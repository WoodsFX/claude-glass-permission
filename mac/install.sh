#!/bin/bash
# Installe GlassPermission et l'ajoute aux hooks de Claude Code.
#   ./install.sh            → compile + installe + branche le hook
#   ./install.sh --uninstall → retire le hook et le binaire
set -euo pipefail

DEST="$HOME/.claude/glass-permission"
BIN="$DEST/GlassPermission"
SETTINGS="$HOME/.claude/settings.json"
HERE="$(cd "$(dirname "$0")" && pwd)"

[[ "$(uname)" == "Darwin" ]] || { echo "❌ Nécessite macOS."; exit 1; }

update_settings() { # $1 = add | remove
  mkdir -p "$(dirname "$SETTINGS")"
  [[ -f "$SETTINGS" ]] && cp "$SETTINGS" "$SETTINGS.bak"
  /usr/bin/python3 - "$SETTINGS" "$BIN" "$1" <<'PY'
import json, os, sys
path, binary, mode = sys.argv[1:]
data = json.load(open(path)) if os.path.exists(path) and os.path.getsize(path) else {}
hooks = data.setdefault("hooks", {})
groups = [g for g in hooks.get("PermissionRequest", [])
          if not any(h.get("command") == binary for h in g.get("hooks", []))]
if mode == "add":
    groups.append({"matcher": "*", "hooks": [{"type": "command", "command": binary, "timeout": 120}]})
if groups: hooks["PermissionRequest"] = groups
else: hooks.pop("PermissionRequest", None)
if not hooks: data.pop("hooks", None)
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
PY
}

if [[ "${1:-}" == "--uninstall" ]]; then
  update_settings remove
  rm -rf "$DEST"
  echo "✅ GlassPermission désinstallé (sauvegarde : $SETTINGS.bak)"
  exit 0
fi

command -v swiftc >/dev/null || { echo "❌ swiftc introuvable : lance  xcode-select --install"; exit 1; }

echo "🔨 Compilation…"
mkdir -p "$DEST"
swiftc -O -parse-as-library "$HERE/main.swift" -o "$BIN"

echo "🪝 Ajout du hook PermissionRequest dans $SETTINGS"
update_settings add

echo "✅ Installé. Redémarre Claude Code, puis teste avec :  ./demo.sh"
