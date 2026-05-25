<p align="center">
  <img src="docs/logo/logo.png" alt="Rockxy" width="128" />
</p>

<h1 align="center">Rockxy</h1>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README.vi.md">Tiếng Việt</a> |
  <a href="README.zh.md">中文</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a>
</p>

<p align="center">
  <strong>The open-source, auditable HTTP debugging proxy for macOS.</strong>
</p>

<p align="center">
  Intercept, inspect, and modify HTTP/HTTPS/WebSocket/GraphQL traffic with a native Swift app you can inspect, build, and trust.<br>
  A local-first, AGPL-3.0 alternative to <a href="#rockxy-vs-alternatives">Proxyman and Charles Proxy</a>.
</p>

<p align="center">
  <a href="https://github.com/RockxyApp/Rockxy/releases"><img src="https://img.shields.io/github/v/release/RockxyApp/Rockxy?label=release&color=blue" alt="Release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License" /></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen" alt="PRs Welcome" /></a>
  <a href="https://github.com/sponsors/LocNguyenHuu"><img src="https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa" alt="Sponsor" /></a>
</p>

<p align="center">
  <img src="docs/images/Rockxy-Light.png" alt="Rockxy running on macOS" width="800" />
</p>

---

<!-- BEGIN GENERATED: latest-release -->
## Latest Tagged Release

**v0.21.1** — 2026-05-22

### Fixed

- Improved scripting stability so request and response scripts handle headers, console output, and runtime errors more reliably.
- Strengthened redaction for local MCP exports so sensitive request and rule data stays protected when shared with connected tools.
- Improved HAR imports and content-type detection for better handling of modern JSON-style responses and imported sessions.

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
<!-- END GENERATED: latest-release -->

## Current Branch Highlights

- Upstream Proxy now includes free/core Automatic Proxy Configuration with PAC URL routing for `DIRECT`, HTTP, and HTTPS routes while preserving existing SOCKS5 and authentication policy boundaries.
- Export workflows now cover OpenAPI YAML/HTML and selected-traffic Gist publishing with redaction-aware payload building.
- Inspector tools now include JSONPath/key/value filtering and quick previews for selected payload text such as JWTs.
- Node.js Developer Setup now mirrors the selected client during validation and has a fuller localhost sample guide.
- Developer Setup Hub now covers runtimes, browsers, clients, devices, frameworks, and environments with target-specific snippets, validation watchers, and honest guide content.
- WebSocket Protobuf work continues as part of Rockxy's richer protocol inspection direction.

## Features

**Traffic Capture** — SwiftNIO proxy with CONNECT tunnel, auto-generated per-host TLS certificates, WebSocket frame capture, and automatic GraphQL operation detection.

**Inspect Everything** — JSON tree viewer, hex inspector, timing waterfall (DNS/TCP/TLS/TTFB/Transfer), headers, cookies, query params, auth — all in a tabbed inspector.

**Mock & Modify** — Map Local (serve from files), Map Remote (redirect to another server), Breakpoints (pause and edit mid-flight), Block, Throttle, Modify Headers, Allow List, Bypass Proxy.

**Log Correlation** — Capture macOS logs (OSLog) and correlate them with network requests by timestamp. See which app made each request.

**Extend with Plugins** — JavaScript scripting in a sandboxed JavaScriptCore runtime. Inspect, modify, and automate traffic with custom hooks.

**Built for Scale** — NSTableView virtual scrolling handles 100k+ requests. Ring buffer eviction, disk body offloading, batched UI updates. Zero lag.

**Developer Setup Hub** — Guided setup per runtime, browser, device, framework, and environment with copyable snippets, validation probes, and troubleshooting notes.

**Upstream Proxy** — Chain captured traffic through HTTP/HTTPS upstream proxies or a PAC URL for automatic proxy configuration in team, VPN-adjacent, and lab networks.

**Local MCP Bridge** — Bundled Model Context Protocol server lets local MCP clients query live traffic, rules, and proxy status. Local-only, token-authenticated, sensitive data redacted by default.

> 100% native macOS. No Electron. No web views. SwiftUI + AppKit + SwiftNIO.

## Quick Start

```bash
git clone https://github.com/RockxyApp/Rockxy.git
cd Rockxy
open Rockxy.xcodeproj
```

Build and run in Xcode. The Welcome window guides you through root CA setup, helper installation, and proxy activation.

**Requirements:** macOS 14.0+, Xcode 16+, Swift 5.9

If you want to connect Rockxy to a local MCP client after installation, see the [MCP Integration guide](docs/features/mcp.mdx).

## Rockxy vs. Alternatives

