# CLAUDE.md

Guidance for Claude Code (and other AI coding agents) working in this repository.

## Project overview

AgentGuard is a Go command-line tool that derives a least-privilege permission policy for an AI coding agent from a project's own configuration, then enforces it. Safe actions are auto-approved, dangerous ones are blocked, and everything else falls back to the agent's normal permission prompt.

- Module path: `github.com/omkarjoshi9/agentguard`
- First supported agent: Claude Code. First supported platform: Linux.
- Status: early development. See "Current status" below.

## Non-negotiable design rules

These define the security model. Do not weaken them without an explicit design discussion and a new entry in `docs/DECISIONS.md` (if that folder is present locally).

1. **Decision order:** `deny`, then `allow`, then `ask`, then `default`. The first matching rule in a list wins. `default` is `ask`.
2. **Fail safe:** any error, parse doubt, unknown tool, or malformed input results in `ask`. Never `allow`. A failure to write a log entry must not change a decision.
3. **Deterministic:** no LLM or other probabilistic component in the decision path. Fixed rules and string/path matching only.
4. **Trust model:**
   - Code and config files (`package.json`, `go.mod`, `Cargo.toml`, lockfiles, `Makefile`, `Dockerfile`, `.git/`) may create `allow` rules.
   - Documentation (`README.md`, `CLAUDE.md`, any `*.md`) is untrusted. The scanner must not read it to create `allow` rules.
   - Repeated human approvals may only produce *suggestions*. A human confirms each one.
5. **Self-protection:** the agent must not be able to modify the rules file, AgentGuard's own files, or the agent's hook configuration (for Claude Code: `.claude/settings*.json` and `~/.claude/**`).
6. **Provenance:** every rule records a `source` (the file or observation that produced it).
7. **Command chaining:** shell commands are split on `;`, `&&`, `||`, `|` and newlines; every part is evaluated; the most restrictive result wins. Commands that cannot be parsed with confidence result in `ask`.
8. **Path handling:** paths are made absolute, cleaned of `..`, and symlink-resolved before matching.

## Claude Code hook protocol

Authoritative source: https://code.claude.com/docs/en/hooks. **Verify against it before changing hook code**; the format can change between Claude Code releases.

- Input: one JSON object on stdin with `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`. PostToolUse adds `tool_response`.
- `tool_input` fields used: Bash `command`; Read `file_path`; Write `file_path`, `content`; Edit `file_path`, `old_string`, `new_string`; Glob `pattern`, `path`; Grep `pattern`, `path`, `glob`; WebFetch `url`.
- Output (PreToolUse): exit code `0` and JSON on stdout:
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow|deny|ask","permissionDecisionReason":"..."}}`
- Exit code `2` blocks the action; any other non-zero code is a non-blocking error and the action proceeds. Therefore errors must print an explicit `ask` and exit `0`.
- A hook `allow` does not override `deny`/`ask` rules in the agent's own settings.

## Repository layout

```
cmd/agentguard/     program entry point (package main)
internal/cli/       Cobra commands
internal/scanner/   project files to rules
internal/rules/     rules file load/save, matching, decision engine
internal/hook/      agent JSON in, decision JSON out
internal/learn/     observations to suggestions
internal/store/     SQLite decision log
internal/osguard/   Docker + eBPF + proxy (OS enforcement layer)
testdata/           sample projects and hook inputs used by tests
docs/               plans, architecture, decisions, glossary (local only; git-ignored)
```

Dependency direction: `cli` depends on `hook`, `scanner`, `learn`; those depend on `rules` and `store`. `rules` imports none of our other packages, so the decision core stays easy to test.

## Build, test, run

```
make build   # go build -o bin/agentguard ./cmd/agentguard
make run     # go run ./cmd/agentguard
make test    # go test ./...
make clean   # remove bin/
```

Go may live in `/usr/local/go/bin`, which is not always on `PATH` in non-interactive shells.

## Conventions

- Idiomatic Go, formatted with `gofmt`; `go vet ./...` must be clean.
- Prefer the standard library. Add a third-party dependency only when it clearly earns its place, and say why in the commit message.
- Errors are returned and wrapped with context (`fmt.Errorf("...: %w", err)`), never ignored.
- Table-driven tests. Security-relevant behaviour (deny precedence, fail-safe, path escapes, chained commands, hostile inputs) needs explicit tests. Fixtures live in `testdata/`.
- Keep comments short and about *why*, not *what*.
- No global mutable state where it can be avoided.
- Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Working conventions for agent sessions

- Work in small, reviewable steps; explain what each change is for.
- Never guess an external API or file format. Check the official documentation first.
- Do not widen scope: finish the current phase's goal before starting the next.
- Report results honestly: say what was run, what passed, and what was not verified.

## Current status

Phase 0 (scaffolding): the module, folder structure, Makefile and a stub `main.go` that prints a version string. No decision logic exists yet. Planned phases:

1. Scanner and Claude Code hook (`init`, `hook`, `install`, `log`)
2. Learning from approvals (SQLite, `learn`, `rules`)
3. OS enforcement layer (Docker, eBPF, proxy)
4. Dashboard and benchmark
