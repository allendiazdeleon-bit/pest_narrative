#!/usr/bin/env bash
# Drive the Massey Upsell Coach Agentforce agent via REST.
# Demonstrates the Headless 360 "API is the UI" thesis — no Slack, no browser.
#
# Prereqs:
#   1. Massey_Upsell_Coach agent built + activated in Agentforce Builder
#   2. Connected App configured for OAuth Client Credentials Flow
#      (scopes: api, refresh_token offline_access, chatbot_api, sfap_api)
#   3. scripts/.env populated (copy scripts/.env.example)
#
# Usage:
#   bash scripts/agent_curl.sh
#   bash scripts/agent_curl.sh "Pull the service portfolio for account 001KY00000LAblHYAT"

set -euo pipefail

ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

: "${MY_DOMAIN:?Set MY_DOMAIN to your org's my.salesforce.com host (no scheme).}"
: "${CONSUMER_KEY:?Set CONSUMER_KEY from the Connected App.}"
: "${CONSUMER_SECRET:?Set CONSUMER_SECRET from the Connected App.}"
: "${AGENT_ID:?Set AGENT_ID to the 18-char Id of the Massey_Upsell_Coach agent.}"

DEFAULT_MESSAGE="What services does Lisa Chen currently have? Her account id is 001KY00000LAblHYAT."
MESSAGE="${1:-$DEFAULT_MESSAGE}"
AGENT_API_BASE="https://api.salesforce.com/einstein/ai-agent/v1"

# ---- 1. Access token (OAuth 2.0 Client Credentials Flow) --------------------
echo "==> Requesting access token from $MY_DOMAIN"
token_response=$(curl -sS -X POST "https://${MY_DOMAIN}/services/oauth2/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials&client_id=${CONSUMER_KEY}&client_secret=${CONSUMER_SECRET}")

access_token=$(printf '%s' "$token_response" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))')
if [[ -z "$access_token" ]]; then
    echo "ERROR: failed to obtain access token. Response:" >&2
    echo "$token_response" >&2
    exit 1
fi
echo "    got token (${#access_token} chars)"

# ---- 2. Start session -------------------------------------------------------
session_key="cli-$(uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())')"
echo "==> Starting session (key=$session_key) against agent $AGENT_ID"

start_body=$(python3 -c "
import json, sys
print(json.dumps({
    'externalSessionKey': sys.argv[1],
    'instanceConfig': {'endpoint': 'https://' + sys.argv[2]},
    'featureSupport': 'Sync',
    'bypassUser': True
}))
" "$session_key" "$MY_DOMAIN")

start_response=$(curl -sS -X POST "${AGENT_API_BASE}/agents/${AGENT_ID}/sessions" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "$start_body")

session_id=$(printf '%s' "$start_response" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sessionId",""))')
if [[ -z "$session_id" ]]; then
    echo "ERROR: failed to start session. Response:" >&2
    echo "$start_response" >&2
    exit 1
fi
echo "    sessionId=$session_id"

# ---- 3. Send a synchronous message ------------------------------------------
echo "==> Sending: $MESSAGE"

message_body=$(python3 -c "
import json, sys
print(json.dumps({
    'message': {'sequenceId': 1, 'type': 'Text', 'text': sys.argv[1]},
    'variables': []
}))
" "$MESSAGE")

message_response=$(curl -sS -X POST "${AGENT_API_BASE}/sessions/${session_id}/messages?sync=true" \
    -H "Authorization: Bearer $access_token" \
    -H "Content-Type: application/json" \
    -d "$message_body")

echo "==> Raw agent response:"
echo "$message_response" | python3 -m json.tool

echo
echo "==> Extracted reply text(s):"
printf '%s' "$message_response" | python3 -c '
import sys, json
data = json.load(sys.stdin)
msgs = data.get("messages") or data.get("response", {}).get("messages") or []
if not msgs:
    print("(no messages field found in response — inspect raw JSON above)")
for m in msgs:
    text = m.get("message") or m.get("text") or ""
    role = m.get("type") or m.get("role") or ""
    if text:
        print(f"[{role}] {text}")
'

# ---- 4. End session ---------------------------------------------------------
echo
echo "==> Ending session"
curl -sS -X DELETE "${AGENT_API_BASE}/sessions/${session_id}" \
    -H "Authorization: Bearer $access_token" > /dev/null
echo "    done"