|  | **Rockxy** | **Proxyman** | **Charles Proxy** |
|---|---|---|---|
| **Project model** | AGPL-3.0 open-source project | Proprietary commercial app | Proprietary commercial app |
| **Source code** | Public, auditable, forkable | Closed source | Closed source |
| **Build from source** | Free with Xcode from this repo | Not available from public source | Not available from public source |
| **Native macOS foundation** | Swift + SwiftNIO + SwiftUI/AppKit | Native macOS commercial app | Cross-platform commercial app |
| **Local-first capture** | Local proxy, certificates, helper, and capture data stay on your Mac | Desktop proxy app | Desktop proxy app |
| **Developer setup workflow** | Built-in Developer Setup Hub for runtimes, clients, devices, frameworks, and environments | Product-specific setup guidance | Product-specific setup guidance |
| **External proxy + PAC routing** | HTTP/HTTPS upstream proxy, PAC auto-configuration, and bypass rules | Mature commercial proxy tooling | Mature commercial proxy tooling |
| **MCP/local automation bridge** | Built in, token-authenticated, redaction by default | Not claimed in public docs reviewed | Not claimed in public docs reviewed |
| **Open contribution path** | Public issues, discussions, roadmap, and PRs | Vendor-controlled product | Vendor-controlled product |

On the roadmap: deeper replay/diff/rules/scripting workflows, improved WebSocket and GraphQL inspection, and exploration of gRPC/Protobuf plus HTTP/2 and HTTP/3 support.

## Security

Rockxy intercepts network traffic — security is foundational, not optional.

- XPC helper validates callers via **certificate-chain comparison**, not just bundle ID
- Plugins run in **sandboxed JavaScriptCore** with 5-second timeout, no filesystem/network access
- **Input validation** on all boundaries — body size caps, URI limits, regex DoS protection, path traversal prevention
- Credentials **automatically redacted** in captured logs
- Sensitive files stored with **0o600 permissions**

Report vulnerabilities via [SECURITY.md](SECURITY.md). See the [full security architecture](docs/development/security.mdx) for details.

## Roadmap

Rockxy's public roadmap is workflow-oriented and date-free. It focuses on reliability, native macOS UX, debugging workflows, protocol support, documentation, and contributor onboarding.

- [ROADMAP.md](ROADMAP.md): high-level public engineering direction
- [Rockxy Public Roadmap](https://github.com/orgs/RockxyApp/projects/1): operational visibility for roadmap-tracked issues

## Documentation

Full documentation available at the [Rockxy Docs](docs/index.mdx):

- [Quickstart Guide](docs/quickstart.mdx) — get up and running in minutes
- [Developer Setup Hub](docs/features/developer-setup-hub.mdx) — runtime snippets, device guides, validation probes, and support matrix
- [MCP Integration](docs/features/mcp.mdx) — connect Rockxy to local MCP clients
- [Architecture](docs/development/architecture.mdx) — proxy engine, actor model, data flow
- [Security Model](docs/development/security.mdx) — trust boundaries, XPC validation, certificate management
- [Design Decisions](docs/development/design-decisions.mdx) — why SwiftNIO, NSTableView, actors
- [Building from Source](docs/development/building.mdx) — build, test, lint, and debug
- [Code Style](docs/development/code-style.mdx) — SwiftLint, SwiftFormat, and conventions
- [Changelog](CHANGELOG.md) — unreleased work and tagged releases

## Contributing

Contributions welcome — code, tests, docs, bug reports, and UX feedback.

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for setup instructions, code style, and the full PR checklist.

Good first issues are labeled [`good first issue`](https://github.com/RockxyApp/Rockxy/labels/good%20first%20issue). By opening a PR, you agree to the [CLA](CLA.md).

## Sponsors & Partners

Rockxy is built and maintained by independent developers. Sponsorships fund continued development, security audits, and new features.

<p align="center">
  <a href="https://github.com/sponsors/LocNguyenHuu">
    <img src="https://img.shields.io/badge/Sponsor_Rockxy-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor Rockxy" />
  </a>
</p>

| Tier | Benefits |
|------|----------|
| **Gold Sponsor** | Logo on README + docs site, priority feature requests, direct support channel |
| **Silver Sponsor** | Logo on README, named acknowledgment in release notes |
| **Bronze Sponsor** | Named acknowledgment in README and docs |
| **Partner** | Co-development, integration support, early access to upcoming features |

**Partnership inquiries** — developer tool companies, security firms, and enterprise teams looking for custom integrations or white-label solutions: [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)

## Support

- [GitHub Sponsors](https://github.com/sponsors/LocNguyenHuu) — support Rockxy's development
- [GitHub Issues](https://github.com/RockxyApp/Rockxy/issues) — bug reports and feature requests
- [GitHub Discussions](https://github.com/RockxyApp/Rockxy/discussions) — questions and community chat
- **Email** — [rockxyapp@gmail.com](mailto:rockxyapp@gmail.com)
- **Security issues** — see [SECURITY.md](SECURITY.md) for responsible disclosure

## License

[GNU Affero General Public License v3.0](LICENSE) — Copyright 2024–2026 Rockxy Contributors.

## Star History

<a href="https://www.star-history.com/?repos=RockxyApp%2FRockxy&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=RockxyApp/Rockxy&type=date&legend=top-left" />
 </picture>
</a>

---

<p align="center">
  <sub>Made by <a href="https://github.com/LocNguyenHuu">Stephen</a>. Built with Swift, SwiftNIO, SwiftUI, and AppKit.</sub>
</p>
