// GitHub-releases-backed pages: /appcast.xml for Sparkle and /changelog for
// humans. Both read the public releases API with a short in-memory cache so
// a burst of update checks doesn't hit GitHub's rate limit.

import type { Request, Response } from "express";

export const REPO = "crazyparadox/panopticon";

interface GhAsset {
  name: string;
  browser_download_url: string;
  size: number;
  content_type: string;
}

interface GhRelease {
  tag_name: string;
  name: string | null;
  body: string | null;
  html_url: string;
  published_at: string;
  draft: boolean;
  prerelease: boolean;
  assets: GhAsset[];
}

let cache: { at: number; releases: GhRelease[] } | null = null;
const CACHE_MS = 5 * 60 * 1000;

async function fetchReleases(): Promise<GhRelease[]> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.releases;
  const resp = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=25`, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "panopticon-mcp",
    },
  });
  if (!resp.ok) {
    // Serve stale data over failing hard: update checks should degrade softly.
    if (cache) return cache.releases;
    throw new Error(`GitHub releases fetch failed: ${resp.status}`);
  }
  const releases = ((await resp.json()) as GhRelease[]).filter((r) => !r.draft);
  cache = { at: Date.now(), releases };
  return releases;
}

function esc(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/** Minimal, safe markdown-ish rendering for release bodies: escapes HTML
 *  first, then applies bold / code / bullet formatting. */
function renderBody(body: string): string {
  const lines = esc(body).split(/\r?\n/);
  const out: string[] = [];
  let inList = false;
  for (const raw of lines) {
    const line = raw
      .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/`([^`]+)`/g, "<code>$1</code>");
    const m = line.match(/^\s*[-*]\s+(.*)$/);
    if (m) {
      if (!inList) {
        out.push("<ul>");
        inList = true;
      }
      out.push(`<li>${m[1]}</li>`);
    } else {
      if (inList) {
        out.push("</ul>");
        inList = false;
      }
      if (line.trim()) out.push(`<p>${line}</p>`);
    }
  }
  if (inList) out.push("</ul>");
  return out.join("\n");
}

function version(tag: string): string {
  return tag.replace(/^v/, "");
}

/** Recent releases rendered as landing-page rows. Returns null when GitHub is
 *  unreachable and nothing is cached, so the caller can fall back to a link
 *  rather than printing a version history that isn't real. */
export async function recentReleaseRows(limit = 4): Promise<string | null> {
  let releases: GhRelease[];
  try {
    releases = await fetchReleases();
  } catch {
    return null;
  }
  if (releases.length === 0) return null;
  return releases
    .slice(0, limit)
    .map((r) => {
      const date = new Date(r.published_at).toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
      });
      const title = describe(r);
      return `      <a class="cl-row" href="/changelog"><span class="v">${esc(
        version(r.tag_name)
      )}</span><span class="d">${date}</span>${
        title ? `<span>${esc(title)}</span>` : ""
      }</a>`;
    })
    .join("\n");
}

/** A one-line description of a release, or "" when there genuinely isn't one.
 *  A release titled "Panopticon 0.1.1" says nothing the version column doesn't,
 *  and GitHub's auto-generated bodies are often just a compare link. In both
 *  cases we print nothing rather than inventing a summary. */
