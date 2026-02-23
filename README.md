# Reli

![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Release](https://img.shields.io/github/v/release/710csm/Reli)
![CI](https://github.com/710csm/Reli/actions/workflows/reli.yml/badge.svg)
![Stars](https://img.shields.io/github/stars/710csm/Reli?style=social)

**AI-powered Swift refactoring linter with SwiftSyntax-based structural analysis and CI integration.**

Reli scans your Swift codebase, detects architectural and structural code smells, and optionally generates AI-driven refactoring guidance in a clean Markdown report.

Built for local development and CI environments.

---

## ✨ Features

- 🔍 Recursively scans Swift files in a project
- 🧠 SwiftSyntax-based type analysis (class / struct / enum)
- 🎯 AI analysis limited via `--ai-limit` for predictable performance
- 🚦 CI-friendly modes (`--fail-on`, GitHub annotations)
- 🧪 Excludes Tests/Samples by default (opt-in available)
- 📊 Detects structural issues (God Type, DI Smell, Async Lifecycle risks)
- 📝 Generates Markdown or JSON reports
- 🤖 Optional AI-powered refactoring recommendations
- ⚙️ Designed for CLI usage (local + CI workflows)
- 🧱 Modular architecture (Core / Rules / CLI)

---

## Requirements

- macOS 10.15+
- Swift 5.9+
- (Optional) OpenAI API key for AI recommendations

---

## Installation

### Option 1 — Homebrew (Recommended for distribution)

```bash
brew tap 710csm/tap
brew install reli
```

---

### Option 2 — Swift Package Manager (Source)

```bash
git clone https://github.com/710csm/Reli.git
cd Reli
swift run reli --help
```

---

## Quick Start

### Run static analysis only

```bash
reli --path /path/to/project --no-ai --out report.md
```

---

### Run with AI recommendations

Set your API key:

```bash
export OPENAI_API_KEY="sk-..."
```

Run:

```bash
reli --path /path/to/project --out report.md --model gpt-4o-mini
```

---

## Usage

```
reli [--config <path>] [--print-config] [--path <path>] [--no-ai] [--rules <rules>] [--format <format>] [--out <out>] [--model <model>] [--ai-limit <ai-limit>] [--fail-on <severity>] [--annotations github]
```

### Options

| Option | Description |
|--------|------------|
| `--config` | Load options from a YAML config file |
| `--print-config` | Print the final merged config (CLI > config > defaults) as JSON |
| `--path` | Project root directory (default: current directory) |
| `--no-ai` | Disable AI recommendations |
| `--rules` | Comma-separated rule IDs to run |
| `--format` | `markdown` or `json` (default: `markdown`) |
| `--out` | Output file path |
| `--model` | AI model (e.g. `gpt-4o-mini`, `gpt-4.1-mini`) |
| `--ai-limit` | Maximum number of findings sent to AI (default: `5`) |
| `--fail-on` | Exit with code 1 if findings meet or exceed severity (`off`, `low`, `medium`, `high`) |
| `--annotations github` | Emit GitHub Actions workflow annotations (`::warning`, `::error`) |

---

## Config File (`.reli.yml`)

Reli can load defaults from a YAML config file.

Resolution order:
1. `--config <path>` (required to exist)
2. `./.reli.yml` (auto-discovered from current working directory)
3. no config (existing CLI defaults apply)

Precedence:
- CLI options override config values
- config values override built-in defaults

Supported keys:
- `path`
- `noAI`
- `aiLimit`
- `model`
- `failOn` (`off|low|medium|high`)
- `annotations` (`off|github`)
- `format` (`markdown|json`)
- `out`
- `rules` (`all` or string array)
- `includeExtensions`
- `includeTests`
- `includeSamples`
- `excludePaths` (glob array)
- `maxFindings`
- `pathStyle` (`relative|absolute`)

Example:

```yaml
aiLimit: 5
failOn: high
annotations: github
format: markdown
out: reli-report.md
includeExtensions: false
includeTests: false
includeSamples: false
excludePaths:
  - "**/*Tests*/**"
  - "**/*Sample*/**"
  - "**/Examples/**"
rules: all
```

`reli.yml.example` is included in the repository root.

---

## Rules

### `god-type`
Detects large files/types based on function and line thresholds. Encourages responsibility separation and modular design.

### `di-smell`
Detects excessive `.shared` singleton usage and direct instantiations. Encourages dependency injection and improved testability.

### `async-lifecycle`
Detects async patterns (`Task`, `Timer`, `asyncAfter`) without proper lifecycle handling. Encourages cancellation and safe lifecycle management.

> Reli now uses SwiftSyntax-based structural analysis for improved accuracy and reduced false positives.

---

## Output

### Markdown Report

- Grouped by severity (High / Medium / Low)
- Evidence included (counts, thresholds)
- AI recommendations include:
  - Root cause analysis
  - Refactoring steps
  - Risk assessment
  - Verification checklist

### Summary Insights

The report includes ranked insights such as:
- Top files by number of findings
- Top types by size (line count)
- Severity distribution overview

---

## CI Integration (GitHub Actions Example)

```yaml
name: reli

on:
  pull_request:
  push:

jobs:
  lint:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v4

      - name: Run Reli (static only)
        run: |
          reli --path . --no-ai --out reli-report.md

      - name: Upload report
        uses: actions/upload-artifact@v4
        with:
          name: reli-report
          path: reli-report.md
```

With AI enabled:

```yaml
      - name: Run Reli (AI enabled)
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          reli --path . --out reli-report.md --model gpt-4o-mini
```

---

## Security

- Never commit API keys.
- Use environment variables or CI secrets.
- Ensure local config files are ignored via `.gitignore`.

---

## Roadmap

- More advanced architectural rules
- GitHub PR annotations
- Multi-provider AI support (local LLM, Azure, etc.)
- CI fail-on-severity options

---

## Performance & AI Usage

By default, Reli limits AI analysis to the top 5 findings using `--ai-limit` to ensure fast execution and predictable API usage.

You can adjust this behavior:

```bash
reli --path . --ai-limit 3
```

Set `--ai-limit 0` to disable AI calls without using `--no-ai`.

This design ensures that large projects remain responsive while still providing high-impact AI insights.

---

## Philosophy

Reli does not enforce stylistic preferences.
It focuses on structural maintainability and architectural health.

AI recommendations are advisory, not authoritative.
Always validate suggestions within your project context.

---

## License

MIT License (see `LICENSE` file)

---

## Contributing

Issues and pull requests are welcome.

If reporting a false positive, please include:
- The Swift file snippet
- The generated report
- Expected behavior
