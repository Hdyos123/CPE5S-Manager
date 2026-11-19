import Foundation

// MARK: - 隐藏 WebView 内运行的桥接脚本
// 说明：全部用 WebCrypto（crypto.subtle）实现，避免依赖页面全局库。
//  - AES-256-CTR 加密：key/iv = URL 中的 32 位十六进制字符串本身（ASCII 字节）
//  - SHA-256：用于密码与 sum 校验
//  - RSA：用 WebCrypto 的 RSA-OAEP 不可用（固件是 PKCS1 v1.5），所以改写为
//    “把 key.iv 明文放进 AES 字段并在 JS 内自行 RSA 加密（BigInt 模幂 + PKCS1 v1.5 填充）”
enum CpeBridge {
    static let js = #"""
    (function () {
      if (window.__cpe) return;
      var B = {
        key: null, iv: null, aeskeyEnc: null, pem: null,
        report: function (o) {
          try { window.webkit.messageHandlers.cpeBridge.postMessage(o); } catch (e) {}
        }
      };

      // ---------- 工具 ----------
      function hex2bytes(h) {
        var out = new Uint8Array(h.length / 2);
        for (var i = 0; i < h.length; i += 2) out[i / 2] = parseInt(h.substr(i, 2), 16);
        return out;
      }
      function bytes2hex(b) {
        var s = '';
        for (var i = 0; i < b.length; i++) s += ('0' + b[i].toString(16)).slice(-2);
        return s;
      }
      function bytes2b64(bytes) {
        var s = '';
        for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
        return btoa(s);
      }
      function b642bytes(str) {
        var bin = atob(str), out = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
        return out;
      }
      function randHex(n) {
        var b = new Uint8Array(n); crypto.getRandomValues(b);
        return bytes2hex(b).toUpperCase();
      }
      function rndToken() {
        var r = new Uint8Array(4); crypto.getRandomValues(r);
        var n = ((r[0] << 24) | (r[1] << 16) | (r[2] << 8) | r[3]) >>> 0;
        return String(Date.now()) + String(n % 10000).padStart(4, '0');
      }
      function b64utf8(s) {
        return bytes2b64(new TextEncoder().encode(s));
      }
      function sha256hex(str) {
        return crypto.subtle.digest('SHA-256', new TextEncoder().encode(str))
          .then(function (buf) { return bytes2hex(new Uint8Array(buf)); });
      }

      // ---------- AES-256-CTR（WebCrypto） ----------
      var keyCache = null;
      function aesKey() {
        if (keyCache) return Promise.resolve(keyCache);
        return crypto.subtle.importKey('raw', new TextEncoder().encode(B.key), 'AES-CTR', false, ['encrypt', 'decrypt'])
          .then(function (k) { keyCache = k; return k; });
      }
      function ctrParams() {
        // 固件 AES-CTR 的计数器 = IV 字符串的前 16 个 ASCII 字节（已用真实报文验证）
        return { name: 'AES-CTR', counter: new TextEncoder().encode(B.iv).slice(0, 16), length: 128 };
      }
      function aesEnc(text) {
        return aesKey().then(function (k) {
          return crypto.subtle.encrypt(ctrParams(), k, new TextEncoder().encode(text));
        }).then(function (buf) { return bytes2b64(new Uint8Array(buf)); });
      }
      function aesDec(b64) {
        return aesKey().then(function (k) {
          return crypto.subtle.decrypt(ctrParams(), k, b642bytes(b64));
        }).then(function (buf) { return new TextDecoder().decode(buf); });
      }

      // ---------- RSA PKCS1 v1.5 ----------
      // 说明：WebCrypto 只支持 RSA-OAEP，不支持 PKCS1 v1.5，所以这里只借它解析 DER 取出 n/e，
      // 再用 BigInt 做模幂。解析用 spki 导入避开手写 DER 长度编码的坑。
      let rsaKey = null;
      function loadRsa(pem) {
        if (rsaKey) return Promise.resolve(rsaKey);
        var body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
        var der = b642bytes(body);
        // 把 PKCS#1 "RSA PUBLIC KEY" 包成 SPKI：SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING }
        var oidSeq = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
        // BIT STRING：前导 0x00 表示无未用位，后面直接是 PKCS#1 RSAPublicKey 的 DER
        var bitStr = [0x03].concat(derLen(der.length + 1), [0x00], Array.from(der));
        var inner = oidSeq.concat(bitStr);
        function derLen(n) {
          if (n < 0x80) return [n];
          var out = [];
          while (n > 0) { out.unshift(n & 0xff); n >>= 8; }
          return [0x80 | out.length].concat(out);
        }
        var spki = new Uint8Array([0x30].concat(derLen(inner.length), inner));
        return crypto.subtle.importKey('spki', spki, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, true, ['verify'])
          .then(function (k) { return crypto.subtle.exportKey('jwk', k); })
          .then(function (jwk) {
            function b64uToBig(s) {
              var b = s.replace(/-/g, '+').replace(/_/g, '/');
              while (b.length % 4) b += '=';
              var raw = b642bytes(b);
              var hex = '';
              for (var i = 0; i < raw.length; i++) hex += ('0' + raw[i].toString(16)).slice(-2);
              return { v: BigInt('0x' + hex), len: raw.length };
            }
            var n = b64uToBig(jwk.n), e = b64uToBig(jwk.e);
            rsaKey = { n: n.v, e: e.v, modLen: n.len };
            return rsaKey;
          });
      }
      function modPow(base, exp, mod) {
        var r = 1n, b = base % mod, x = exp;
        while (x > 0n) {
          if (x & 1n) r = (r * b) % mod;
          b = (b * b) % mod;
          x >>= 1n;
        }
        return r;
      }
      function rsaPkcs1(pem, msg) {
        return loadRsa(pem).then(function (key) {
          var msgBytes = new TextEncoder().encode(msg);
          var k = key.modLen;
          var padLen = k - 3 - msgBytes.length;
          if (padLen < 8) throw new Error('msg too long');
          var block = new Uint8Array(k);
          block[0] = 0; block[1] = 2;
          for (var i = 0; i < padLen; i++) {
            var r = new Uint8Array(1);
            do { crypto.getRandomValues(r); } while (r[0] === 0);
            block[2 + i] = r[0];
          }
          block[2 + padLen] = 0;
          block.set(msgBytes, 3 + padLen);
          var hex = '';
          for (var j = 0; j < block.length; j++) hex += ('0' + block[j].toString(16)).slice(-2);
          var m = BigInt('0x' + hex);
          var c = modPow(m, key.e, key.n);
          var ch = c.toString(16);
          while (ch.length < k * 2) ch = '0' + ch;
          return bytes2b64(hex2bytes(ch));
        });
      }

      // ---------- 请求构造 ----------
      B.init = function () {
        return fetch('/api/webCgi/GetPemKey', { credentials: 'include' })
          .then(function (r) { return r.json(); })
          .then(function (j) {
            var pem = j && j.data && j.data.pem;
            if (!pem) throw new Error('GetPemKey failed');
            B.pem = pem;
            B.key = randHex(16);
            B.iv = randHex(16);
            keyCache = null;
            rsaKey = null;
            return rsaPkcs1(pem, B.key + '.' + B.iv).then(function (enc) {
              B.aeskeyEnc = enc;
              return true;
            });
          });
      };

      B.login = function (user, pwd) {
        return sha256hex(pwd).then(function (hash) {
          var rt = rndToken();
          var inner = JSON.stringify({ data: { username: user, password: hash }, randomToken: rt });
          return aesEnc(inner).then(function (data) {
            var hdr = b64utf8('{"type":"JWT","alg":"HS256"}');
            var pl = b64utf8(JSON.stringify({ username: 'admin', iat: String(Date.now()) }));
            return aesEnc(JSON.stringify({ header: hdr, payload: pl })).then(function (jwt) {
              return sha256hex(data + rt + jwt).then(function (sum) {
                var body = { AES: B.aeskeyEnc, data: data, JWT: jwt, sum: sum };
                return fetch('/api/userLoginCgi/userLogin', {
                  method: 'POST', credentials: 'include',
                  headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                  body: JSON.stringify(body)
                });
              });
            });
          });
        }).then(function (r) { return r.text(); }).then(function (txt) {
          return B.dec(txt);
        });
      };

      B.dec = function (txt) {
        var t = String(txt || '').trim();
        if (!t) return Promise.resolve('');
        if (t.charAt(0) === '{') return Promise.resolve(t);
        return aesDec(t).catch(function () { return t; });
      };

      B.body = function (payload) {
        var rt = rndToken();
        var inner = JSON.stringify({ data: payload || {}, randomToken: rt });
        return aesEnc(inner).then(function (data) {
          var hdr = b64utf8('{"type":"JWT","alg":"HS256"}');
          var pl = b64utf8(JSON.stringify({ username: 'admin', iat: String(Date.now()) }));
          return aesEnc(JSON.stringify({ header: hdr, payload: pl })).then(function (jwt) {
            return sha256hex(data + rt + jwt).then(function (sum) {
              return { AES: B.aeskeyEnc, data: data, JWT: jwt, sum: sum };
            });
          });
        });
      };

      // 加密接口
      B.api = function (path, payload) {
        return B.body(payload).then(function (body) {
          return fetch('/api' + path, {
            method: 'POST', credentials: 'include',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body)
          });
        }).then(function (r) { return r.text(); }).then(function (t) { return B.dec(t); });
      };

      // 明文接口（/webCgi/*）
      B.plain = function (path, payload) {
        return fetch('/api' + path, {
          method: 'POST', credentials: 'include',
          headers: { 'Content-Type': 'application/json; charset=UTF-8' },
          body: JSON.stringify({ data: payload || {}, flag: 1, randomToken: rndToken() })
        }).then(function (r) { return r.text(); });
      };

      window.__cpe = B;
      B.report({ type: 'ready', url: location.href });
    })();
    """#
}
