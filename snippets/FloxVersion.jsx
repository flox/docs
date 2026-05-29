const VERSION_URL = 'https://downloads.flox.dev/by-env/stable/LATEST_VERSION';

export async function fetchVersion() {
  try {
    const res = await fetch(VERSION_URL, { next: { revalidate: 21600 } }); // 6-hour ISR
    if (!res.ok) return null;
    return (await res.text()).trim();
  } catch {
    return null;
  }
}

/** Renders the current Flox version string inline. */
export async function FloxVersion() {
  return (await fetchVersion()) ?? null;
}

/**
 * Renders an <a> tag where {VERSION} in `base` is replaced with the live version.
 * Falls back to plain text if the fetch fails.
 */
export async function FloxVersionedUrl({ base, children }) {
  const version = await fetchVersion();
  if (!version) return children ? <>{children}</> : null;
  const href = base.replace('{VERSION}', version);
  return <a href={href}>{children ?? href}</a>;
}
