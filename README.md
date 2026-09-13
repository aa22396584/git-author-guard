# git-author-guard

**Development, Issues & Pull Requests:**  
https://github.com/aa22396584/git-author-guard

**Mirrors:**  
[GitLab](https://gitlab.com/aa22396584/git-author-guard) ·
[Codeberg](https://codeberg.org/ImL1s/git-author-guard)


Stop AI coding agents (and yourself) from committing under the **wrong git identity**.

Many teams scan pushed commits and flag any `author_email` that isn't an approved
work identity — `*@local`, `cursor-agent@local`, a personal Gmail, etc. Those bad
authors usually come from a *tool silently rewriting the author*, not a person
choosing badly. This package is a small, layered gate that makes such a commit
fail locally before it is ever made or pushed.

It enforces an **allowlist of author/committer emails** across normal git *and*
across the shell your AI agents run, so `--no-verify`, `--author=`, `GIT_AUTHOR_*`,
and disabling the hooks path can't slip past.

## What it blocks (all verified)

| Attempt | Caught by | Result |
|---|---|---|
| Normal commit with wrong `user.email` | A. git hook | blocked |
| `git commit --no-verify` | A (`--no-verify` can't skip `prepare-commit-msg`) | blocked |
| `git commit --author='x <x@local>'` | A (hook reads `git var GIT_AUTHOR_IDENT` = the *effective* identity) | blocked |
| `GIT_AUTHOR_EMAIL=x@local git commit` | A (same) | blocked |
| A bad commit already made, then pushed | B. `pre-push` (scans only `@{u}..HEAD`) | blocked |
| Disabling the hooks path to skip the hook, then commit | C/D/E agent deny | blocked |
| `git commit-tree` (builds a commit bypassing all hooks) | C/D/E agent deny | blocked |
| `git config --global user.email …` | C/D/E agent deny | blocked |

**Layer A is the main gate** — it catches anyone using normal git, including
`--no-verify`, because it checks the *effective* author (`git var
GIT_AUTHOR_IDENT`), which is what `--author=` and the env vars have already been
folded into.

**Layers C/D/E only cover A's two blind spots** (disabling the hooks path, and
`commit-tree`) by inspecting the command string *before* an AI agent's shell runs
it. They do **not** replace A: open a plain terminal and they don't apply — only
A/B do.

**Known gap (be honest about it):** a determined person on a real terminal can
still disable the hooks path and use low-level plumbing to forge a commit. Closing
that needs a *server-side* hook / push rule on your git host. This package's job is
to stop *agent slip-ups and honest misconfiguration*, not a deliberate insider.

## Layers

- **A** — git `prepare-commit-msg` / `pre-commit` / `pre-merge-commit` reject any
  commit whose author or committer email isn't in `hooks/authors.allow`.
- **B** — `pre-push` scans only the commits you're actually pushing that the remote
  doesn't have yet (`@{u}..HEAD`), so existing history (e.g. teammates' old
  commits) is never falsely blocked.
- **C** — Cursor CLI deny rules (`Shell(...)`), verified against cursor-agent's real
  matcher.
- **D/E** — a `PreToolUse` deny script for Claude Code and Codex (they share the
  same hook contract, so one script serves both).

## Install

```bash
# 1. Set your allowlist (one email per line)
cp hooks/authors.allow.example hooks/authors.allow
$EDITOR hooks/authors.allow

# 2. Protect one or more repos + wire up whatever agents you have installed
./install.sh /path/to/repoA /path/to/repoB
./install.sh --check /path/to/repoA      # check only, change nothing
./install.sh --agents-only               # only wire agents, touch no repo
```

`install.sh` is idempotent. It sets each repo's **local** `core.hooksPath` to this
package's `hooks/` dir, and *appends* the deny to each agent's config (it never
edits an existing hook, and never touches global git config or a repo's remotes).

### Manual finish

- **Codex** — after `~/.codex/hooks.json` changes, run `/hooks` in Codex to trust it,
  or the hook won't run.
- **Grok Build** — use its `/hooks-add` pointing at `agents/agent-deny-git.mjs`
  (no auto-wiring for it here).
- **Antigravity** — if it reads a Claude-compatible `settings.json`, point it at the
  same deny script; otherwise add it manually.

## Notes

- `hooks/authors.allow` is git-ignored — your real allowlist never gets committed;
  only `authors.allow.example` ships.
- **Fail-closed:** if `authors.allow` is missing, the hook rejects the commit rather
  than guessing who's allowed.
- The deny script matches on the **whole command string**, so writing docs that
  *quote* these dangerous commands via a shell heredoc will trip it — use an editor
  for such files, not `cat <<EOF`. This is deliberate: it errs toward blocking.
- `core.hooksPath` is a **local** repo setting pointing at this package — the hook
  scripts are never added to your repo or pushed anywhere.

## License

MIT — see `LICENSE`.
