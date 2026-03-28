#!/usr/bin/env bash
# Writes a new expense row to the Expenses sheet
# Usage: write_expense.sh <amount|amount with currency> =zategory<stableId> <description> <YYYY-MM-DD> [account] [notes]
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: write_expense.sh <amount|amount with currency> =zategory<stableId> <description> <YYYY-MM-DD> [account] [notes]"
  exit 1
fi

AMOUNT="$1"
CATEGORY_RAW="$2"
DESCRIPTION="$3"
DATE_INPUT="$4"
ACCOUNT="${5:-Cash}"
NOTES="${6:-}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/Users/slm/.openclaw/skills/simplify-budget/scripts/expense_lib.sh
source "$SCRIPT_DIR/expense_lib.sh"

CATEGORY="$(normalize_category_formula "$CATEGORY_RAW")"

python3 - "$DATE_INPUT" <<'PY'
import sys
from datetime import datetime

date_input = sys.argv[1].strip()
datetime.strptime(date_input, "%Y-%m-%d")
PY

AMOUNT_JSON="$(resolve_amount_and_notes_json "$AMOUNT" "$NOTES")"
AMOUNT="$(echo "$AMOUNT_JSON" | jq -r '.amount')"
NOTES="$(echo "$AMOUNT_JSON" | jq -r '.notes')"

# Generate transaction ID matching SB_LIVE format: ex-{ms_timestamp}-{5_random_chars}
TIMESTAMP_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
RANDOM_SUFFIX=$(python3 -c "import random, string; print(''.join(random.choices(string.ascii_lowercase + string.digits, k=5)))")
TRANSACTION_ID="ex-${TIMESTAMP_MS}-${RANDOM_SUFFIX}"

# Format date as "1-Jul-2025" (SB_LIVE format)
FORMATTED_DATE="$(iso_to_sheet_display "$DATE_INPUT")"

# Build JSON body — columns D:K
# D=transactionId, E=date, F=amount, G=category, H=name, I=label, J=notes, K=account
BODY=$(jq -n \
  --arg tid "$TRANSACTION_ID" \
  --arg dt "$FORMATTED_DATE" \
  --argjson amt "$AMOUNT" \
  --arg cat "$CATEGORY" \
  --arg desc "$DESCRIPTION" \
  --arg notes "$NOTES" \
  --arg acc "$ACCOUNT" \
  '{"values": [[($tid), ($dt), ($amt), ($cat), ($desc), "🤖", ($notes), ($acc)]]}')

# Append to Expenses sheet (RAW so date stays as string, not converted to serial)
RESULT=$(curl -sf -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21D%3AK:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS" \
  -d "$BODY")

UPDATED_RANGE=$(echo "$RESULT" | jq -r '.updates.updatedRange // "unknown"')

# Patch category cell with USER_ENTERED so =zategoryN evaluates as a formula (not literal text)
ROW=$(echo "$UPDATED_RANGE" | grep -oE '[0-9]+$')
CAT_BODY=$(jq -n --arg cat "$CATEGORY" '{"values": [[($cat)]]}')
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21G${ROW}?valueInputOption=USER_ENTERED" \
  -d "$CAT_BODY" > /dev/null

update_master_timestamp

echo "transaction_id=${TRANSACTION_ID}"
echo "range=${UPDATED_RANGE}"
echo "date=${FORMATTED_DATE}"
