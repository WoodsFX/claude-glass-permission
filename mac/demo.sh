#!/bin/bash
# Affiche la pop-up avec une fausse demande, sans passer par Claude Code.
BIN="$HOME/.claude/glass-permission/GlassPermission"
[[ -x "$BIN" ]] || BIN="$(dirname "$0")/GlassPermission"

echo '{
  "hook_event_name": "PermissionRequest",
  "cwd": "'"$PWD"'",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm install && npm run build",
    "description": "Installer les dépendances puis compiler le projet"
  }
}' | GLASS_TIMEOUT="${GLASS_TIMEOUT:-30}" "$BIN"

echo "(code de sortie : $?)"
