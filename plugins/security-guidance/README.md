# Security guidance for Codex

Codex-only bridge; the official Claude plugin remains installed independently.
Requires `uv`, Git and the signed-in Codex CLI. Inherits the configured Codex model;
does not require an Anthropic API key or copy Claude model names.

- Edits: apply_patch added lines are checked against the 25 upstream security
  pattern rules; reminders deduplicate per session, file and rule. Shell-based
  file writes are not observed. Custom CC user rules and baseline suppression
  are not yet bridged.
- Commit/push: capture pre-command SHA/outgoing range for literal Git commands,
  review new commits through native `codex review` in a read-only child with hooks
  disabled, and deduplicate successful reviews by repository and immutable SHA.
  Push without an upstream reviews HEAD. Dynamic shell expressions, `git -c`,
  `gt` and custom wrappers require manual review. Push reviews run even when the
  push fails, so a failed network request does not skip local security checking.
- Stop review stays disabled, matching the user's existing preference. Stop does
  not start a model call; setting ENABLE_STOP_REVIEW=1 is currently unsupported.
- Master switches SECURITY_GUIDANCE_DISABLE, ENABLE_SECURITY_REMINDER,
  ENABLE_PATTERN_RULES, ENABLE_CODE_SECURITY_REVIEW and ENABLE_COMMIT_REVIEW work
  through the hook process environment.

Codex delivers background reports at the next safe point or user turn; it cannot
reproduce CC's asyncRewake. Ending a session cancels unfinished native background
hooks. A failed/timed-out review is not marked reviewed. Each commit has a 240 s
review timeout and stale claims can be retried after 15 minutes.

## Vendored patterns

`vendor/patterns.py` is an unmodified copy of Anthropic's security-guidance 2.0.14
from `anthropics/claude-plugins-official/plugins/security-guidance/hooks/patterns.py`,
distributed under Apache-2.0 (`vendor/LICENSE`). Only the pure pattern data is
reused; this adapter and its orchestration are maintained here.
