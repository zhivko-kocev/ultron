# shellcheck shell=bash
# ultron guide: the agent skill text (how an agent should behave on this PC), without its front matter.

cmd_guide() {
  local skill="$ULTRON_ROOT/home/skill/.agents/skills/ultron/SKILL.md"
  [[ -r "$skill" ]] || die "the guide is missing: $skill (is the ultron checkout complete?)"
  # Front matter = the lines between a leading --- and the next ---, plus the blank line after it.
  awk 'NR == 1 && $0 == "---" {fm = 1; next}
       fm && $0 == "---" {fm = 0; after = 1; next}
       fm {next}
       after && $0 == "" {after = 0; next}
       {after = 0; print}' "$skill"
}
