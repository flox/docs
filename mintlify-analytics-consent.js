(() => {
  try {
    if (typeof window === 'undefined') return;

    // Mintlify runs its own analytics only for a visitor whose `localStorage`
    // has this key set to this value. `integrations.cookies` in `docs.json`
    // names both.
    const CONSENT_KEY = 'flox-docs-analytics-consent';
    const CONSENT_VALUE = 'granted';

    window._hsp ||= [];
    window._hsp.push([
      'addPrivacyConsentListener',
      (consent) => {
        try {
          if (consent?.categories?.analytics) {
            window.localStorage.setItem(CONSENT_KEY, CONSENT_VALUE);
          } else {
            const hadConsent = window.localStorage.getItem(CONSENT_KEY) === CONSENT_VALUE;
            window.localStorage.removeItem(CONSENT_KEY);
            // Mintlify does not delete the identifiers it stored while its
            // analytics ran.
            window.localStorage.removeItem('mintlify_anonymous_id');
            window.localStorage.removeItem('mintlify_user_id');
            window.sessionStorage.removeItem('mintlify_session_id');
            // Mintlify reads the entry only as a page renders, so it is still
            // recording this page for a visitor whose entry outlived their
            // consent. Reloading the page stops the recording, as Mintlify
            // itself does when consent is withdrawn through Transcend:
            // https://www.mintlify.com/docs/integrations/privacy/transcend
            if (hadConsent) window.location.reload();
          }
        } catch { /* noop */ }
      }
    ]);
  } catch { /* noop */ }
})();
