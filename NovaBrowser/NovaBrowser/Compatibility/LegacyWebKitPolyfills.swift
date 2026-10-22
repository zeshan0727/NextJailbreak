import WebKit

enum LegacyWebKitPolyfills {
    // Non-invasive, standards-aligned shims for JavaScript APIs unavailable in some older WebKit builds.
    // No network access, tracking, credential access, or browser engine spoofing.
    static let source = #"""
    (function () {
      "use strict";
      if (!Array.prototype.at) Object.defineProperty(Array.prototype, "at", { configurable: true, value: function(i) { var n = Number(i) || 0; if (n < 0) n += this.length; return this[n]; } });
      if (!Array.prototype.findLast) Object.defineProperty(Array.prototype, "findLast", { configurable: true, value: function(fn, ctx) { for (var i=this.length-1; i>=0; i--) if (fn.call(ctx, this[i], i, this)) return this[i]; } });
      if (!Array.prototype.findLastIndex) Object.defineProperty(Array.prototype, "findLastIndex", { configurable: true, value: function(fn, ctx) { for (var i=this.length-1; i>=0; i--) if (fn.call(ctx, this[i], i, this)) return i; return -1; } });
      if (!Object.hasOwn) Object.defineProperty(Object, "hasOwn", { configurable: true, value: function(o,k) { return Object.prototype.hasOwnProperty.call(Object(o),k); } });
      if (!Promise.withResolvers) Object.defineProperty(Promise, "withResolvers", { configurable: true, value: function() { var resolve, reject; var promise = new Promise(function(res, rej) { resolve = res; reject = rej; }); return {promise:promise,resolve:resolve,reject:reject}; } });
      if (!Array.prototype.toReversed) Object.defineProperty(Array.prototype, "toReversed", { configurable: true, value: function() { return Array.prototype.slice.call(this).reverse(); } });
      if (!Array.prototype.toSorted) Object.defineProperty(Array.prototype, "toSorted", { configurable: true, value: function(compare) { return Array.prototype.slice.call(this).sort(compare); } });
      if (!Array.prototype.toSpliced) Object.defineProperty(Array.prototype, "toSpliced", { configurable: true, value: function() { var result=Array.prototype.slice.call(this); Array.prototype.splice.apply(result,arguments); return result; } });
      if (typeof AbortSignal !== "undefined" && !AbortSignal.timeout) Object.defineProperty(AbortSignal, "timeout", { configurable: true, value: function(ms) { var controller=new AbortController(); setTimeout(function(){ var error = new DOMException("The operation timed out", "TimeoutError"); controller.abort(error); }, Math.max(0,Number(ms)||0)); return controller.signal; } });
      if (typeof crypto !== "undefined" && crypto.getRandomValues && !crypto.randomUUID) {
        try { Object.defineProperty(crypto, "randomUUID", { configurable:true, value:function() { var b=new Uint8Array(16); crypto.getRandomValues(b); b[6]=(b[6]&15)|64; b[8]=(b[8]&63)|128; var h=Array.prototype.map.call(b,function(x){return x.toString(16).padStart(2,"0");}).join(""); return h.slice(0,8)+"-"+h.slice(8,12)+"-"+h.slice(12,16)+"-"+h.slice(16,20)+"-"+h.slice(20); } }); } catch(e) {}
      }
    })();
    """#
    // A single standards-compatible Promise API is enabled only on the ChatGPT
    // and OpenAI authentication domains. This is not a service-worker polyfill.
    static let chatGPTBootstrap = #"""
    (function () {
      "use strict";
      var h = location.hostname.toLowerCase();
      if (!(h === "chatgpt.com" || h.endsWith(".chatgpt.com") ||
            h === "auth.openai.com" || h === "chat.openai.com")) return;
      if (!Promise.withResolvers) {
        Object.defineProperty(Promise, "withResolvers", {
          configurable: true,
          writable: true,
          value: function () {
            var resolve, reject;
            var promise = new Promise(function (r, j) { resolve = r; reject = j; });
            return { promise: promise, resolve: resolve, reject: reject };
          }
        });
      }
    })();
    """#

    // JS runtime error reporting only categorizes errors. Never send arbitrary
    // page error text, URLs, tokens, cookies, or chat messages to native code.
    static let chatGPTRuntimeProbe = #"""
    (function () {
      "use strict";
      var h = location.hostname.toLowerCase();
      if (!(h === "chatgpt.com" || h.endsWith(".chatgpt.com") ||
            h === "auth.openai.com" || h === "chat.openai.com")) return;
      var count = 0;
      function category(msg) {
        var m = String(msg || "").toLowerCase();
        if (m.indexOf("withresolvers") >= 0) return "missing-promise-withresolvers";
        if (m.indexOf("serviceworker") >= 0 || m.indexOf("service worker") >= 0) return "service-worker";
        if (m.indexOf("chunkloaderror") >= 0 || m.indexOf("loading chunk") >= 0) return "chunk-load";
        if (m.indexOf("fetch") >= 0 || m.indexOf("networkerror") >= 0) return "network";
        if (m.indexOf("syntax") >= 0 || m.indexOf("unexpected token") >= 0) return "syntax";
        if (m.indexOf("is not a function") >= 0) return "missing-function";
        if (m.indexOf("undefined") >= 0 || m.indexOf("null") >= 0) return "null-or-undefined";
        return "other";
      }
      function emit(kind, message) {
        if (count++ >= 30) return;
        try {
          var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.novaRuntime;
          if (handler) handler.postMessage({kind: kind, category: category(message)});
        } catch (_) {}
      }
      window.addEventListener("error", function (e) {
        if (e.target !== window) return;
        emit("script-error", e.message || (e.error && e.error.name) || "");
      }, true);
      window.addEventListener("unhandledrejection", function (e) {
        var reason = e.reason;
        emit("unhandled-rejection", reason && (reason.message || reason.name) || "");
      });
    })();
    """#

}
