#!/usr/bin/env bash
set -euo pipefail

# LoopHarness v1.4 installer
# Optional overrides: CLAUDE_HH_DIR=/path HARNESS_BIN_DIR=/path
INSTALL_DIR="${CLAUDE_HH_DIR:-${HOME}/.loopharness}"
BIN_DIR="${HARNESS_BIN_DIR:-${HOME}/.local/bin}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing LoopHarness v1.4 to ${INSTALL_DIR} ..."

mkdir -p "${INSTALL_DIR}/claude_hh" "${INSTALL_DIR}/hooks" \
  "${INSTALL_DIR}/prompts" "${INSTALL_DIR}/hermes" "${BIN_DIR}"
cp -R "${REPO_DIR}/claude_hh/." "${INSTALL_DIR}/claude_hh/"
cp -R "${REPO_DIR}/hooks/." "${INSTALL_DIR}/hooks/"
cp -R "${REPO_DIR}/prompts/." "${INSTALL_DIR}/prompts/"
cp -R "${REPO_DIR}/hermes/." "${INSTALL_DIR}/hermes/"
find "${INSTALL_DIR}" -type d -name __pycache__ -prune -exec rm -rf {} +
find "${INSTALL_DIR}" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf 'PYTHONPATH=%q exec python3 -m claude_hh.pipeline "$@"\n' "${INSTALL_DIR}"
} > "${BIN_DIR}/harness"
chmod 755 "${BIN_DIR}/harness"

PATH_MARKER="# LoopHarness PATH"
PATH_LINE="export PATH=\"${BIN_DIR}:\$PATH\""

retire_legacy_harness_alias() {
  local rc="$1"
  local temp_rc="${rc}.loopharness.$$"

  cp -p "${rc}" "${temp_rc}"
  awk '
    /^[[:space:]]*alias[[:space:]]+harness=/ &&
      index($0, "python3 -m claude_hh.pipeline") { next }
    { print }
  ' "${rc}" > "${temp_rc}"

  if cmp -s "${rc}" "${temp_rc}"; then
    rm -f "${temp_rc}"
    return
  fi

  mv "${temp_rc}" "${rc}"
  echo "  Retired legacy harness alias in ${rc}"
}

add_path() {
  local rc="$1"
  if grep -Fq "${PATH_MARKER}" "${rc}" 2>/dev/null; then
    echo "  (PATH already configured in ${rc}, skipping)"
    return
  fi
  printf '\n%s\n%s\n' "${PATH_MARKER}" "${PATH_LINE}" >> "${rc}"
  echo "  Added PATH to ${rc}"
}

for shell_rc in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
  if [[ -f "${shell_rc}" ]]; then
    retire_legacy_harness_alias "${shell_rc}"
    add_path "${shell_rc}"
  fi
done

# --- Cross-agent global memory (~/.agent-memory) ---
# One-time, idempotent: point every known agent's user-level config at the
# global memory store so any agent in any project reads/sediments it.
MEMORY_MARKER_BEGIN="<!-- loopharness:global-memory v1 -->"

add_global_memory_pointer() {
  local cfg="$1"
  if [[ -f "${cfg}" ]] && grep -Fq "${MEMORY_MARKER_BEGIN}" "${cfg}" 2>/dev/null; then
    echo "  (global memory pointer already in ${cfg}, skipping)"
    return
  fi
  cat >> "${cfg}" << 'POINTER_EOF'

<!-- loopharness:global-memory v1 -->

# Cross-agent global memory (LoopHarness .agent-memory)

- **Before starting work in any project**: read `~/.agent-memory/README.md`
  and follow its read order (profile → projects → decisions/learned → inbox).
  If the project contains its own `.agent-memory/`, the project copy wins.
- **Before ending a work session** (meaningful feature / pitfall / decision):
  1. Append progress and next steps to `~/.agent-memory/projects/<project>.md`
  2. Append durable lessons to `~/.agent-memory/decisions/learned.md`
     (or run `harness learn "..."`)
  3. Park undecided items in `~/.agent-memory/inbox.md`
- **Never** write secrets, tokens, or real user data into the memory store.

<!-- /loopharness:global-memory -->
POINTER_EOF
  echo "  Added global memory pointer to ${cfg}"
}

# Known agent user-level configs. Agents that auto-read project AGENTS.md
# (Codex, Qoder, Trae, ...) are also covered per-project by `harness init`,
# which writes the same protocol into AGENTS.md.
if [[ -d "${HOME}/.claude" ]]; then
  add_global_memory_pointer "${HOME}/.claude/CLAUDE.md"
fi
if [[ -d "${HOME}/.codex" ]]; then
  add_global_memory_pointer "${HOME}/.codex/AGENTS.md"
fi

# Initialize the global memory store (idempotent, never overwrites content).
if (cd "${HOME}" && "${BIN_DIR}/harness" memory-init >/dev/null 2>&1); then
  echo "  Global memory store ready at ${HOME}/.agent-memory"
else
  echo "  (global memory init skipped; run 'harness memory-init' later)"
fi

echo ""
echo "LoopHarness v1.4 installed."
echo "Executable: ${BIN_DIR}/harness"
echo "Global memory: ${HOME}/.agent-memory (agents auto-read after this install)"
echo "Run: harness -h"
