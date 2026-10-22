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
}
