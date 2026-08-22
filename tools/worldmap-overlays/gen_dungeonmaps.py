"""Generate modules/worldmap/DungeonMapData.lua from the CLIENT'S OWN DBCs.

WHY THIS EXISTS
---------------
3.3.5a renders instance floor maps perfectly well -- but only while you are STANDING IN the
instance. The map switches to them through SetMapToCurrentZone; `SetMapZoom(continent, zone)` has no
dungeon entries, so there is no way to look at Ulduar's map from Stormwind.

Making them browsable means drawing the tiles ourselves, which needs two things the client has and
does not expose to Lua: which folder a dungeon's art lives in, and how many floors it has.

    WorldMapArea.dbc   id -> areaName, the folder under Interface\\WorldMap\\
    DungeonMap.dbc     one row per FLOOR, keyed by the map it belongs to

NewEra solves the same problem for Era with a 600-line pair of files whose data was discovered by
probing the live client, because Era's instance uiMaps carry no art at all. This client's DBCs
answer it directly, so the table is generated rather than discovered.

USAGE
-----
    python tools/worldmap-overlays/gen_dungeonmaps.py

Point it at a different install with NE_DATA=/path/to/Wow/Data.

WHAT IS LEFT TO RUNTIME
-----------------------
The tile FILENAME convention. A zone's tiles are `<Folder><1..12>`; a multi-floor dungeon's are
`<Folder><floor>_<1..12>`; and a few single-floor dungeons use the zone form despite having a floor
row. Rather than encode a rule with exceptions, the addon probes both forms with SetTexture and
keeps whichever resolves -- an existence check that costs one texture object and cannot be wrong.
"""

import os
import re
import struct
import glob
import sys

try:
    from mpyq import MPQArchive
except ImportError:
    sys.exit("mpyq is required:  pip install mpyq")

DATA = os.environ.get("NE_DATA") or next(
    (p for p in (r"D:/Triumvirate/Data", r"D:/Project Reforged 3.3.5a/Data")
     if os.path.isdir(p)), r"D:/Triumvirate/Data")

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "modules", "worldmap", "DungeonMapData.lua"))

LOCALE_ORDER = ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]
NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_'\- ]{1,60}$")


def lq(t):
    """A Lua string literal. (Lua's %q is not Python's.)"""
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'



def archives():
    out = []
    for name in LOCALE_ORDER:
        p = os.path.join(DATA, "enUS", name)
        if os.path.exists(p):
            out.append(p)
    out += sorted(glob.glob(os.path.join(DATA, "*.MPQ")) + glob.glob(os.path.join(DATA, "*.mpq")))
    return out


def read_dbc(name, required=True):
    best, src = None, None
    for p in archives():
        try:
            d = MPQArchive(p).read_file("DBFilesClient\\" + name)
        except Exception:
            continue
        if d:
            best, src = d, os.path.basename(p)
    if not best and required:
        sys.exit("could not find DBFilesClient\\%s under %s" % (name, DATA))
    return best, src


class DBC(object):
    def __init__(self, blob):
        magic, self.rows, self.fields, self.rowsize, _ = struct.unpack("<4siiii", blob[:20])
        if magic != b"WDBC":
            sys.exit("not a DBC (magic %r)" % magic)
        body = blob[20:20 + self.rows * self.rowsize]
        self.strings = blob[20 + self.rows * self.rowsize:]
        self.ints = [struct.unpack("<%di" % self.fields, body[i * self.rowsize:(i + 1) * self.rowsize])
                     for i in range(self.rows)]
        self.floats = [struct.unpack("<%df" % self.fields, body[i * self.rowsize:(i + 1) * self.rowsize])
                       for i in range(self.rows)]

    def s(self, off):
        if off <= 0 or off >= len(self.strings):
            return ""
        end = self.strings.find(b"\0", off)
        return self.strings[off:end].decode("utf-8", "replace")


def detect_string_col(dbc, sample=250, want=0.6):
    """See gen_overlays.py -- identified from the data, not assumed."""
    best, best_score = None, 0.0
    for col in range(dbc.fields):
        hits, seen = 0, 0
        for row in dbc.ints[:sample]:
            v = row[col]
            if v == 0:
                continue
            seen += 1
            t = dbc.s(v)
            if t and NAME_RE.match(t):
                hits += 1
        if seen and hits / float(seen) > best_score:
            best, best_score = col, hits / float(seen)
    assert best is not None and best_score >= want, \
        "no string column found (best %s at %.2f)" % (best, best_score)
    return best


