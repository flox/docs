(() => {
  try {
    if (typeof window === 'undefined') return;

    const PROD_HOSTS = ['flox.dev', 'www.flox.dev', 'flox.mintlify.dev'];
    const AMPLITUDE_API_KEY = PROD_HOSTS.includes(location.hostname)
      ? '6f89e78c468a7da6fecfd717437fcb32'
      : '820bc93b6feb09134fb8ed7b25af09a1';

    window._hsp ||= [];
    window._hsp.push([
      'addPrivacyConsentListener',
      (consent) => {
        try {
          if (!consent?.categories?.analytics) return;
          if (document.getElementById('amplitude-script-loaded')) return;

          const script = document.createElement('script');
          script.id = 'amplitude-script-loaded';
          script.type = 'text/javascript';
          script.async = true;
          script.src = `https://cdn.amplitude.com/script/${AMPLITUDE_API_KEY}.js`;
          script.onload = () => {
            try {
              if (typeof window.amplitude?.init !== 'function') return;

              if (typeof window.sessionReplay?.plugin === 'function') {
                window.amplitude.add(window.sessionReplay.plugin({ sampleRate: 0.3 }));
              }

              window.amplitude.init(AMPLITUDE_API_KEY, {
                fetchRemoteConfig: true,
                autocapture: {
                  attribution: true,
                  fileDownloads: true,
                  formInteractions: true,
                  pageViews: true,
                  sessions: true,
                  elementInteractions: true,
                  networkTracking: true,
                  webVitals: true,
                  frustrationInteractions: {
                    thrashedCursor: true,
                    errorClicks: true,
                    deadClicks: true,
                    rageClicks: true
                  }
                }
              });
            } catch { /* noop */ }
          };
          document.head.appendChild(script);
        } catch { /* noop */ }
      }
    ]);
  } catch { /* noop */ }
})();
