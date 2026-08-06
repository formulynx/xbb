#!/usr/bin/env bash
# detect-agent-workspace.sh — identify which coding-agent workspace/terminal
# tool this shell is running under, and print exactly one identifier to
# stdout. Read-only: checks env vars only, no side effects.
#
# Consulted by SKILL.md's Codex reviewer path at the Spawn step: look up the
# printed identifier in references/codex-launch.md for whether that specific
# environment needs any special handling before spawning codex.
#
# Currently only the cmux branches are active; the other-environment branches
# are commented out (kept for possible future reinstatement) and fall through
# to "other".
#
# Usage: bash scripts/detect-agent-workspace.sh   (no arguments)
set -u

# 1. cmux, tmux-backed (e.g. `cmux claude-teams`) — the one environment with
#    a confirmed, documented workaround (see references/codex-launch.md).
if [ -n "${CMUX_CLAUDE_TEAMS_CMUX_BIN:-}" ] || { [ -n "${CMUX_SOCKET_PATH:-}" ] && [ -n "${TMUX:-}" ]; }; then
  echo "cmux-tmux"
  exit 0
fi

# 2. cmux, native pane mode (no tmux underneath).
if [ -n "${CMUX_SOCKET_PATH:-}" ] && [ -z "${TMUX:-}" ]; then
  echo "cmux-native"
  exit 0
fi

# --- Non-cmux branches below are deactivated (commented out); everything
# --- falls through to "other". Re-enable individually if per-environment
# --- handling is ever needed again.

# # 3. Herdr pane.
# if [ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_PANE_ID:-}" ]; then
#   echo "herdr"
#   exit 0
# fi
#
# # 4. Plain tmux (none of the cmux/herdr conditions above matched).
# if [ -n "${TMUX:-}" ]; then
#   echo "tmux"
#   exit 0
# fi
#
# # 5. Conductor (parallel Claude Code session/workspace manager).
# if [ -n "${CONDUCTOR_IS_LOCAL:-}" ]; then
#   echo "conductor"
#   exit 0
# fi
#
# # 6. Superset (multi-agent desktop app; embedded terminal per agent pane).
# if [ -n "${SUPERSET_WORKSPACE_NAME:-}" ] || [ -n "${SUPERSET_ROOT_PATH:-}" ]; then
#   echo "superset"
#   exit 0
# fi
#
# # 7. Kitty. Does not reliably set $TERM_PROGRAM, so checked before the
# #    $TERM_PROGRAM-based branches below.
# if [ -n "${KITTY_WINDOW_ID:-}" ]; then
#   echo "kitty"
#   exit 0
# fi
#
# # 8. Alacritty. $TERM_PROGRAM support is unconfirmed, so use its IPC socket
# #    var instead (on by default on Unix).
# if [ -n "${ALACRITTY_SOCKET:-}" ]; then
#   echo "alacritty"
#   exit 0
# fi
#
# # 9. WezTerm.
# if [ -n "${WEZTERM_PANE:-}" ]; then
#   echo "wezterm"
#   exit 0
# fi
#
# # 10. Ghostty.
# if [ "${TERM_PROGRAM:-}" = "ghostty" ] || [ -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then
#   echo "ghostty"
#   exit 0
# fi
#
# # 11. Warp.
# if [ "${TERM_PROGRAM:-}" = "WarpTerminal" ]; then
#   echo "warp"
#   exit 0
# fi
#
# # 12. Zed.
# if [ "${TERM_PROGRAM:-}" = "zed" ]; then
#   echo "zed"
#   exit 0
# fi
#
# # 13. iTerm2.
# if [ "${TERM_PROGRAM:-}" = "iTerm.app" ]; then
#   echo "iterm2"
#   exit 0
# fi
#
# # 14. Apple Terminal.app.
# if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
#   echo "apple-terminal"
#   exit 0
# fi
#
# # 15. VS Code and every fork (Cursor, Windsurf, Antigravity, ...) all report
# #     the same $TERM_PROGRAM=vscode — indistinguishable by this var alone.
# if [ "${TERM_PROGRAM:-}" = "vscode" ]; then
#   echo "vscode-family"
#   exit 0
# fi

# 16. Not cmux — no special handling.
echo "other"
exit 0
