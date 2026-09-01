#!/usr/bin/env bash
#
# Post, or update in place, one stack's plan as a pull request comment.
#
# The masking below is best effort and explicitly NOT a security control. Per
# ADR 0012 the map — hostnames, cluster UUIDs — is accepted as public; this only
# avoids copying identifiers onto an indexed page. It redacts identifiers and
# never structure, so a reviewer can still see which rule changed. Anything that
# would be unsafe if these patterns matched nothing is already wrong.
set -euo pipefail

: "${STACK:?}" "${EXITCODE:?}" "${PR:?}" "${GITHUB_REPOSITORY:?}"

PLAN_FILE=${PLAN_FILE:-plan.txt}
MARKER="<!-- tofu-plan:${STACK} -->"
LIMIT=60000 # GitHub caps a comment at 65536 characters.

case "$EXITCODE" in
0) summary="No changes." ;;
1) summary="**Plan failed.**" ;;
2) summary="Changes to apply." ;;
*) summary="Unexpected exit code \`${EXITCODE}\`." ;;
esac

# CIDRs keep their prefix length, so the negative lookahead leaves declared
# network ranges — which are in the committed configuration anyway — readable.
masked=$(perl -pe '
  s{[A-Za-z0-9][A-Za-z0-9.-]*\.ondigitalocean\.com}{<host>}g;
  s{\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b}{<uuid>}g;
  s{\b(?:\d{1,3}\.){3}\d{1,3}\b(?!/)}{<ip>}g;
' "$PLAN_FILE")

if [ "${#masked}" -gt "$LIMIT" ]; then
  masked="${masked:0:$LIMIT}"$'\n\n... truncated. The full plan is in the workflow run.'
fi

{
  echo "$MARKER"
  echo "### \`terraform/${STACK}\` — ${summary}"
  echo
  echo '```terraform'
  echo "$masked"
  echo '```'
  echo
  echo "<sub>Identifiers masked best effort. Not a security boundary — see ADR 0012.</sub>"
} >body.md

id=$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" --paginate \
  --jq "map(select(.body | startswith(\"${MARKER}\"))) | .[0].id // empty")

if [ -n "$id" ]; then
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" -F body=@body.md >/dev/null
  echo "updated comment $id"
else
  gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" -F body=@body.md >/dev/null
  echo "created comment"
fi
