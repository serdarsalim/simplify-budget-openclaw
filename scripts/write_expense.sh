#!/usr/bin/env bash
# Writes a new expense row to the Expenses sheet
# Usage: write_expense.sh <amount> =category<stableId> <description> <YYYY-MM-DD> [account]
set -euo pipefail

AMOUNT="$1"
CATEGORY="$2"
DESCRIPTION="$3"
DATE_INPUT="$4"
ACCOUNT="${5:-Cash}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN=$("$SCRIPT_DIR/get_token.sh")

# Generate transaction ID matching SB_LIVE format: ex-{ms_timestamp}-{5_random_chars}
TIMESTAMP_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
RANDOM_SUFFIX=$(python3 -c "import random, string; print(''.join(random.choices(string.ascii_lowercase + string.digits, k=5)))")
TRANSACTION_ID="ex-${TIMESTAMP_MS}-${RANDOM_SUFFIX}"

# Format date as "1-Jul-2025" (SB_LIVE format)
FORMATTED_DATE=$(python3 -c "
from datetime import datetime
d = datetime.strptime('$DATE_INPUT', '%Y-%m-%d')
print(str(d.day) + '-' + d.strftime('%b') + '-' + str(d.year))
")

# Build JSON body — columns D:K
# D=transactionId, E=date, F=amount, G=category, H=name, I=label, J=notes, K=account
BODY=$(jq -n \
  --arg tid "$TRANSACTION_ID" \
  --arg dt "$FORMATTED_DATE" \
  --argjson amt "$AMOUNT" \
  --arg cat "$CATEGORY" \
  --arg desc "$DESCRIPTION" \
  --arg acc "$ACCOUNT" \
  '{"values": [[($tid), ($dt), ($amt), ($cat), ($desc), "🤖", "", ($acc)]]}')

# Append to Expenses sheet (RAW so date stays as string, not converted to serial)
RESULT=$(curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21D%3AK:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS" \
  -d "$BODY")

UPDATED_RANGE=$(echo "$RESULT" | jq -r '.updates.updatedRange // "unknown"')

# Update masterData timestamp in Dontedit J9 so SB_LIVE knows to re-sync
ISO_NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
TS_BODY=$(jq -n --arg ts "$ISO_NOW" '{"values": [[($ts)]]}')
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Dontedit%21J9?valueInputOption=RAW" \
  -d "$TS_BODY" > /dev/null

echo "transaction_id=${TRANSACTION_ID}"
echo "range=${UPDATED_RANGE}"
echo "date=${FORMATTED_DATE}"
