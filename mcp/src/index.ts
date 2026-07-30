// Long-lived entry point for local dev (`npm run dev`) and container hosting.
// Vercel uses api/index.ts instead.

import app, { config } from "./app.js";

app.listen(config.port, () => {
  console.log(`panopticon-mcp listening on :${config.port}`);
  console.log(`  MCP:   POST http://localhost:${config.port}/mcp`);
  console.log(`  Sync:  POST http://localhost:${config.port}/sync/days`);
});
