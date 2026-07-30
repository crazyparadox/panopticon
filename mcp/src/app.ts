// Panopticon MCP server — the Express app (transport-agnostic). Runs as a
// long-lived process (src/index.ts → app.listen) or as a Vercel serverless
// function (api/index.ts → export default app). Stateless: a fresh MCP
// server + transport per request.
//
// Auth is a single shared bearer (PANOPTICON_TOKEN) checked on /mcp and
// /sync/* — this is a personal, single-user deployment; there is no OAuth.

import { readFileSync } from "node:fs";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { loadConfig } from "./config.js";
import { db } from "./db.js";
import { buildMcpServer } from "./mcpServer.js";
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
// app.js (see the build script), so resolve it relative to this module —
// a pattern Vercel's file tracer follows when bundling the function.
const landingHtml = readFileSync(new URL("./landing.html", import.meta.url), "utf8");
const serveLanding = (_req: Request, res: Response) => {
  res.header("Content-Type", "text/html; charset=utf-8");
  res.header("Cache-Control", "public, max-age=300");
  res.send(landingHtml);
};
app.get("/", serveLanding);
app.get("/landing", serveLanding);

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
