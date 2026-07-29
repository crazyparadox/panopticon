# Panopticon

A background screen recorder for macOS. It captures your screen, turns the
captures into a structured activity timeline with an LLM, and stores everything
locally in SQLite so your own agents can read it.

Panopticon has no dashboard. It is a capture-and-store daemon: the data is the
product, and it is meant to be consumed programmatically (an MCP server is
planned) rather than browsed in-app.

## What it does

- Captures periodic screenshots via ScreenCaptureKit, skipping idle stretches.
- Batches captures and sends them to an LLM provider to produce timeline cards
  (title, summary, category, apps/sites, distractions).
- Generates a daily recap in the background.
- Stores screenshots, observations, timeline cards, and recaps in a local
  GRDB/SQLite database.

## What it deliberately does not do

- No timeline, weekly, or dashboard UI.
- No accounts, subscriptions, hosted backend, analytics, or crash reporting.
- No auto-update.

The only in-app surfaces are onboarding (permissions + LLM provider setup),
Settings, and a menu bar item.

## LLM providers

Timeline generation needs one provider configured in Settings → Providers:

| Provider | Notes |
| --- | --- |
| Gemini | API key, free tier available |
| ChatGPT / Claude | Runs through the `codex` or `claude` CLI on your machine |
| Local | Ollama, LM Studio, or any compatible local server |

A secondary provider can be set as a fallback.

## Build

Requires Xcode 16+ and macOS 14+.

To build from the command line without a signing certificate:

```sh
xcodebuild -project Panopticon/Panopticon.xcodeproj -scheme Panopticon \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Screen recording permission must be granted in System Settings → Privacy &
Security → Screen Recording.

## Data location

Recordings and the database live under `~/Library/Application Support/`. Nothing
leaves your machine except the screenshots sent to whichever LLM provider you
configure.

## Roadmap

- MCP server exposing timeline, recaps, and screenshots to local agents
- Optional cloud sync for captured data
- Notes capture

## License

See [LICENSE](LICENSE).
