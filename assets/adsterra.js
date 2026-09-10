/* Next Jailbreak — Monetag site-wide loader (legacy filename kept for existing pages) */
(function () {
  'use strict';

  // Keep shared branding and homepage/category content behavior unchanged.
  if (!document.querySelector('script[data-ns-site-branding]')) {
    var brandingScript = document.createElement('script');
    brandingScript.src = '/assets/site-branding.js?v=20260823-2';
    brandingScript.defer = true;
    brandingScript.setAttribute('data-ns-site-branding', '1');
    document.head.appendChild(brandingScript);
  }

  if (!document.querySelector('script[data-ns-site-content]')) {
    var contentScript = document.createElement('script');
    contentScript.src = '/assets/site-content.js?v=20260825-1';
    contentScript.defer = true;
    contentScript.setAttribute('data-ns-site-content', '1');
    document.head.appendChild(contentScript);
  }

  var path = window.location.pathname || '/';

  // Keep ads off repository depictions, legal/support pages and app-internal pages.
  var blockedPrefixes = ['/depictions/', '/applications/', '/DailyLedger/', '/DailyTweaks/', '/Diagnostics/', '/ModuleGlassPreview/', '/NextPDF/', '/NextPost/', '/license/', '/install/', '/support/', '/payment/', '/request/'];
  var blockedExact = ['/about/', '/about.html', '/contact/', '/contact.html', '/privacy/', '/privacy.html', '/terms/', '/terms.html', '/repo/', '/repo.html', '/videos/', '/videos.html', '/next-ledger-support.html'];
  if (blockedExact.indexOf(path) !== -1 || blockedPrefixes.some(function (prefix) { return path.indexOf(prefix) === 0; })) {
    return;
  }

  // Monetag MultiTag — zone 273366.
  if (!document.querySelector('script[data-ns-monetag]') && !document.querySelector('script[src="https://quge5.com/88/tag.min.js"]')) {
    var monetag = document.createElement('script');
    monetag.src = 'https://quge5.com/88/tag.min.js';
    monetag.async = true;
    monetag.setAttribute('data-zone', '273366');
    monetag.setAttribute('data-cfasync', 'false');
    monetag.setAttribute('data-ns-monetag', '1');
    document.head.appendChild(monetag);
  }
}());
