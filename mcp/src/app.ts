// Panopticon MCP server: the Express app (transport-agnostic). Runs as a
// long-lived process (src/index.ts → app.listen) or as a Vercel serverless
// function (api/index.ts → export default app). Stateless: a fresh MCP
// server + transport per request.
//
// Auth is a single shared bearer (PANOPTICON_TOKEN) checked on /mcp and
// /sync/*. This is a personal, single-user deployment; there is no OAuth.

import { readFileSync } from "node:fs";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { loadConfig } from "./config.js";
import { db } from "./db.js";
import { buildMcpServer } from "./mcpServer.js";
import { recentReleaseRows, serveAppcast, serveChangelog, serveDownload } from "./releases.js";
import { buildSyncRouter } from "./sync.js";

export const config = loadConfig();
const sql = db(config.databaseUrl);

const app: Express = express();

// Trust the platform proxy (Vercel) so req is seen as https.
app.set("trust proxy", true);
app.use(express.json({ limit: "8mb" }));

// Permissive CORS (browser-hosted MCP clients call cross-origin).
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", req.headers.origin ?? "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.header(
    "Access-Control-Allow-Headers",
    "Authorization, Content-Type, Accept, mcp-session-id, mcp-protocol-version",
  );
  res.header("Access-Control-Expose-Headers", "Mcp-Session-Id");
  if (req.method === "OPTIONS") {
    res.sendStatus(204);
    return;
  }
  next();
});

app.get("/health", (_req, res) => {
  res.status(200).send("ok");
});

// Landing page. The build copies src/landing.html next to the compiled
// app.js (see the build script), so resolve it relative to this module,
// a pattern Vercel's file tracer follows when bundling the function.
const landingHtml = readFileSync(new URL("./landing.html", import.meta.url), "utf8");
const staticAssets: Record<string, Buffer> = {
  "iphone-frame.png": readFileSync(new URL("./assets/iphone-frame.png", import.meta.url)),
  "poke-logo.png": readFileSync(new URL("./assets/poke-logo.png", import.meta.url)),
  "folk-logo.png": readFileSync(new URL("./assets/folk-logo.png", import.meta.url)),
  "hermes-logo.png": readFileSync(new URL("./assets/hermes-logo.png", import.meta.url)),
  "openclaw-logo.png": readFileSync(new URL("./assets/openclaw-logo.png", import.meta.url)),
  "wall-imessage.jpg": readFileSync(new URL("./assets/wall-imessage.jpg", import.meta.url)),
  "wall-telegram.jpg": readFileSync(new URL("./assets/wall-telegram.jpg", import.meta.url)),
  "wall-whatsapp.jpg": readFileSync(new URL("./assets/wall-whatsapp.jpg", import.meta.url)),
  "app-icon.png": readFileSync(new URL("./assets/app-icon.png", import.meta.url)),
};
const IS_DEV = process.env.NODE_ENV !== "production" && !process.env.VERCEL;

// react-grab lets you select an element in the browser and hand its context
// to a coding agent. Dev-only; it must never reach the deployed page.
const GRAB_SNIPPET =
  '<script crossorigin src="https://unpkg.com/react-grab/dist/index.global.js"></script>';

const serveLanding = async (_req: Request, res: Response) => {
  // The changelog block is filled from the real GitHub releases at request
  // time (5-min cached upstream). If that lookup comes back empty we drop the
  // block entirely rather than show a version history we made up.
  const rows = await recentReleaseRows();
  let html = landingHtml.replace(
    "<!--RELEASE_ROWS-->",
    rows ?? '      <p class="muted" style="font-size:14px">No tagged releases yet.</p>'
  );
  if (IS_DEV) html = html.replace("</body>", `${GRAB_SNIPPET}\n</body>`);
  res.header("Content-Type", "text/html; charset=utf-8");
  res.header("Cache-Control", IS_DEV ? "no-store" : "public, max-age=300");
  res.send(html);
};
// The landing page is the project's marketing site, not part of the server a
// user deploys. A self-hosted instance is one person's private endpoint, so it
// serves a short status page at / instead and skips the marketing routes
// entirely. Set PANOPTICON_PUBLIC_SITE=1 on the canonical deployment.
const SERVE_PUBLIC_SITE = process.env.PANOPTICON_PUBLIC_SITE === "1" || IS_DEV;

