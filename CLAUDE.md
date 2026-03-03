# CLAUDE.md

This file provides guidance for AI assistants (Claude Code and similar tools) working in this repository.

---

## Repository Overview

- **Owner:** Afshinnazari1985
- **Remote:** `http://local_proxy@127.0.0.1:33421/git/Afshinnazari1985/Afshinnazari1985`
- **State:** Freshly initialized — no source code has been committed yet.

> This file should be updated as the project grows. Sections marked `[TODO]` are placeholders awaiting content.

---

## Git Workflow

### Branch Naming Conventions

| Prefix | Purpose |
|--------|---------|
| `claude/` | Branches created and managed by AI assistants |
| `feature/` | New features |
| `fix/` | Bug fixes |
| `chore/` | Maintenance, refactoring, dependency updates |
| `docs/` | Documentation-only changes |

AI assistant branches follow the pattern: `claude/<task-slug>-<session-id>`

### Commit Messages

Write clear, imperative commit messages:

```
<type>: <short summary>

Optional longer explanation of why the change was made.
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`

Examples:
- `feat: add user authentication endpoint`
- `fix: handle null response from payment API`
- `docs: update CLAUDE.md with project structure`

### Push Workflow

Always push to the designated feature branch:

```bash
git push -u origin <branch-name>
```

- Branches must start with `claude/` for AI-managed branches.
- Never push directly to `main` or `master` without explicit permission.
- On network failure, retry up to 4 times with exponential backoff: 2s, 4s, 8s, 16s.

---

## Development Setup

[TODO: Document how to install dependencies and set up the local environment once the project is initialized.]

```bash
# Example — update with actual commands
# npm install        (Node.js projects)
# pip install -r requirements.txt  (Python projects)
# cargo build        (Rust projects)
```

---

## Project Structure

[TODO: Describe the directory layout once source files are added. Example format:]

```
/
├── src/           # Application source code
├── tests/         # Test files
├── docs/          # Documentation
├── scripts/       # Utility/build scripts
└── CLAUDE.md      # This file
```

---

## Running Tests

[TODO: Document test commands once a test framework is configured.]

```bash
# Example — update with actual commands
# npm test
# pytest
# cargo test
```

---

## Code Style & Conventions

[TODO: Document linting, formatting, and style rules once tooling is configured.]

- Prefer descriptive variable names over abbreviations.
- Keep functions small and single-purpose.
- Do not introduce security vulnerabilities (SQL injection, XSS, command injection, etc.).
- Avoid over-engineering: build only what the current task requires.

---

## CI/CD

[TODO: Document CI/CD pipeline once GitHub Actions or equivalent is configured.]

---

## Key Principles for AI Assistants

1. **Read before modifying** — always read a file before editing it.
2. **Minimal changes** — only change what is directly requested or clearly necessary.
3. **No unnecessary files** — do not create files that aren't needed for the task.
4. **Security first** — never introduce vulnerabilities; validate at system boundaries.
5. **Ask before destructive actions** — confirm before `git reset --hard`, force-push, deleting files, or other irreversible operations.
6. **Stay on the designated branch** — develop on the branch specified in the task; never push to another branch without explicit permission.
7. **Update this file** — when new tools, workflows, or conventions are established, update the relevant sections above.

---

*Last updated: 2026-03-03 — Initial creation on empty repository.*
