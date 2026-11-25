#!/bin/sh
# Prints {"forgejo_jwt"} for forgejo-variables.tf's Forgejo sign-in: this Forgejo Actions
# job's own short-lived token for the audience of nelson's authorized integration for its
# event, which Forgejo takes as a sign-in limited to that integration's scope. OpenTofu's
# query gives the two integrations' audiences. Outside a job it is empty, and the Forgejo
# variables can't be planned there. The same pattern as nelsong6/openbao's
# tofu/forgejo-job-token.sh.
set -eu
query=$(cat)
field() { printf '%s' "$query" | sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p"; }
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  printf '{"forgejo_jwt":""}\n'
  exit 0
fi
case ${GITHUB_EVENT_NAME:-} in
  pull_request) aud=$(field forgejo_plan_audience) ;;
  *) aud=$(field forgejo_apply_audience) ;;
esac
jwt=$(curl -fsS --max-time 30 -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$aud" | sed -n 's/.*"value": *"\([^"]*\)".*/\1/p')
[ -n "$jwt" ] || { echo "Forgejo gave this job no token for audience $aud" >&2; exit 1; }
printf '{"forgejo_jwt":"%s"}\n' "$jwt"
