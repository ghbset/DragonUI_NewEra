// mpq.js — minimal MPQ archive reader (WoW 3.3.5a, format v0/v1), browser + Node.
//
// Reads on demand via an async byte reader { size, read(offset, len) -> Promise<ArrayBuffer> } so a
// 4 GB archive never has to be loaded whole (browser: File.slice().arrayBuffer(); Node: fd read).
// Supports the file flags WoW DBCs actually use: compressed (multi-sector zlib) / stored /
// single-unit / encrypted. PKWARE-implode and bzip2 sectors throw (DBCs don't use them).
(function (root, factory) {
  var api = factory();
  if (root) root.MPQ = api;                                                 // browser global (window.MPQ)
  if (typeof module === "object" && module.exports) module.exports = api;   // Node
})(typeof globalThis !== "undefined" ? globalThis : (typeof self !== "undefined" ? self : this), function () {
  "use strict";

  // ---- MPQ crypt table + hashing (StormLib algorithm) --------------------------------------------
  var cryptTable = new Uint32Array(0x500);
  (function () {
    var seed = 0x00100001;
    for (var i1 = 0; i1 < 0x100; i1++) {
      for (var i2 = i1, n = 0; n < 5; n++, i2 += 0x100) {
        seed = (seed * 125 + 3) % 0x2aaaab;
        var t1 = seed & 0xffff;
        seed = (seed * 125 + 3) % 0x2aaaab;
        var t2 = seed & 0xffff;
        cryptTable[i2] = ((t1 << 16) | t2) >>> 0;
      }
    }
  })();

  function hashString(str, type) {
    var s1 = 0x7fed7fed, s2 = 0xeeeeeeee >>> 0;
    str = str.toUpperCase().replace(/\//g, "\\");
    for (var i = 0; i < str.length; i++) {
      var ch = str.charCodeAt(i) & 0xff;
      s1 = (cryptTable[((type << 8) + ch) >>> 0] ^ ((s1 + s2) >>> 0)) >>> 0;
      s2 = (ch + s1 + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
    }
    return s1 >>> 0;
  }

  function decryptU32(arr, key) {
    var s1 = key >>> 0, s2 = 0xeeeeeeee >>> 0;
    for (var i = 0; i < arr.length; i++) {
      s2 = (s2 + cryptTable[0x400 + (s1 & 0xff)]) >>> 0;
      var ch = (arr[i] ^ ((s1 + s2) >>> 0)) >>> 0;
      s1 = (((((~s1 << 0x15) >>> 0) + 0x11111111) >>> 0) | (s1 >>> 0x0b)) >>> 0;
      s2 = (ch + s2 + ((s2 << 5) >>> 0) + 3) >>> 0;
      arr[i] = ch >>> 0;
    }
  }

  // ---- zlib inflate via the Web Streams DecompressionStream (Node 20 + browsers) ------------------
  async function inflate(u8) {
    var ds = new DecompressionStream("deflate");
    var w = ds.writable.getWriter();
    w.write(u8); w.close();
    var r = ds.readable.getReader(), chunks = [], len = 0, c;
    for (;;) { c = await r.read(); if (c.done) break; chunks.push(c.value); len += c.value.length; }
    var out = new Uint8Array(len), o = 0;
    for (var i = 0; i < chunks.length; i++) { out.set(chunks[i], o); o += chunks[i].length; }
    return out;
  }

  var FLAG = { IMPLODE: 0x100, COMPRESS: 0x200, ENCRYPTED: 0x10000, FIX_KEY: 0x20000, SINGLE: 0x1000000, EXISTS: 0x80000000 };

  function MPQArchive() {}

  // reader: { size:Number, read(offset,len)->Promise<ArrayBuffer> }
  MPQArchive.open = async function (reader) {
    var a = new MPQArchive();
    a.reader = reader;
    // Find the 'MPQ\x1a' header (0, 0x200, 0x400, ...).
    var off = -1;
    for (var probe = 0; probe < Math.min(reader.size, 0x40000); probe += 0x200) {
      var hb = new DataView(await reader.read(probe, 4));
      if (hb.getUint32(0, true) === 0x1a51504d) { off = probe; break; }
    }
    if (off < 0) throw new Error("not an MPQ archive");
    a.archiveOffset = off;
    var h = new DataView(await reader.read(off, 32));
    a.sectorSize = 512 << h.getUint16(14, true);
    var hashPos = h.getUint32(16, true), blockPos = h.getUint32(20, true);
    a.hashCount = h.getUint32(24, true);
    a.blockCount = h.getUint32(28, true);

    a.hash = await readTable(reader, off + hashPos, a.hashCount, hashString("(hash table)", 3));
    a.block = await readTable(reader, off + blockPos, a.blockCount, hashString("(block table)", 3));
    return a;
  };

  async function readTable(reader, pos, count, key) {
    var raw = new Uint32Array(await reader.read(pos, count * 16));
    decryptU32(raw, key);
    return raw; // each entry = 4 u32
  }

  MPQArchive.prototype.findFile = function (name) {
    var n = this.hashCount;
    var start = hashString(name, 0) % n;
    var a = hashString(name, 1), b = hashString(name, 2);
    for (var i = 0; i < n; i++) {
      var e = (start + i) % n, base = e * 4;
      var blockIndex = this.hash[base + 3] >>> 0;
      if (blockIndex === 0xffffffff) return null; // empty terminator
      if (blockIndex !== 0xfffffffe && this.hash[base] === a && this.hash[base + 1] === b) {
        var bb = blockIndex * 4;
        return {
          filePos: this.block[bb] >>> 0, cSize: this.block[bb + 1] >>> 0,
          fSize: this.block[bb + 2] >>> 0, flags: this.block[bb + 3] >>> 0, name: name,
        };
      }
    }
    return null;
  };

  MPQArchive.prototype.hasFile = function (name) { return !!this.findFile(name); };

  MPQArchive.prototype.readFile = async function (name) {
    var e = this.findFile(name);
    if (!e) return null;
    if (!(e.flags & FLAG.EXISTS)) return null;
    var fileKey = 0, encrypted = !!(e.flags & FLAG.ENCRYPTED);
    if (encrypted) {
      var bn = name.replace(/^.*[\\/]/, "");
      fileKey = hashString(bn, 3) >>> 0;
      if (e.flags & FLAG.FIX_KEY) fileKey = (((fileKey + e.filePos) >>> 0) ^ e.fSize) >>> 0;
    }
    var abs = this.archiveOffset + e.filePos;

    if (e.flags & FLAG.SINGLE) {
      var raw = new Uint8Array(await this.reader.read(abs, e.cSize));
      if (encrypted) { var u = new Uint32Array(raw.buffer.slice(0, raw.length & ~3)); decryptU32(u, fileKey); raw = new Uint8Array(u.buffer); }
      return decompressSector(raw, e.fSize, e.flags);
    }

    // Stored (no COMPRESS/IMPLODE flag): there is NO sector offset table — the data is just the raw
    // fSize bytes (in sectorSize chunks). Many patch tools store DBCs uncompressed; Blizzard's are
    // zlib-compressed (which has the offset table). Read it directly.
    if (!(e.flags & (FLAG.COMPRESS | FLAG.IMPLODE))) {
      var stored = new Uint8Array(await this.reader.read(abs, e.fSize));
      if (encrypted) {
        var ss = this.sectorSize;
        for (var so0 = 0, sec = 0; so0 < stored.length; so0 += ss, sec++) {
          var nb = Math.min(ss, stored.length - so0) & ~3;
          if (nb) { var su0 = new Uint32Array(stored.buffer.slice(so0, so0 + nb)); decryptU32(su0, (fileKey + sec) >>> 0); stored.set(new Uint8Array(su0.buffer), so0); }
        }
      }
      return stored;
    }

    var numSectors = Math.ceil(e.fSize / this.sectorSize);
    var offU = new Uint32Array(await this.reader.read(abs, (numSectors + 1) * 4));
    if (encrypted) decryptU32(offU, (fileKey - 1) >>> 0);
    var out = new Uint8Array(e.fSize), written = 0;
    for (var i = 0; i < numSectors; i++) {
      var so = offU[i], eo = offU[i + 1];
      var sraw = new Uint8Array(await this.reader.read(abs + so, eo - so));
      if (encrypted) { var su = new Uint32Array(sraw.buffer.slice(0, sraw.length & ~3)); decryptU32(su, (fileKey + i) >>> 0); var merged = new Uint8Array(sraw.length); merged.set(new Uint8Array(su.buffer)); for (var k = su.length * 4; k < sraw.length; k++) merged[k] = sraw[k]; sraw = merged; }
      var expected = Math.min(this.sectorSize, e.fSize - written);
      var dec = await decompressSector(sraw, expected, e.flags);
      out.set(dec.subarray(0, expected), written);
      written += expected;
    }
    return out;
  };

  async function decompressSector(raw, expected, flags) {
    if (raw.length >= expected) return raw.subarray(0, expected); // stored (not compressed)
    if (flags & FLAG.COMPRESS) {
      var mask = raw[0], body = raw.subarray(1);
      if (mask & 0x02) return await inflate(body);   // zlib
      if (mask === 0x00) return body;                // stored with leading 0 byte
      throw new Error("unsupported MPQ compression 0x" + mask.toString(16));
    }
    if (flags & FLAG.IMPLODE) throw new Error("PKWARE-implode sectors not supported");
    return raw.subarray(0, expected);
  }

  MPQArchive.hashString = hashString;
  return MPQArchive;
});
