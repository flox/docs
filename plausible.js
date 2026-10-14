(function () {
  try {
    if (typeof window === 'undefined') return;

    // Production only. flox.mintlify.dev is left out so previews don't count as flox.dev traffic.
    var PROD_HOSTS = ['flox.dev', 'www.flox.dev'];
    if (PROD_HOSTS.indexOf(location.hostname) === -1) return;

    if (document.getElementById('plausible-script')) return;

    // Plausible is cookie-less, so unlike amplitude.js it loads without waiting for consent.
    window.plausible = window.plausible || function () { (window.plausible.q = window.plausible.q || []).push(arguments); };
    window.plausible.init = window.plausible.init || function (i) { window.plausible.o = i || {}; };
    window.plausible.init();

    var s = document.createElement('script');
    s.id = 'plausible-script';
    s.async = true;
    s.src = 'https://plausible.io/js/pa-cEV79lqetNhwZPjIORFBy.js';
    document.head.appendChild(s);
  } catch (e) {}
})();
