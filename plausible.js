(() => {
  try {
    if (typeof window === 'undefined') return;

    // Production only. flox.mintlify.dev is left out so previews don't count as flox.dev traffic.
    const PROD_HOSTS = ['flox.dev', 'www.flox.dev'];
    if (!PROD_HOSTS.includes(location.hostname)) return;

    if (document.getElementById('plausible-script')) return;

    // Plausible is cookie-less, so unlike amplitude.js it loads without waiting for consent.
    window.plausible ||= (...args) => { (window.plausible.q ||= []).push(args); };
    window.plausible.init ||= (options) => { window.plausible.o = options || {}; };
    window.plausible.init();

    const script = document.createElement('script');
    script.id = 'plausible-script';
    script.async = true;
    script.src = 'https://plausible.io/js/pa-cEV79lqetNhwZPjIORFBy.js';
    document.head.appendChild(script);
  } catch { /* noop */ }
})();