const serveInstanceStatus = (_req: Request, res: Response) => {
  res.header("Content-Type", "text/html; charset=utf-8");
  res.header("Cache-Control", "no-store");
  // Deliberately plain: confirms the deploy works and says what to do next,
  // without pretending to be a product page.
  res.send(`<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Panopticon MCP</title>
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
    background:#101828; color:#EAECF0; font:15px/1.6 ui-sans-serif,system-ui,sans-serif; }
  main { max-width:34rem; padding:32px 24px; }
  h1 { margin:0 0 6px; font-size:17px; font-weight:600; }
  p { margin:0 0 14px; color:#98A2B3; font-size:14px; }
  code { font-family:ui-monospace,monospace; font-size:13px; background:#1D2939;
    border-radius:5px; padding:2px 6px; color:#EAECF0; }
  ul { margin:0; padding-left:18px; color:#98A2B3; font-size:14px; }
  li { margin:3px 0; }
</style></head>
<body><main>
  <h1>Panopticon MCP server</h1>
  <p>This instance is running. Point the Mac app and your agents at it.</p>
  <ul>
    <li><code>/mcp</code> &mdash; MCP endpoint for your agents</li>
    <li><code>/sync</code> &mdash; where the app pushes day snapshots</li>
    <li><code>/health</code> &mdash; liveness check</li>
  </ul>
  <p style="margin-top:14px">Both require the bearer token you configured as
  <code>PANOPTICON_TOKEN</code>.</p>
</main></body></html>`);
};

app.get("/", SERVE_PUBLIC_SITE ? serveLanding : serveInstanceStatus);
if (SERVE_PUBLIC_SITE) {
  app.get("/landing", serveLanding);
  app.get("/changelog", serveChangelog);
}
// Update routes stay on every instance: a self-hoster can point the app's
// SUFeedURL at their own server.
app.get("/download", serveDownload);
app.get("/appcast.xml", serveAppcast);

app.get("/assets/:name", (req: Request, res: Response) => {
  const name = String(req.params.name ?? "");
  const asset = staticAssets[name];
  if (!asset) {
    res.status(404).send("not found");
    return;
  }
  res.header("Content-Type", name.endsWith(".jpg") ? "image/jpeg" : "image/png");
  res.header("Cache-Control", "public, max-age=86400, immutable");
  res.send(asset);
});

function requireBearer(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  if (token !== config.token) {
    res.status(401).json({ error: "missing or invalid bearer token" });
    return;
  }
  next();
}

// --- Sync ingest (Mac app → Neon) ---
app.use("/sync", requireBearer, buildSyncRouter(sql));

// --- MCP (agents → timeline) ---
app.post("/mcp", requireBearer, async (req: Request, res: Response) => {
  // Fresh server+transport per request; sessionless (stateless serverless).
  const server = buildMcpServer(sql);
  const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
  res.on("close", () => {
    void transport.close();
    void server.close();
  });
  try {
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (err) {
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: "2.0",
        error: { code: -32603, message: err instanceof Error ? err.message : "internal error" },
        id: null,
      });
    }
  }
});

// Stateless transport: GET (SSE resumption) and DELETE (session teardown)
// don't apply; answer 405 per the MCP spec.
const methodNotAllowed = (_req: Request, res: Response) => {
  res.status(405).json({
    jsonrpc: "2.0",
    error: { code: -32000, message: "Method not allowed for stateless server" },
    id: null,
  });
};
app.get("/mcp", methodNotAllowed);
app.delete("/mcp", methodNotAllowed);

export default app;
