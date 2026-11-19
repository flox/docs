(() => {
  try {
    if (typeof window === 'undefined') return;

    const PROD_HOSTS = ['flox.dev', 'www.flox.dev', 'flox.mintlify.dev'];
    if (!PROD_HOSTS.includes(location.hostname)) return;

    if (document.getElementById('hs-script-loader')) return;

    const script = document.createElement('script');
    script.id = 'hs-script-loader';
    script.type = 'text/javascript';
    script.async = true;
    script.defer = true;
    script.src = '//js.hs-scripts.com/23414950.js';
    document.head.appendChild(script);
  } catch { /* noop */ }
})();
