// Lua 5.1 gate. Usage: node check.js <file.lua> [...]
//
// Two passes:
//   1. SYNTAX — luaparse at Lua 5.1, standing in for the luac this box does not have.
//   2. FORWARD REFERENCES to file-local functions — a call written ABOVE the `local function` that
//      defines it. That is valid Lua and parses clean, but the name is not in scope at the call
//      site: it resolves to a nil global and throws at call time. In this addon almost every such
//      call sits inside a hooksecurefunc post-hook, where a throw silently kills the rest of the
//      chain and strands whatever that hook was keeping in sync — a failure that reads as "the
//      window stopped updating", with no error shown, and which has cost real debugging time here
//      more than once.
//
// The check is deliberately conservative: it only considers `local function NAME` declared at the
// top level of a file, and only flags a bare `NAME(` call appearing on an earlier line. Locals
// declared inside a block, method calls and field accesses are all left alone, so a hit is a real
// ordering problem rather than something to argue with.
const luaparse = require('luaparse');
const fs = require('fs');

// Strip comments and string literals so neither can produce a phantom hit.
function stripNoise(src) {
  return src
    .replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, ' ')  // long comments
    .replace(/--[^\n]*/g, ' ')                  // line comments
    .replace(/\[(=*)\[[\s\S]*?\]\1\]/g, ' ')    // long strings
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'(?:\\.|[^'\\])*'/g, "''");
}

function forwardRefs(src) {
  const lines = stripNoise(src).split('\n');
  const declared = new Map();                   // name -> 1-based line of `local function NAME`
  lines.forEach((line, i) => {
    const m = /^local\s+function\s+([A-Za-z_]\w*)\s*\(/.exec(line);
    if (m && !declared.has(m[1])) declared.set(m[1], i + 1);
  });

  const hits = [];
  for (const [name, declLine] of declared) {
    // A call to the bare name, not preceded by '.' or ':' (those are fields, not this local).
    const call = new RegExp('(^|[^\\w.:])' + name + '\\s*\\(');
    for (let i = 0; i < declLine - 1; i++) {
      if (/^\s*local\s+function\s/.test(lines[i])) continue;   // the declaration itself
      if (call.test(lines[i])) {
        hits.push({ name, callLine: i + 1, declLine });
        break;                                                  // first one is enough to report
      }
    }
  }
  return hits;
}

let bad = 0;
for (const f of process.argv.slice(2)) {
  const src = fs.readFileSync(f, 'utf8');
  try {
    luaparse.parse(src, { luaVersion: '5.1' });
  } catch (e) {
    bad++;
    console.log('FAIL ' + f + '  -> ' + e.message);
    continue;
  }
  const hits = forwardRefs(src);
  if (hits.length) {
    bad++;
    console.log('FAIL ' + f + '  -> forward reference to a file-local function (nil at call time):');
    for (const h of hits) {
      console.log('        ' + h.name + '() called at line ' + h.callLine +
                  ', but `local function ' + h.name + '` is at line ' + h.declLine);
    }
  } else {
    console.log('OK   ' + f);
  }
}
process.exit(bad ? 1 : 0);