def main():
    print("client: %s" % DATA)

    wma_blob, wma_src = read_dbc("WorldMapArea.dbc")
    dm_blob, dm_src = read_dbc("DungeonMap.dbc")
    wma, dm = DBC(wma_blob), DBC(dm_blob)
    print("  WorldMapArea.dbc  %d rows, %d fields  (%s)" % (wma.rows, wma.fields, wma_src))
    print("  DungeonMap.dbc    %d rows, %d fields  (%s)" % (dm.rows, dm.fields, dm_src))

    name_col = detect_string_col(wma)

    # WorldMapArea rows: id, mapID (the instance/continent this art belongs to), areaID, folder.
    # The mapID column is the one whose values repeat heavily and are small -- a continent or
    # instance id -- and which is not the id column or the name column.
    map_col = None
    for col in range(wma.fields):
        if col in (0, name_col):
            continue
        vals = [r[col] for r in wma.ints]
        if all(0 <= v < 10000 for v in vals) and len(set(vals)) < wma.rows * 0.9:
            map_col = col
            break
    assert map_col is not None, "could not identify WorldMapArea's mapID column"
    print("  columns: name=%d mapID=%d" % (name_col, map_col))

    by_map = {}          # mapID -> folder (the instance's own art directory)
    folder_of_area = {}  # WorldMapArea.id -> folder
    for row in wma.ints:
        t = wma.s(row[name_col])
        if not t:
            continue
        folder_of_area[row[0]] = t
        by_map.setdefault(row[map_col], t)

    # DungeonMap: one row per floor. Column 1 is the mapID; the floor index is the small
    # monotonically-increasing column beside it.
    dm_map_col, dm_floor_col = None, None
    for col in range(1, dm.fields):
        vals = [r[col] for r in dm.ints]
        if all(0 <= v < 10000 for v in vals):
            if dm_map_col is None and len(set(vals)) > 5:
                dm_map_col = col
            elif dm_floor_col is None and max(vals) <= 64:
                dm_floor_col = col
                break
    assert dm_map_col is not None and dm_floor_col is not None, \
        "could not identify DungeonMap's mapID / floor columns"
    print("  DungeonMap columns: mapID=%d floor=%d" % (dm_map_col, dm_floor_col))

    floors = {}
    for row in dm.ints:
        mid, fl = row[dm_map_col], row[dm_floor_col]
        folder = by_map.get(mid)
        if not folder:
            continue
        floors.setdefault(folder, set()).add(fl)

    out = {k: sorted(v) for k, v in floors.items() if v}
    print("  -> %d maps with floor data, %d floors total"
          % (len(out), sum(len(v) for v in out.values())))

    L = []
    L.append("-- DragonUI_NewEra/modules/worldmap/DungeonMapData.lua")
    L.append("--")
    L.append("-- GENERATED. Do not hand-edit -- re-run tools/worldmap-overlays/gen_dungeonmaps.py.")
    L.append("--")
    L.append("-- Which art folder each instance's floor maps live in, and how many floors it has,")
    L.append("-- joined from this client's own WorldMapArea.dbc (%s) and DungeonMap.dbc (%s)."
             % (wma_src, dm_src))
    L.append("--")
    L.append("-- The client renders these itself, but ONLY while the player is standing inside the")
    L.append("-- instance -- SetMapZoom has no dungeon entries, so there is no way to look at a")
    L.append("-- dungeon's map from outside it. This is what lets the map browse to one.")
    L.append("--")
    L.append("-- The tile FILENAME is deliberately not encoded here. A zone's tiles are")
    L.append("-- `<Folder><1..12>`, a multi-floor dungeon's are `<Folder><floor>_<1..12>`, and a few")
    L.append("-- single-floor dungeons use the zone form anyway -- so DungeonMap.lua probes both with")
    L.append("-- SetTexture and keeps whichever resolves, rather than encoding a rule with exceptions.")
    L.append("")
    L.append("local NE = DragonUI_NewEra")
    L.append("if not NE or NE.disabled then return end")
    L.append("")
    L.append("NE.worldmap = NE.worldmap or {}")
    L.append("")
    L.append("-- folder -> ordered list of floor indices.")
    L.append("NE.worldmap.dungeonFloors = {")
    for folder in sorted(out):
        L.append("  [%s] = { %s }," % (lq(folder), ", ".join(str(f) for f in out[folder])))
    L.append("}")
    L.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print("wrote %s (%d lines)" % (OUT, len(L)))


if __name__ == "__main__":
    main()