function describe(r: GhRelease): string {
  const v = version(r.tag_name);
  const name = (r.name ?? "").trim();
  if (name && name !== r.tag_name && name !== v && name !== `Panopticon ${v}`) {
    return name;
  }
  for (const raw of (r.body ?? "").split(/\r?\n/)) {
    // Blockquotes carry build caveats (e.g. the unsigned-build warning), not
    // changelog content, so they never stand in for a description.
    if (/^\s*>/.test(raw)) continue;
    const line = raw
      .replace(/^\s*[-*]\s*/, "")
      .replace(/[*`#]/g, "")
      .trim();
    if (!line || /^https?:/.test(line)) continue;
    if (/^full changelog/i.test(line)) continue;
    return line.length > 72 ? `${line.slice(0, 71)}…` : line;
  }
  return "";
}

// ── Sparkle appcast ──────────────────────────────────────────────────────

export async function serveAppcast(_req: Request, res: Response): Promise<void> {
  try {
    const releases = await fetchReleases();
    const items = releases
      .map((r) => {
        const asset = r.assets.find((a) => /\.(zip|dmg)$/.test(a.name));
        if (!asset) return null;
        return `    <item>
      <title>${esc(r.name ?? r.tag_name)}</title>
      <sparkle:version>${esc(version(r.tag_name))}</sparkle:version>
      <sparkle:shortVersionString>${esc(version(r.tag_name))}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>${new Date(r.published_at).toUTCString()}</pubDate>
      <sparkle:fullReleaseNotesLink>https://github.com/${REPO}/releases/tag/${esc(r.tag_name)}</sparkle:fullReleaseNotesLink>
      <enclosure url="${esc(asset.browser_download_url)}" length="${asset.size}" type="application/octet-stream" />
    </item>`;
      })
      .filter(Boolean)
      .join("\n");

    res.header("Content-Type", "application/xml; charset=utf-8");
    res.header("Cache-Control", "public, max-age=300");
    res.send(`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Panopticon</title>
    <link>https://github.com/${REPO}</link>
${items}
  </channel>
</rss>`);
  } catch (err) {
    res.status(502).send(`appcast unavailable: ${err instanceof Error ? err.message : "error"}`);
  }
}

// ── Download redirect ────────────────────────────────────────────────────
//
// Sends the visitor to the newest release's .zip so the landing button never
// points at a stale version. Falls back to the releases page if there is no
// downloadable asset yet.

export async function serveDownload(_req: Request, res: Response): Promise<void> {
  try {
    const releases = await fetchReleases();
    for (const r of releases) {
      if (r.prerelease) continue;
      const asset = r.assets.find((a) => /\.(zip|dmg)$/.test(a.name));
      if (asset) {
        res.redirect(302, asset.browser_download_url);
        return;
      }
    }
  } catch {
    // fall through to the releases page
  }
  res.redirect(302, `https://github.com/${REPO}/releases/latest`);
}

// ── Human changelog page ─────────────────────────────────────────────────

export async function serveChangelog(_req: Request, res: Response): Promise<void> {
  let releases: GhRelease[] = [];
  let error: string | null = null;
  try {
    releases = await fetchReleases();
  } catch (err) {
    error = err instanceof Error ? err.message : "failed to load releases";
  }

  const rows =
    releases.length === 0
      ? `<p class="muted">${error ? esc(error) : "No releases yet. The first tagged build will appear here."}</p>`
      : releases
          .map((r) => {
            const date = new Date(r.published_at).toLocaleDateString("en-US", {
              month: "short",
              day: "numeric",
              year: "numeric",
            });
            const asset = r.assets.find((a) => /\.(zip|dmg)$/.test(a.name));
            return `<article class="rel">
  <div class="rel-head">
    <span class="v">${esc(version(r.tag_name))}</span>
    <h2>${esc(r.name ?? r.tag_name)}</h2>
    <span class="d">${date}${r.prerelease ? " · pre-release" : ""}</span>
  </div>
  <div class="rel-body">${r.body ? renderBody(r.body) : '<p class="muted">No notes.</p>'}</div>
  <p class="rel-links">
    ${asset ? `<a class="u" href="${esc(asset.browser_download_url)}">Download ${esc(asset.name)}</a> · ` : ""}
    <a class="u" href="${esc(r.html_url)}" target="_blank" rel="noreferrer">View on GitHub</a>
  </p>
</article>`;
          })
          .join("\n");

  res.header("Content-Type", "text/html; charset=utf-8");
  res.header("Cache-Control", "public, max-age=300");
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Changelog: Panopticon</title>
<link rel="icon" type="image/png" href="/assets/app-icon.png" />
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet" />
<style>
  :root { --ink:#111110; --stone-600:#57534e; --stone-500:#78716c; --stone-300:#d6d3d1; --stone-200:#e7e5e4; --stone-100:#f5f5f4; --accent:#2f6fec; --mono:"JetBrains Mono",ui-monospace,monospace; }
  * { margin:0; padding:0; box-sizing:border-box; }
  body { background:#fff; color:var(--ink); font-family:"Inter",system-ui,sans-serif; font-size:16px; line-height:1.65; -webkit-font-smoothing:antialiased; }
  nav { max-width:72rem; margin:0 auto; display:flex; align-items:center; justify-content:space-between; padding:16px 20px; }
  @media (max-width:640px){ nav{ flex-wrap:wrap; gap:8px 16px; padding:14px 18px 12px; border-bottom:1px solid var(--stone-200); } main{ padding:40px 20px 72px; } }
  .brand { display:inline-flex; align-items:center; gap:8px; font-weight:600; font-size:15px; text-decoration:none; color:inherit; }
  .brand .mark { display:block; flex-shrink:0; }
  .u { color:inherit; text-decoration:underline; text-decoration-color:var(--stone-500); text-underline-offset:2.5px; }
  .u:hover { text-decoration-color:var(--ink); }
  main { max-width:600px; margin:0 auto; padding:64px 20px 96px; display:flex; flex-direction:column; gap:36px; }
  h1 { font-size:18px; font-weight:600; }
  .muted { color:var(--stone-500); }
  .rel { display:flex; flex-direction:column; gap:8px; border-top:1px solid var(--stone-200); padding-top:24px; }
  .rel-head { display:flex; align-items:baseline; gap:12px; flex-wrap:wrap; }
  .rel-head .v { font-family:var(--mono); font-size:13px; color:var(--accent); }
  .rel-head h2 { font-size:16px; font-weight:600; }
  .rel-head .d { font-size:13.5px; color:var(--stone-500); margin-left:auto; }
  .rel-body { color:var(--stone-600); font-size:15px; display:flex; flex-direction:column; gap:6px; }
  .rel-body ul { padding-left:20px; display:flex; flex-direction:column; gap:3px; }
  .rel-body code { font-family:var(--mono); font-size:13px; background:var(--stone-100); border-radius:4px; padding:1px 5px; }
  .rel-body b { color:var(--ink); font-weight:500; }
  .rel-links { font-size:14px; color:var(--stone-500); }
</style>
</head>
<body>
<nav>
  <a class="brand" href="/"><svg class="mark" width="17" height="17" viewBox="0 0 100 99" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M100 49C100 76.6142 77.6142 99 50 99C22.3858 99 0 76.6142 0 49H100Z" fill="#2645E3"/><rect y="23" width="100" height="23" fill="#2645E3"/><path d="M0 23C0 10.2975 10.2975 0 23 0H77C89.7025 0 100 10.2975 100 23V23H0V23Z" fill="#2645E3"/></svg>Panopticon</a>
  <a class="u" href="https://github.com/${REPO}" target="_blank" rel="noreferrer" style="font-size:14.5px">GitHub</a>
</nav>
<main>
  <div>
    <h1>Changelog</h1>
    <p class="muted">Every release, straight from GitHub. The app updates itself from the same feed.</p>
  </div>
  ${rows}
</main>
</body>
</html>`);
}
