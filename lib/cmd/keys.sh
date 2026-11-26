# shellcheck shell=bash
# ultron keys: the key cheat sheet (read-only), read from the sway config and your overrides.

# Prints "KEY — COMMAND · SECTION" for every bindsym in FILE…; a later file's binding of the same key wins.
# Sections are comment lines after a blank line ("# Apps" → Apps); bindings in files under YOURS_DIR are "yours".
_keys_list() {
  awk -v yours="$ULTRON_CONF_DIR/sway/" '
    function nice_key(k,   n, p, i, out, s) {
      n = split(k, p, "+")
      for (i = 1; i <= n; i++) {
        s = p[i]
        if (s == "Mod4") s = "Super"
        else if (s == "Mod1") s = "Alt"
        else if (s == "Control") s = "Ctrl"
        else s = toupper(substr(s, 1, 1)) substr(s, 2)
        out = out (i > 1 ? "+" : "") s
      }
      return out
    }
    function expand(s,   out, name) {
      out = ""
      while (match(s, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
        name = substr(s, RSTART, RLENGTH)
        out = out substr(s, 1, RSTART - 1) ((name in vars) ? vars[name] : name)
        s = substr(s, RSTART + RLENGTH)
      }
      return out s
    }
    FNR == 1 { prev_blank = 1; section = (index(FILENAME, yours) == 1) ? "yours" : "" }
    /^[ \t]*$/ { prev_blank = 1; next }
    /^#/ {
      if (prev_blank && section != "yours") {
        s = substr($0, 2); sub(/^ +/, "", s); sub(/[.(].*$/, "", s); sub(/ +$/, "", s); section = s
      }
      prev_blank = 0; next
    }
    { prev_blank = 0 }
    $1 == "set" && $2 ~ /^\$/ { v = $2; s = $0; sub(/^[ \t]*set[ \t]+[^ \t]+[ \t]+/, "", s); vars[v] = s; next }
    $1 == "bindsym" {
      i = 2
      while ($i ~ /^--/) i++
      key = nice_key(expand($i)); cmd = ""
      for (j = i + 1; j <= NF; j++) cmd = cmd (cmd == "" ? "" : " ") $j
      cmd = expand(cmd)
      if (cmd ~ /^exec /) cmd = substr(cmd, 6)
      gsub(/; exec /, "; ", cmd)
      if (!(key in line)) order[++n] = key
      line[key] = key " — " cmd (section == "" ? "" : " · " section)
    }
    END { for (i = 1; i <= n; i++) print line[order[i]] }
  ' "$@"
}

cmd_keys() {
  local files=("$ULTRON_ROOT/home/sway/.config/sway/config") f
  for f in "$ULTRON_CONF_DIR"/sway/*.conf; do [[ -f "$f" ]] && files+=("$f"); done
  _keys_list "${files[@]}" |
    fuzzel --dmenu --width 90 --lines 25 --prompt "keys ▸ " >/dev/null || true
}
