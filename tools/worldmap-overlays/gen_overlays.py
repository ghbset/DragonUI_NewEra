"""Generate modules/worldmap/OverlayData.lua from the CLIENT'S OWN WorldMapOverlay.dbc.

WHY THIS EXISTS
---------------
Fog of war on 3.3.5a is not a fog layer that gets removed. The map's base art is mostly empty, and
the client lays one OVERLAY per subzone you have DISCOVERED on top of it. `GetNumMapOverlays()`
only ever reports what the current character has found, and no API enumerates the rest — so
revealing an unexplored subzone at all requires knowing it exists, which requires a table.

Mapster ships one, hand-written, ~1000 lines, and only as complete as somebody bothered to make it.
The client ships the real thing: `WorldMapOverlay.dbc`, 988 rows, with every subzone overlay's
texture name, size and offset. This reads that.

Same approach, and the same reasons, as tools/cdm-spellgen: a table generated from the player's own
client is correct for the client it will run on, needs nobody's permission, and cannot drift from a
server's own content the way a table copied from retail data does.

USAGE
-----
    python tools/worldmap-overlays/gen_overlays.py

Point it at a different install with NE_DATA=/path/to/Wow/Data. Writes
modules/worldmap/OverlayData.lua.

WHAT IT DOES NOT DO
-------------------
It does not guess the DBC's column order. Field layouts for 3.3.5a DBCs are folklore that varies
between references, and a wrong guess here does not error — it produces a table of plausible
nonsense that puts subzone art in the wrong place. Every column is IDENTIFIED from the data itself
(see `detect_*` below) and the detection is asserted, so a client whose layout differs fails loudly
instead of shipping garbage.
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
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "modules", "worldmap", "OverlayData.lua"))

LOCALE_ORDER = ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]


# ── MPQ / DBC ───────────────────────────────────────────────────────────────────────────────────

def archives():
    """Lowest priority first, so a later hit overwrites an earlier one — patches win over base."""
    out = []
    for name in LOCALE_ORDER:
        p = os.path.join(DATA, "enUS", name)
        if os.path.exists(p):
            out.append(p)
    # A server's own patches can override any DBC, and they sort after the stock ones.
    out += sorted(glob.glob(os.path.join(DATA, "*.MPQ")) + glob.glob(os.path.join(DATA, "*.mpq")))
    return out


def read_dbc(name):
    best, src = None, None
    for p in archives():
        try:
            d = MPQArchive(p).read_file("DBFilesClient\\" + name)
        except Exception:
            continue
        if d:
            best, src = d, os.path.basename(p)
    if not best:
        sys.exit("could not find DBFilesClient\\%s under %s" % (name, DATA))
    return best, src


class DBC(object):
    def __init__(self, blob):
        magic, self.rows, self.fields, self.rowsize, strsize = struct.unpack("<4siiii", blob[:20])
        if magic != b"WDBC":
            sys.exit("not a DBC (magic %r)" % magic)
        body = blob[20:20 + self.rows * self.rowsize]
        self.strings = blob[20 + self.rows * self.rowsize:]
        self.ints = [struct.unpack("<%di" % self.fields, body[i * self.rowsize:(i + 1) * self.rowsize])
                     for i in range(self.rows)]

    def s(self, off):
        if off <= 0 or off >= len(self.strings):
            return ""
        end = self.strings.find(b"\0", off)
        return self.strings[off:end].decode("utf-8", "replace")


# ── column detection ────────────────────────────────────────────────────────────────────────────
#
# Identified from the data, never assumed. Each detector states what it is looking for so that a
# client whose layout differs fails on the assert with something readable.

NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9_'\- ]{1,60}$")


def lq(t):
    """A Lua string literal. (Lua's %q is not Python's -- that cost one run.)"""
    return '"' + t.replace("\\", "\\\\").replace('"', '\\"') + '"'



def detect_string_col(dbc, sample=None, want=0.5):
    """The column of string offsets, found by DISTINCTNESS rather than by resolvability.

    Resolvability alone does not work here, and two runs proved it. A DBC's string offsets are just
    integers, and so are its areaIDs, dimensions and hit rects -- any small integer indexes into the
    string block as happily as a real offset does, landing mid-string and resolving to a suffix that
    reads like a name ("urotar"). The first attempt picked an areaID column; the second, tightened,
    picked an offsetY.

    What actually separates them is that every row has its OWN texture name, so a real string column
    resolves to almost as many DISTINCT strings as there are rows -- while a dimensions column
    resolves to a handful of values repeated hundreds of times.
    """
    best, best_score = None, 0.0
    for col in range(dbc.fields):
        seen = set()
        for row in dbc.ints:
            v = row[col]
            if v <= 0:
                continue
            t = dbc.s(v)
            if t and NAME_RE.match(t):
                seen.add(t)
        score = len(seen) / float(dbc.rows)
        if score > best_score:
            best, best_score = col, score
    assert best is not None and best_score >= want,         "no string column found (best %s at %.2f distinct/row)" % (best, best_score)
    return best, best_score


def detect_pixel_run(dbc, after):
    """The four consecutive columns after the texture name: width, height, offsetX, offsetY.

    Structural, because the DBC stores them immediately after the name it describes. Bounded by the
    map child (1002x668, rounded to 1024). NOT filtered on being populated -- a couple of hundred
    rows in this table are placeholders with a zero width, and requiring the column to be non-zero
    almost everywhere pushed the detector past them onto the hit-rect block that follows.
    """
    ok_cols = []
    for col in range(dbc.fields):
        vals = [r[col] for r in dbc.ints]
        if all(0 <= v <= 1024 for v in vals):
            ok_cols.append(col)
    for start in ok_cols:
        if start <= after:
            continue
        if all((start + k) in ok_cols for k in range(4)):
            return start, start + 1, start + 2, start + 3
    raise AssertionError("could not find four consecutive pixel columns after column %d" % after)


def main():
    print("client: %s" % DATA)

    ov_blob, ov_src = read_dbc("WorldMapOverlay.dbc")
    wma_blob, wma_src = read_dbc("WorldMapArea.dbc")
    ov, wma = DBC(ov_blob), DBC(wma_blob)
    print("  WorldMapOverlay.dbc  %d rows, %d fields   (%s)" % (ov.rows, ov.fields, ov_src))
    print("  WorldMapArea.dbc     %d rows, %d fields   (%s)" % (wma.rows, wma.fields, wma_src))

    # WorldMapArea: id -> the texture FOLDER name. That folder name is exactly what GetMapInfo()
    # returns at runtime, which is what makes it the join key between this table and the addon.
    wma_name_col, wma_score = detect_string_col(wma)
    area_folder = {}
    for row in wma.ints:
        t = wma.s(row[wma_name_col])
        if t:
            area_folder[row[0]] = t
    print("  folder names: %d  (column %d, %.2f distinct/row)"
          % (len(area_folder), wma_name_col, wma_score))

    # WorldMapOverlay: the texture name, then the four pixel columns that follow it.
    ov_name_col, ov_score = detect_string_col(ov)
    w_col, h_col, x_col, y_col = detect_pixel_run(ov, after=ov_name_col)
    print("  columns: name=%d (%.2f distinct/row) width=%d height=%d offsetX=%d offsetY=%d"
          % (ov_name_col, ov_score, w_col, h_col, x_col, y_col))

    # The mapAreaID column: values that are WorldMapArea ids, and not the ones we already claimed.
    map_col = None
    for col in range(ov.fields):
        if col in (ov_name_col, w_col, h_col, x_col, y_col) or col == 0:
            continue
        hits = sum(1 for r in ov.ints if r[col] in area_folder)
        if hits > ov.rows * 0.9:
            map_col = col
            break
    assert map_col is not None, "could not identify the mapAreaID column"
    print("  mapAreaID column: %d" % map_col)

    # ── build ───────────────────────────────────────────────────────────────────────────────────
    # Packed exactly as modules/worldmap/FogClear.lua packs a harvested overlay, so the seed and the
    # harvest are the same kind of value and can be read by one renderer.
    out = {}
    skipped_fit, skipped_junk, skipped_map = 0, 0, 0
    for row in ov.ints:
        folder = area_folder.get(row[map_col])
        if not folder:
            skipped_map += 1
            continue
        name = ov.s(row[ov_name_col])
        w, h, x, y = row[w_col], row[h_col], row[x_col], row[y_col]
        if not name or name.lower() == "pixelfix" or w <= 0 or h <= 0:
            skipped_junk += 1
            continue
        if not (0 <= w < 1024 and 0 <= h < 1024 and 0 <= x < 1024 and 0 <= y < 1024):
            # The packing is four 10-bit fields. Nothing in a stock client trips this; a row that
            # does is reported rather than silently truncated into a wrong position.
            print("  !! out of range, skipped: %s/%s  %dx%d @%d,%d" % (folder, name, w, h, x, y))
            skipped_fit += 1
            continue
        out.setdefault(folder, {})[name] = w + h * (2 ** 10) + x * (2 ** 20) + y * (2 ** 30)

    total = sum(len(v) for v in out.values())
    print("  -> %d maps, %d overlays  (skipped: %d junk, %d unmapped, %d out of range)"
          % (len(out), total, skipped_junk, skipped_map, skipped_fit))

    # ── emit ────────────────────────────────────────────────────────────────────────────────────
    L = []
    L.append("-- DragonUI_NewEra/modules/worldmap/OverlayData.lua")
    L.append("--")
    L.append("-- GENERATED. Do not hand-edit -- re-run tools/worldmap-overlays/gen_overlays.py.")
    L.append("--")
    L.append("-- Every subzone overlay this client knows about, read from its own")
    L.append("-- WorldMapOverlay.dbc (%d rows, %s) joined to WorldMapArea.dbc (%s) for the texture"
             % (ov.rows, ov_src, wma_src))
    L.append("-- folder name -- which is what GetMapInfo() returns at runtime, and so is the key.")
    L.append("--")
    L.append("-- This is what lets the map show ground nobody on the account has walked. Without it")
    L.append("-- FogClear can only redraw what it has watched somebody discover, because")
    L.append("-- GetNumMapOverlays() reports only the current character's own discoveries and no API")
    L.append("-- enumerates the rest.")
    L.append("--")
    L.append("-- Values are packed exactly as FogClear packs a harvested overlay:")
    L.append("--     width + height * 2^10 + offsetX * 2^20 + offsetY * 2^30")
    L.append("-- so a seeded entry and a harvested one are the same kind of thing to the renderer.")
    L.append("")
    L.append("local NE = DragonUI_NewEra")
    L.append("if not NE or NE.disabled then return end")
    L.append("")
    L.append("NE.worldmap = NE.worldmap or {}")
    L.append("")
    L.append("-- %d maps, %d subzone overlays." % (len(out), total))
    L.append("NE.worldmap.overlaySeed = {")
    for folder in sorted(out):
        subs = out[folder]
        L.append("  [%s] = {" % lq(folder))
        for name in sorted(subs):
            L.append("    [%s] = %d," % (lq(name), subs[name]))
        L.append("  },")
    L.append("}")
    L.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print("wrote %s (%d lines)" % (OUT, len(L)))


if __name__ == "__main__":
    main()
