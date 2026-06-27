// dbc.js — WoW 3.3.5a DBC parsing + talent-tree assembly + fingerprint + Talented-format codec.
// Browser + Node. The fingerprint + codec MUST stay byte-identical to the addon
// (modules/talents/Loadouts.lua) so builds round-trip between this calculator and the in-game addon.
(function (root, factory) {
  var api = factory();
  if (root) root.DBC = api;                                                 // browser global (window.DBC)
  if (typeof module === "object" && module.exports) module.exports = api;   // Node
})(typeof globalThis !== "undefined" ? globalThis : (typeof self !== "undefined" ? self : this), function () {
  "use strict";

  // ---- generic DBC (WDBC) reader -----------------------------------------------------------------
  function parse(bytes) {
    var dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (dv.getUint32(0, true) !== 0x43424457) throw new Error("not a WDBC file");
    var recordCount = dv.getUint32(4, true);
    var fieldCount = dv.getUint32(8, true);
    var recordSize = dv.getUint32(12, true);
    var stringSize = dv.getUint32(16, true);
    var recBase = 20;
    var strBase = 20 + recordCount * recordSize;
    function u32(rec, field) { return dv.getUint32(recBase + rec * recordSize + field * 4, true); }
    function f32(rec, field) { return dv.getFloat32(recBase + rec * recordSize + field * 4, true); }
    function str(off) {
      if (!off || off >= stringSize) return "";
      var s = "", b, p = strBase + off;
      while ((b = dv.getUint8(p++)) !== 0) s += String.fromCharCode(b);
      return s;
    }
    return { recordCount: recordCount, fieldCount: fieldCount, u32: u32, f32: f32, str: str };
  }

  var CLASS_BIT = {
    0x1: "WARRIOR", 0x2: "PALADIN", 0x4: "HUNTER", 0x8: "ROGUE", 0x10: "PRIEST",
    0x20: "DEATHKNIGHT", 0x40: "SHAMAN", 0x80: "MAGE", 0x100: "WARLOCK", 0x400: "DRUID",
  };
  var SPELL_NAME_FIELD = 136; // enUS SpellName_Lang in 3.3.5a Spell.dbc
  var SPELL_ICON_FIELD = 133; // SpellIconID
  var SPELL_DESC_FIELD = 170; // enUS SpellDescription_Lang
  var SPELL_DURIDX_FIELD = 40; // DurationIndex -> SpellDuration.dbc
  var EFF_BASEPOINTS = [80, 81, 82];  // EffectBasePoints[1..3]

  function secs(ms) {
    if (!ms || ms <= 0) return "0 sec";
    var s = ms / 1000;
    if (s >= 60 && s % 60 === 0) return (s / 60) + " min";
    return (Number.isInteger(s) ? s : Math.round(s * 10) / 10) + " sec";
  }

  // Comprehensive WoW tooltip placeholder substitution. `ctx` exposes per-spell lookups (closed over
  // all of Spell.dbc + SpellDuration in buildTrees): ctx.val(id,eff), ctx.durMs(id), ctx.ampMs(id,eff),
  // ctx.proc(id), ctx.stack(id), ctx.charges(id), ctx.chain(id). `selfId` = the spell being described.
  //   $sN/$SN/$mN/$MN  effect value      $/D;sN  divided        $<id>sN/$<id>mN  referenced effect value
  //   $d/$D/$<id>d      duration          $tN/$TN/$<id>tN  periodic time       $h/$<id>h  proc chance
  //   $uN/$u/$<id>u     stack count       $n/$<id>n  charges    $xN/$i/$<id>i    chain/target count
  //   ${ ... }          math expression   $g a:b;  gender       $l a:b;  plural   $b  line break
  // Anything left (radius $a, $<named> variables, and math using live stats like $AP/$SPH) is rendered
  // readably — those need live character data that doesn't exist offline.
  function substituteDesc(desc, selfId, ctx) {
    if (!desc) return "";
    function self(){ return selfId; }
    function num(v){ return (typeof v === "number" && isFinite(v)) ? v : 0; }

    // resolve a single scalar token (without the leading $), e.g. "s1", "12345d", "m2", "tN", "h"
    function scalar(tok) {
      var m;
      if ((m = tok.match(/^(\d+)?([smSM])(\d)$/)))   return String(num(ctx.val(m[1] ? +m[1] : self(), +m[3])));
      if ((m = tok.match(/^(\d+)?[dD]$/)))            return secs(ctx.durMs(m[1] ? +m[1] : self()));
      if ((m = tok.match(/^(\d+)?[tT](\d)$/)))        return secs(ctx.ampMs(m[1] ? +m[1] : self(), +m[2]));
      if ((m = tok.match(/^(\d+)?[aA](\d)?$/)))        return String(Math.round(num(ctx.radius(m[1] ? +m[1] : self(), +m[2] || 1))));
      if ((m = tok.match(/^(\d+)?[oO](\d)$/)))        return String(num(ctx.val(m[1] ? +m[1] : self(), +m[2])));
      if ((m = tok.match(/^(\d+)?h$/)))               return String(num(ctx.proc(m[1] ? +m[1] : self())));
      if ((m = tok.match(/^(\d+)?[un]$/)))            return String(num(ctx.stack(m[1] ? +m[1] : self())) || num(ctx.charges(m[1] ? +m[1] : self())));
      if ((m = tok.match(/^(\d+)?[ixX]\d?$/)))        return String(num(ctx.chain(m[1] ? +m[1] : self())));
      return null;
    }

    var out = desc;
    // 0) conditionals  $?cond[a][b] -> the first (true) branch (the common case in talent text)
    out = out.replace(/\$\?[^\[]*\[([^\]]*)\]\[([^\]]*)\]/g, "$1")
             .replace(/\$\?[^\[]*\[([^\]]*)\]/g, "$1");
    // Render an expression that still has live-stat vars: split into +/- terms; evaluate the numeric
    // ones (157*5 -> 785) and turn "coef * $STAT" into "X% of <stat>" (e.g. $RAP*0.1 -> 10% of ranged
    // attack power). Result reads like "785 plus 10% of ranged attack power".
    function evalNum(str) { try { var v = Function('"use strict";return (' + str + ')')(); return isFinite(v) ? v : null; } catch (x) { return null; } }
    function renderMath(e) {
      var terms = e.match(/[+\-]?[^+\-]+/g) || [e], parts = [];
      for (var k = 0; k < terms.length; k++) {
        var raw = terms[k].trim(), sign = "";
        if (raw[0] === "+" || raw[0] === "-") { sign = raw[0]; raw = raw.slice(1).trim(); }
        if (!raw) continue;
        var sm = raw.match(/\$<?([A-Za-z]\w*)>?/), piece;
        if (!sm) {
          var v = /^[\d.+\-*/() ]+$/.test(raw) ? evalNum(raw) : null;
          piece = (v === null) ? raw : String(Math.round(v));
        } else {
          var word = STAT_WORDS[sm[1].toLowerCase()] || sm[1];
          var coefExpr = raw.replace(/\$<?[A-Za-z]\w*>?/, "1");
          var coef = /^[\d.+\-*/() ]+$/.test(coefExpr) ? evalNum(coefExpr) : null;
          piece = (coef === null) ? raw.replace(/\$<?([A-Za-z]\w*)>?/g, function (_2, w) { return STAT_WORDS[w.toLowerCase()] || w; })
                : (coef === 1 ? "your " + word : (Math.round(coef * 1000) / 10) + "% of " + word);
        }
        parts.push(parts.length === 0 ? (sign === "-" ? "-" : "") + piece : (sign === "-" ? "minus " : "plus ") + piece);
      }
      return parts.join(" ");
    }

    // 1) math expressions ${ ... }
    out = out.replace(/\$\{([^}]*)\}/g, function (_, expr) {
      var e = expr
        .replace(/\$(\d+)?([smSM])(\d)/g, function (_2, id, c, n) { return String(num(ctx.val(id ? +id : self(), +n))); })
        .replace(/\$(\d+)?[dD]/g, function (_2, id) { return String(ctx.durMs(id ? +id : self()) / 1000); })
        .replace(/\$h/g, function () { return String(num(ctx.proc(self()))); })
        .replace(/\$[ix]\d?/g, function () { return String(num(ctx.chain(self()))); });
      if (/^[-+*/().\d\s]+$/.test(e)) {                 // pure arithmetic -> evaluate
        var r = evalNum(e); if (r !== null) return String(Math.round(r * 100) / 100);
      }
      return renderMath(e);                             // mixed numeric + live stats
    });
    // 2) divided / multiplied value  $/D;[<id>]sN  or  $*D;[<id>]sN  (s or o effect)
    out = out.replace(/\$([/*])(\d+);(\d+)?([sSoO])(\d)/g, function (_, op, D, id, c, n) {
      var v = num(ctx.val(id ? +id : self(), +n));
      return String(Math.round(op === "/" ? v / +D : v * +D));
    });
    // 3) gender / plural / line break
    out = out.replace(/\$[gG]\s*([^:;]*):([^;]*);?/g, "$1")
             .replace(/\$[lL]\s*([^:;]*):([^;]*);?/g, "$2")
             .replace(/\$b/gi, " ");
    // 4) scalar tokens $<...>  (longest match first: optional spellid, letter, optional digit)
    out = out.replace(/\$(\d+)?([a-zA-Z])(\d)?/g, function (whole, id, c, n) {
      var r = scalar((id || "") + c + (n || ""));
      return r === null ? whole : r;
    });
    // 5) named variables $<name> and any leftover $codes -> readable / stripped
    out = out.replace(/\$<([^>]*)>/g, function (_, w) { return STAT_WORDS[w.toLowerCase()] || w; })
             .replace(/\$\{[^}]*\}/g, "").replace(/\$\w+/g, "");
    return out.replace(/\s{2,}/g, " ").trim();
  }
  // Live-character stat variables that can't be computed offline — render as words.
  var STAT_WORDS = { ap: "attack power", rap: "ranged attack power", sph: "spell power", spd: "spell power",
    mw: "min weapon damage", mwb: "max weapon damage", pl: "level", bonus: "bonus", heal: "healing",
    mana: "mana", percent: "%", threat: "threat", mult: "multiplier" };

  // Assemble per-class trees from the four DBCs (Uint8Array each). spellDbc/spellIconDbc optional
  // (names/icons); without them talents fall back to "#<id>" and no icon.
  function buildTrees(talentBytes, talentTabBytes, spellBytes, spellIconBytes, spellDurationBytes, spellRadiusBytes) {
    var TT = parse(talentTabBytes);
    var tabs = {};
    for (var i = 0; i < TT.recordCount; i++) {
      tabs[TT.u32(i, 0)] = { cls: CLASS_BIT[TT.u32(i, 20)] || null, order: TT.u32(i, 22), name: TT.str(TT.u32(i, 1)) };
    }

    var T = parse(talentBytes);
    var talents = [], needSpells = {};
    for (var r = 0; r < T.recordCount; r++) {
      var ranks = [];
      for (var k = 0; k < 9; k++) ranks.push(T.u32(r, 4 + k));
      var maxRank = 0; for (var z = 0; z < 9; z++) if (ranks[z]) maxRank++;
      var prereq = [T.u32(r, 13), T.u32(r, 14), T.u32(r, 15)];
      var prereqRank = [T.u32(r, 16), T.u32(r, 17), T.u32(r, 18)];
      var t = {
        id: T.u32(r, 0), tab: T.u32(r, 1), tier: T.u32(r, 2), col: T.u32(r, 3),
        maxRank: maxRank, ranks: ranks, prereq: prereq, prereqRank: prereqRank,
        name: "#" + T.u32(r, 0), icon: null,
      };
      talents.push(t);
      for (var nk = 0; nk < 9; nk++) if (ranks[nk]) needSpells[ranks[nk]] = 1;   // every rank's spell
    }

    // name/icon/desc for talent rank spells, plus the per-spell numbers placeholders may reference
    // (for ALL spells, since $<id>... can point anywhere). sd[id] = { bp, di, amp, proc, charges, stack, chain }.
    var iconIds = {};
    if (spellBytes) {
      var S = parse(spellBytes), info = {}, sd = {};
      for (var s = 0; s < S.recordCount; s++) {
        var id = S.u32(s, 0);
        sd[id] = {
          bp: [S.u32(s, 80) | 0, S.u32(s, 81) | 0, S.u32(s, 82) | 0],
          di: S.u32(s, SPELL_DURIDX_FIELD),
          amp: [S.u32(s, 98), S.u32(s, 99), S.u32(s, 100)],
          rad: [S.u32(s, 92), S.u32(s, 93), S.u32(s, 94)],
          proc: S.u32(s, 35), charges: S.u32(s, 36), stack: S.u32(s, 49), chain: S.u32(s, 104),
        };
        if (needSpells[id]) info[id] = { name: S.str(S.u32(s, SPELL_NAME_FIELD)), icon: S.u32(s, SPELL_ICON_FIELD), desc: S.str(S.u32(s, SPELL_DESC_FIELD)) };
      }
      var durByIndex = {};
      if (spellDurationBytes) { var SD = parse(spellDurationBytes); for (var d = 0; d < SD.recordCount; d++) durByIndex[SD.u32(d, 0)] = SD.u32(d, 1); }
      var radByIndex = {};
      if (spellRadiusBytes) { var SR = parse(spellRadiusBytes); for (var rr = 0; rr < SR.recordCount; rr++) radByIndex[SR.u32(rr, 0)] = SR.f32(rr, 1); }
      function g(id) { return sd[id] || { bp: [0, 0, 0], di: 0, amp: [0, 0, 0], rad: [0, 0, 0], proc: 0, charges: 0, stack: 0, chain: 0 }; }
      var ctx = {
        val: function (id, eff) { return Math.abs((g(id).bp[eff - 1] || 0) + 1); },
        durMs: function (id) { return durByIndex[g(id).di] || 0; },
        ampMs: function (id, eff) { return g(id).amp[eff - 1] || 0; },
        radius: function (id, eff) { var r = g(id).rad; return radByIndex[r[(eff || 1) - 1]] || radByIndex[r[0]] || 0; },
        proc: function (id) { return g(id).proc || 0; },
        stack: function (id) { return g(id).stack || 0; },
        charges: function (id) { return g(id).charges || 0; },
        chain: function (id) { return g(id).chain || 0; },
      };
      for (var ti = 0; ti < talents.length; ti++) {
        var rks = talents[ti].ranks, r1 = info[rks[0]];
        if (r1) { talents[ti].name = r1.name; if (r1.icon) { talents[ti].iconId = r1.icon; iconIds[r1.icon] = 1; } }
        var tips = [];
        for (var rk = 0; rk < 9; rk++) { var sid = rks[rk]; if (!sid) break; var si = info[sid]; tips.push(si ? substituteDesc(si.desc, sid, ctx) : ""); }
        talents[ti].tooltips = tips;
      }
    }
    // icon texture paths from SpellIcon.dbc
    if (spellIconBytes) {
      var SI = parse(spellIconBytes), pathById = {};
      for (var ic = 0; ic < SI.recordCount; ic++) pathById[SI.u32(ic, 0)] = SI.str(SI.u32(ic, 1));
      for (var tj = 0; tj < talents.length; tj++) if (talents[tj].iconId) talents[tj].icon = pathById[talents[tj].iconId] || null;
    }

    // group by class -> ordered tabs -> talents
    var byClass = {};
    for (var p = 0; p < talents.length; p++) {
      var tb = tabs[talents[p].tab];
      if (!tb || !tb.cls) continue;
      (byClass[tb.cls] = byClass[tb.cls] || {});
      (byClass[tb.cls][talents[p].tab] = byClass[tb.cls][talents[p].tab] || []).push(talents[p]);
    }
    var classes = {};
    Object.keys(byClass).forEach(function (cls) {
      var tabIds = Object.keys(byClass[cls]).map(Number).sort(function (a, b) { return tabs[a].order - tabs[b].order; });
      var outTabs = tabIds.map(function (id) {
        var list = byClass[cls][id].slice().sort(byTierCol);
        return { id: id, name: tabs[id].name, talents: list };
      });
      classes[cls] = { tabs: outTabs };
      classes[cls].fingerprint = fingerprint(cls, outTabs);
    });
    return classes;
  }

  function byTierCol(a, b) { return a.tier !== b.tier ? a.tier - b.tier : a.col - b.col; }

  // ---- fingerprint (must match Loadouts.lua fingerprintOf) ---------------------------------------
  function djb2(str) {
    var h = 5381;
    for (var i = 0; i < str.length; i++) h = (h * 33 + (str.charCodeAt(i) & 0xff)) % 4294967296;
    return ("0000000" + h.toString(16)).slice(-8);
  }
  function fingerprint(cls, outTabs) {
    var parts = [cls];
    for (var t = 0; t < outTabs.length; t++) {
      var list = outTabs[t].talents; // already sorted by (tier,col)
      var minT = Infinity, minC = Infinity;
      for (var i = 0; i < list.length; i++) { if (list[i].tier < minT) minT = list[i].tier; if (list[i].col < minC) minC = list[i].col; }
      if (!isFinite(minT)) minT = 0; if (!isFinite(minC)) minC = 0;
      parts.push("n" + list.length);
      for (var j = 0; j < list.length; j++) parts.push((list[j].tier - minT) + "," + (list[j].col - minC) + "," + list[j].maxRank);
    }
    return djb2(parts.join("|"));
  }

  // ---- Talented-format codec (must match Loadouts.lua). ranks: per-tab arrays in (tier,col) order.
  var MAP_URL = "0zMcmVokRsaqbdrfwihuGINALpTjnyxtgevE";
  var STOP = "Z";
  var CLASSMAP = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "DEATHKNIGHT"];

  function rtrim(s, c) { var l = s.length; while (l > 0 && s[l - 1] === c) l--; return s.slice(0, l); }

  // counts: array of per-tab talent counts (sorted (tier,col) order). ranks[tab] = array of ranks.
  function encode(cls, counts, ranks, map) {
    map = map || MAP_URL;
    var ci = CLASSMAP.indexOf(cls); if (ci < 0) return null;
    var ccode = map[ci * 3];
    var zero = map[0], code = "";
    for (var tab = 0; tab < counts.length; tab++) {
      var r = ranks[tab] || [], idx = 0;
      while (idx < counts[tab]) {
        var r1 = r[idx] || 0, r2 = idx + 1 < counts[tab] ? (r[idx + 1] || 0) : 0;
        code += map[r1 * 6 + r2];
        idx += 2;
      }
      var nc = rtrim(code, zero);
      if (nc !== code) code = nc + STOP;
    }
    return ccode + rtrim(code, STOP);
  }

  function classFromChar(map, ch) {
    var p = map.indexOf(ch); if (p < 0) return null;
    return CLASSMAP[Math.floor(p / 3)] || null;
  }

  function decode(code, counts, map) {
    map = map || MAP_URL;
    var cls = classFromChar(map, code[0]); if (!cls) return null;
    var ranks = [[]], tab = 0, cnt = counts[0] || 0, t = ranks[0];
    function nextTab() { tab++; ranks[tab] = []; t = ranks[tab]; cnt = counts[tab] || 0; }
    for (var i = 1; i < code.length; i++) {
      var ch = code[i];
      if (ch === STOP) { if (t.length >= cnt) nextTab(); nextTab(); }
      else {
        var v = map.indexOf(ch); if (v < 0) return null;
        var b = v % 6, a = (v - b) / 6;
        if (t.length >= cnt) nextTab();
        t.push(a);
        if (t.length < cnt) t.push(b);
      }
    }
    for (var tb = 0; tb < counts.length; tb++) { ranks[tb] = ranks[tb] || []; for (var z = 0; z < counts[tb]; z++) ranks[tb][z] = ranks[tb][z] || 0; }
    return { cls: cls, ranks: ranks };
  }

  return {
    parse: parse, buildTrees: buildTrees, fingerprint: fingerprint, djb2: djb2,
    encode: encode, decode: decode, CLASS_BIT: CLASS_BIT,
  };
});
