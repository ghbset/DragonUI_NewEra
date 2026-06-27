// resolve.js — given the archives found under a WoW Data folder, resolve each DBFilesClient file to
// the WINNING copy by WoW's override order: within a chain, patch letters Z->A, then patch numbers
// high->low, then the unnumbered patch, then base archives; the LOCALE chain overrides the base chain
// (that's where DBFilesClient lives). Loose directory-as-MPQ patches (tswow) are handled too.
(function (root, factory) {
  var MPQ = (root && root.MPQ) || (typeof require === "function" ? require("./mpq.js") : null);
  var api = factory(MPQ);
  if (root) root.Resolve = api;                                             // browser global (window.Resolve)
  if (typeof module === "object" && module.exports) module.exports = api;   // Node
})(typeof globalThis !== "undefined" ? globalThis : (typeof self !== "undefined" ? self : this), function (MPQ) {
  "use strict";

  // Classify an archive filename into a sortable priority {group, kind, value}. Higher wins.
  function classify(fname, locale) {
    var b = fname.replace(/\.mpq$/i, "").toLowerCase();
    var loc = (locale || "").toLowerCase();
    var group = 0;
    if (loc && b.indexOf(loc) >= 0) { group = 1; b = b.replace(new RegExp("-?" + loc, "g"), ""); }
    b = b.replace(/--+/g, "-").replace(/^-|-$/g, "");
    var m, kind = 0, value = 0;
    if (b === "patch") { kind = 1; value = 0; }
    else if ((m = b.match(/^patch-([a-z])$/))) { kind = 3; value = m[1].charCodeAt(0) - 96; }
    else if ((m = b.match(/^patch-(\d+)$/))) { kind = 2; value = parseInt(m[1], 10); }
    else {
      var rank = { locale: 5, base: 4, "expansion-locale": 3, "lichking-locale": 3, expansion: 2, lichking: 2, "common-2": 1, common: 1, backup: 0 };
      kind = 0; value = rank[b] !== undefined ? rank[b] : 0;
    }
    return { group: group, kind: kind, value: value };
  }

  function cmp(a, b) {
    // The letter/number rank dominates (a base letter-patch like patch-C beats the stock locale
    // archives); locale-vs-base is only a tiebreaker within the same rank.
    if (a.kind !== b.kind) return b.kind - a.kind;       // letter > number > unnumbered patch > base
    if (a.value !== b.value) return b.value - a.value;   // Z>..>A ; higher number first
    return b.group - a.group;                            // tiebreak: locale chain over base
  }

  // sources: [{ name, archive }]  where archive is an opened MPQArchive OR a loose-dir adapter
  //          (any object exposing hasFile(path) and readFile(path)).
  // Returns a resolver: { has(file), read(file), info(file) }.
  function make(sources, locale) {
    var ordered = sources.slice().map(function (s) {
      return { name: s.name, archive: s.archive, key: classify(s.name, locale) };
    }).sort(function (a, b) { return cmp(a.key, b.key); });

    return {
      order: ordered.map(function (o) { return o.name; }),
      has: function (file) { return ordered.some(function (o) { return o.archive.hasFile(file); }); },
      info: function (file) { for (var i = 0; i < ordered.length; i++) if (ordered[i].archive.hasFile(file)) return ordered[i].name; return null; },
      read: async function (file) {
        for (var i = 0; i < ordered.length; i++) if (ordered[i].archive.hasFile(file)) return await ordered[i].archive.readFile(file);
        return null;
      },
    };
  }

  return { classify: classify, make: make };
});
