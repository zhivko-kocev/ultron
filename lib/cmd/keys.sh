# shellcheck shell=bash
# ultron keys: the key cheat sheet (read-only).

cmd_keys() {
  grep -v -e '^#' -e '^[[:space:]]*$' "$ULTRON_ROOT/docs/keys.md" |
    fuzzel --dmenu --width 70 --lines 25 --prompt "keys ▸ " >/dev/null || true
}
