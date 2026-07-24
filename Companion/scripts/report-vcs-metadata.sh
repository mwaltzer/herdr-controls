#!/bin/sh
set -eu

HERDR_BIN=${HERDR_BIN:-herdr}
SOURCE_ID=controls_vcs

snapshot=$("$HERDR_BIN" api snapshot)

printf '%s' "$snapshot" | jq -r '
  .result.snapshot as $s
  | $s.workspaces[]
  | .workspace_id as $id
  | [
      $id,
      (
        [$s.panes[] | select(.workspace_id == $id) | .foreground_cwd // .cwd]
        | map(select(. != null and . != ""))
        | first // ""
      )
    ]
  | @tsv
' | while IFS="$(printf '\t')" read -r workspace_id cwd; do
  [ -n "$cwd" ] || continue

  provider=
  ref=
  change=
  dirty=false

  if jj_root=$(jj -R "$cwd" root 2>/dev/null); then
    provider=jj
    ref=$(jj -R "$jj_root" log --ignore-working-copy --no-graph -r @ \
      -T 'bookmarks.join(", ")' 2>/dev/null || true)
    [ -n "$ref" ] || ref=$(jj -R "$jj_root" log --ignore-working-copy --no-graph -r @ \
      -T 'commit_id.short(8)' 2>/dev/null || true)
    change=$(jj -R "$jj_root" log --ignore-working-copy --no-graph -r @ \
      -T 'change_id.shortest(8)' 2>/dev/null || true)
    empty=$(jj -R "$jj_root" log --ignore-working-copy --no-graph -r @ -T 'empty' 2>/dev/null || true)
    [ "$empty" = "true" ] || dirty=true
  elif git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
    provider=git
    ref=$(git -C "$git_root" symbolic-ref --quiet --short HEAD 2>/dev/null \
      || git -C "$git_root" rev-parse --short HEAD 2>/dev/null \
      || true)
    change=$(git -C "$git_root" rev-parse --short HEAD 2>/dev/null || true)
    [ -z "$(git -C "$git_root" status --porcelain=v1 2>/dev/null)" ] || dirty=true
  fi

  if [ -z "$provider" ]; then
    "$HERDR_BIN" workspace report-metadata "$workspace_id" --source "$SOURCE_ID" \
      --clear-token vcs_provider --clear-token vcs_ref \
      --clear-token vcs_change --clear-token vcs_dirty \
      >/dev/null
    continue
  fi

  set -- workspace report-metadata "$workspace_id" --source "$SOURCE_ID" \
    --token "vcs_provider=$provider" --token "vcs_dirty=$dirty"
  [ -z "$ref" ] || set -- "$@" --token "vcs_ref=$ref"
  [ -z "$change" ] || set -- "$@" --token "vcs_change=$change"
  "$HERDR_BIN" "$@" >/dev/null
done
