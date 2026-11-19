(() => {
  try {
    if (typeof window === 'undefined') return;

    // Plausible loads only at flox.dev, the address Flox sends visitors to,
    // and not at Mintlify's own addresses for the docs, such as
    // flox.mintlify.dev and preview deployments.
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
