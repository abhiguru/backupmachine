#!/bin/bash
# Slack notification helper for backup alerts
# Usage: ./notify-slack.sh "message" [success|failure|warning]

set -euo pipefail

# Webhook URL from environment or config file
WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
if [[ -z "$WEBHOOK_URL" && -f "$HOME/.secrets/slack_webhook" ]]; then
    WEBHOOK_URL=$(cat "$HOME/.secrets/slack_webhook")
fi

if [[ -z "$WEBHOOK_URL" ]]; then
    # Silently exit if no webhook configured
    exit 0
fi

HOSTNAME=$(hostname)
MESSAGE="${1:-Backup notification}"
STATUS="${2:-info}"

# Set color based on status
case "$STATUS" in
    success)
        COLOR="#36a64f"  # Green
        EMOJI=":white_check_mark:"
        ;;
    failure)
        COLOR="#dc3545"  # Red
        EMOJI=":x:"
        ;;
    warning)
        COLOR="#ffc107"  # Yellow
        EMOJI=":warning:"
        ;;
    *)
        COLOR="#6c757d"  # Gray
        EMOJI=":information_source:"
        ;;
esac

# Build JSON payload
PAYLOAD=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$COLOR",
            "blocks": [
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "$EMOJI *Backup Alert - $HOSTNAME*\n$MESSAGE"
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": "$(date '+%Y-%m-%d %H:%M:%S %Z')"
                        }
                    ]
                }
            ]
        }
    ]
}
EOF
)

# Send to Slack
curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$WEBHOOK_URL" > /dev/null 2>&1 || true
