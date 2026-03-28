#!/usr/bin/env bash
# Updates an existing expense row by transaction ID
# Usage: update_expense.sh <transaction_id> <amount> <category_fullname> <description> <YYYY-MM-DD> [account]
set -euo pipefail

TRANSACTION_ID="$1"
AMOUNT="$2"
CATEGORY="$3"
DESCRIPTION="$4"
DATE_INPUT="$5"
ACCOUNT="${6:-Cash}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN=$("$SCRIPT_DIR/get_token.sh")

# Read Expenses sheet from row 5 (header) onwards to find the transaction
DATA=$(curl -sf \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21D5%3AK")

# Find 0-based array index of the row matching the transaction ID
ROW_INDEX=$(echo "$DATA" | jq -r --arg tid "$TRANSACTION_ID" \
  '.values | to_entries | .[] | select(.value[0] == $tid) | .key')

if [ -z "$ROW_INDEX" ]; then
  echo "Error: transaction ID $TRANSACTION_ID not found in sheet"
  exit 1
fi

# Convert array index to actual sheet row number
# Range starts at D5, so index 0 = row 5, index N = row N+5
SHEET_ROW=$((ROW_INDEX + 5))

# Format date as "1-Jul-2025"
FORMATTED_DATE=$(python3 -c "
from datetime import datetime
d = datetime.strptime('$DATE_INPUT', '%Y-%m-%d')
print(str(d.day) + '-' + d.strftime('%b') + '-' + str(d.year))
")

# Build updated row (same column order D:K)
BODY=$(jq -n \
  --arg tid "$TRANSACTION_ID" \
  --arg dt "$FORMATTED_DATE" \
  --argjson amt "$AMOUNT" \
  --arg cat "$CATEGORY" \
  --arg desc "$DESCRIPTION" \
  --arg acc "$ACCOUNT" \
  '{"values": [[($tid), ($dt), ($amt), ($cat), ($desc), "🤖", "", ($acc)]]}')

# Update the specific row
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21D${SHEET_ROW}%3AK${SHEET_ROW}?valueInputOption=RAW" \
  -d "$BODY" > /dev/null

# Update masterData timestamp
ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
TS_BODY=$(jq -n --arg ts "$ISO_NOW" '{"values": [[($ts)]]}')
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Dontedit%21J9?valueInputOption=RAW" \
  -d "$TS_BODY" > /dev/null

echo "Updated transaction ${TRANSACTION_ID} at row ${SHEET_ROW}"
echo "date=${FORMATTED_DATE}"
