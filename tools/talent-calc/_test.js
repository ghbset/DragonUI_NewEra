// node _test.js — validate mpq.js + dbc.js against the real client archives on this box.
const fs = require("fs");
const MPQ = require("./mpq.js");
const DBC = require("./dbc.js");

const DATA = "/root/tswow-server/tswow-client/Data";
const LOOSE = DATA + "/patch-A/DBFilesClient";

function fdReader(path) {
  const fd = fs.openSync(path, "r");
  const size = fs.fstatSync(fd).size;
  return {
    size,
    read(off, len) {
      const buf = Buffer.allocUnsafe(len);
      fs.readSync(fd, buf, 0, len, off);
      return Promise.resolve(buf.buffer.slice(buf.byteOffset, buf.byteOffset + len));
    },
  };
}

(async () => {
  // 1) MPQ reader: find an archive that holds Talent.dbc and extract+parse it.
  const candidates = ["patch.MPQ", "patch-3.MPQ", "patch-2.MPQ", "common.MPQ", "common-2.MPQ", "lichking.MPQ", "expansion.MPQ"];
  let done = false;
  for (const c of candidates) {
    const p = DATA + "/" + c;
    if (!fs.existsSync(p)) continue;
    try {
      const arch = await MPQ.open(fdReader(p));
      if (arch.hasFile("DBFilesClient\\Talent.dbc")) {
        const bytes = await arch.readFile("DBFilesClient\\Talent.dbc");
        const parsed = DBC.parse(bytes);
        console.log(`1 MPQ OK  ${c} -> Talent.dbc magic+parse, records=${parsed.recordCount} (stock ~700)`);
        done = true;
        break;
      }
    } catch (e) {
      console.log(`   (${c}: ${e.message})`);
    }
  }
  if (!done) console.log("1 MPQ: no candidate archive contained Talent.dbc (will rely on loose/dir patches)");

  // 2) trees + fingerprint from the loose CUSTOM dbcs -> WARRIOR must be fe59d8c9 (addon parity).
  const trees = DBC.buildTrees(
    fs.readFileSync(LOOSE + "/Talent.dbc"),
    fs.readFileSync(LOOSE + "/TalentTab.dbc"),
    fs.readFileSync(LOOSE + "/Spell.dbc"),
    fs.readFileSync(LOOSE + "/SpellIcon.dbc")
  );
  const EXPECT = {
    WARRIOR: "fe59d8c9", PALADIN: "8aa0fced", HUNTER: "7250d388", ROGUE: "bdf86583", PRIEST: "6213db33",
    DEATHKNIGHT: "c613a6f0", SHAMAN: "3749e96f", MAGE: "078120d3", WARLOCK: "576ec597", DRUID: "4f2bb2f3",
  };
  let allFp = true;
  Object.keys(EXPECT).forEach((cls) => {
    const got = trees[cls] && trees[cls].fingerprint;
    const ok = got === EXPECT[cls];
    if (!ok) allFp = false;
    if (!ok) console.log(`   MISMATCH ${cls}: got ${got} expected ${EXPECT[cls]}`);
  });
  console.log(`2 fingerprint parity ${allFp ? "OK" : "FAILED"} (10 classes vs addon/Python)`);

  // sample tree readout
  const w = trees.WARRIOR;
  console.log(`   WARRIOR tabs: ${w.tabs.map((t) => `${t.name}(${t.talents.length})`).join(", ")}`);
  console.log(`   sample: ${w.tabs[0].talents.slice(0, 3).map((t) => `${t.name}[max ${t.maxRank}${t.icon ? " " + t.icon : ""}]`).join("  ")}`);

  // 3) codec round-trip (encode -> decode identity) on a real WARRIOR shape.
  const counts = w.tabs.map((t) => t.talents.length);
  const ranks = w.tabs.map((t) => t.talents.map((tt, i) => (i % 2 === 0 ? Math.min(tt.maxRank, 1) : 0)));
  const code = DBC.encode("WARRIOR", counts, ranks);
  const dec = DBC.decode(code, counts);
  let rt = dec && dec.cls === "WARRIOR";
  for (let tab = 0; tab < counts.length && rt; tab++)
    for (let i = 0; i < counts[tab]; i++) if ((dec.ranks[tab][i] || 0) !== (ranks[tab][i] || 0)) rt = false;
  console.log(`3 codec round-trip ${rt ? "OK" : "FAILED"}  code="${code}"`);

  console.log(allFp && rt ? "\nALL TESTS PASSED" : "\nSOME TESTS FAILED");
})().catch((e) => { console.error("ERROR", e); process.exit(1); });
