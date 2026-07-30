// Vercel serverless entry point. Vercel rewrites every path to this function
// (see vercel.json); the exported Express app routes /mcp, /sync/* and
// /health internally. Imports the COMPILED app (../dist/app.js) — the `build`
// script (tsc) runs before Vercel bundles functions, so dist exists at bundle
// time; importing built .js avoids TS/.js-extension resolution ambiguity in
// the function bundler. (Same pattern as flowy-mcp.)
import app from "../dist/app.js";

export default app;
