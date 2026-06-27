// blp.js — minimal BLP2 decoder (WoW 3.3.5a icons), browser + Node. Decodes mip 0 to RGBA.
// Handles the three compressions icons use: DXTC (DXT1/3/5), palettized (RAW1), and BGRA (RAW3).
(function (root, factory) {
  var api = factory();
  if (root) root.BLP = api;                                                 // browser global (window.BLP)
  if (typeof module === "object" && module.exports) module.exports = api;   // Node
})(typeof globalThis !== "undefined" ? globalThis : (typeof self !== "undefined" ? self : this), function () {
  "use strict";

  function rgb565(c) {
    var r = (c >> 11) & 31, g = (c >> 5) & 63, b = c & 31;
    return [(r * 255 / 31) | 0, (g * 255 / 63) | 0, (b * 255 / 31) | 0];
  }

  // DXT colour endpoints -> 4 colours. dxt1Punch = DXT1 1-bit-alpha mode (c0<=c1 -> 3 colours + clear).
  function dxtColors(c0, c1, dxt1Punch) {
    var a = rgb565(c0), b = rgb565(c1);
    if (dxt1Punch) {
      return [a, b,
        [(a[0] + b[0]) >> 1, (a[1] + b[1]) >> 1, (a[2] + b[2]) >> 1, 255],
        [0, 0, 0, 0]];
    }
    return [
      [a[0], a[1], a[2], 255], [b[0], b[1], b[2], 255],
      [(2 * a[0] + b[0]) / 3 | 0, (2 * a[1] + b[1]) / 3 | 0, (2 * a[2] + b[2]) / 3 | 0, 255],
      [(a[0] + 2 * b[0]) / 3 | 0, (a[1] + 2 * b[1]) / 3 | 0, (a[2] + 2 * b[2]) / 3 | 0, 255]];
  }

  function dxt5Alphas(a0, a1) {
    var al = [a0, a1];
    if (a0 > a1) { for (var i = 1; i <= 6; i++) al.push(((7 - i) * a0 + i * a1) / 7 | 0); }
    else { for (var j = 1; j <= 4; j++) al.push(((5 - j) * a0 + j * a1) / 5 | 0); al.push(0); al.push(255); }
    return al;
  }

  function decodeDXT(data, w, h, alphaType, out) {
    var p = 0;
    for (var by = 0; by < h; by += 4) {
      for (var bx = 0; bx < w; bx += 4) {
        var alphaBlock = null, dxt5 = null;
        if (alphaType === 1) { alphaBlock = data.subarray(p, p + 8); p += 8; }       // DXT3
        else if (alphaType === 7) {                                                  // DXT5
          alphaBlock = data.subarray(p, p + 8);
          dxt5 = dxt5Alphas(alphaBlock[0], alphaBlock[1]);
          p += 8;
        }
        var c0 = data[p] | (data[p + 1] << 8);
        var c1 = data[p + 2] | (data[p + 3] << 8);
        var bits = (data[p + 4] | (data[p + 5] << 8) | (data[p + 6] << 16) | (data[p + 7] << 24)) >>> 0;
        p += 8;
        var cols = dxtColors(c0, c1, alphaType === 0 && c0 <= c1);
        for (var py = 0; py < 4; py++) {
          for (var px = 0; px < 4; px++) {
            var x = bx + px, y = by + py;
            if (x >= w || y >= h) continue;
            var pi = py * 4 + px;
            var col = cols[(bits >>> (2 * pi)) & 3];
            var o = (y * w + x) * 4;
            out[o] = col[0]; out[o + 1] = col[1]; out[o + 2] = col[2];
            if (alphaType === 1) {              // DXT3: explicit 4-bit
              out[o + 3] = ((alphaBlock[pi >> 1] >> ((pi & 1) * 4)) & 0xf) * 17;
            } else if (alphaType === 7) {       // DXT5: indexed
              var bit = 3 * pi, bi = 2 + (bit >> 3), sh = bit & 7;
              var idx = ((alphaBlock[bi] | ((alphaBlock[bi + 1] || 0) << 8)) >> sh) & 7;
              out[o + 3] = dxt5[idx];
            } else {                            // DXT1
              out[o + 3] = col.length > 3 ? col[3] : 255;
            }
          }
        }
      }
    }
  }

  function decode(bytes) {
    var dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    if (!(bytes[0] === 0x42 && bytes[1] === 0x4c && bytes[2] === 0x50 && bytes[3] === 0x32)) throw new Error("not BLP2");
    var compression = bytes[8], alphaDepth = bytes[9], alphaType = bytes[10];
    var width = dv.getUint32(12, true), height = dv.getUint32(16, true);
    var mip0 = dv.getUint32(20, true), size0 = dv.getUint32(20 + 64, true);
    var data = bytes.subarray(mip0, mip0 + (size0 || bytes.length - mip0));
    var out = new Uint8ClampedArray(width * height * 4);

    if (compression === 2) {
      decodeDXT(data, width, height, alphaType, out);
    } else if (compression === 1) {            // palettized: 256 BGRA palette @ 148, then 8-bit indices
      var pal = bytes.subarray(148, 148 + 1024);
      var n = width * height;
      for (var i = 0; i < n; i++) {
        var idx = data[i] * 4;
        out[i * 4] = pal[idx + 2]; out[i * 4 + 1] = pal[idx + 1]; out[i * 4 + 2] = pal[idx];
        if (alphaDepth === 8) out[i * 4 + 3] = data[n + i];
        else if (alphaDepth === 1) out[i * 4 + 3] = ((data[n + (i >> 3)] >> (i & 7)) & 1) ? 255 : 0;
        else out[i * 4 + 3] = 255;
      }
    } else if (compression === 3) {            // raw BGRA
      var m = width * height;
      for (var k = 0; k < m; k++) {
        out[k * 4] = data[k * 4 + 2]; out[k * 4 + 1] = data[k * 4 + 1];
        out[k * 4 + 2] = data[k * 4]; out[k * 4 + 3] = data[k * 4 + 3];
      }
    } else {
      throw new Error("unsupported BLP compression " + compression);
    }
    return { width: width, height: height, rgba: out };
  }

  return { decode: decode };
});
