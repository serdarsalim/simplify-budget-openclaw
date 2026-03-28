#!/usr/bin/env bash
# Updates an existing expense row by transaction ID.
# Use __KEEP__ to preserve the current value and __CLEAR__ to blank notes.
# Usage: update_expense.sh <transaction_id> <amount|__KEEP__> <category|__KEEP__> <description|__KEEP__> <YYYY-MM-DD|__KEEP__> [account|__KEEP__] [notes|__KEEP__|__CLEAR__]
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: update_expense.sh <transaction_id> <amount|__KEEP__> <category|__KEEP__> <description|__KEEP__> <YYYY-MM-DD|__KEEP__> [account|__KEEP__] [notes|__KEEP__|__CLEAR__]"
  exit 1
fi

TRANSACTION_ID="$1"
AMOUNT_INPUT="$2"
CATEGORY_INPUT="$3"
DESCRIPTION_INPUT="$4"
DATE_INPUT="$5"
ACCOUNT_INPUT="${6:-__KEEP__}"
NOTES_INPUT="${7:-__KEEP__}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/Users/slm/.openclaw/skills/simplify-budget/scripts/expense_lib.sh
source "$SCRIPT_DIR/expense_lib.sh"

ROW_JSON="$(find_expense_row_json "$TRANSACTION_ID")" || {
  echo "Error: transaction ID $TRANSACTION_ID not found in sheet"
  exit 1
}

CURRENT_AMOUNT="$(echo "$ROW_JSON" | jq -r '.amountNumber // .amount')"
CURRENT_CATEGORY="$(echo "$ROW_JSON" | jq -r '.categoryFormula // .category')"
CURRENT_DESCRIPTION="$(echo "$ROW_JSON" | jq -r '.description')"
CURRENT_DATE_ISO="$(echo "$ROW_JSON" | jq -r '.dateIso')"
CURRENT_LABEL="$(echo "$ROW_JSON" | jq -r '.label')"
CURRENT_NOTES="$(echo "$ROW_JSON" | jq -r '.notes')"
CURRENT_ACCOUNT="$(echo "$ROW_JSON" | jq -r '.account')"
SHEET_ROW="$(echo "$ROW_JSON" | jq -r '.rowNumber')"

AMOUNT="$CURRENT_AMOUNT"
if [ "$AMOUNT_INPUT" != "__KEEP__" ]; then
  AMOUNT="$AMOUNT_INPUT"
fi

CATEGORY="$CURRENT_CATEGORY"
if [ "$CATEGORY_INPUT" != "__KEEP__" ]; then
  CATEGORY="$(normalize_category_formula "$CATEGORY_INPUT")"
fi

DESCRIPTION="$CURRENT_DESCRIPTION"
if [ "$DESCRIPTION_INPUT" != "__KEEP__" ]; then
  DESCRIPTION="$DESCRIPTION_INPUT"
fi

DATE_ISO="$CURRENT_DATE_ISO"
if [ "$DATE_INPUT" != "__KEEP__" ]; then
  DATE_ISO="$DATE_INPUT"
fi

ACCOUNT="$CURRENT_ACCOUNT"
if [ "$ACCOUNT_INPUT" != "__KEEP__" ]; then
  ACCOUNT="$ACCOUNT_INPUT"
fi

NOTES="$CURRENT_NOTES"
if [ "$NOTES_INPUT" = "__CLEAR__" ]; then
  NOTES=""
elif [ "$NOTES_INPUT" != "__KEEP__" ]; then
  NOTES="$NOTES_INPUT"
fi

python3 - "$AMOUNT" "$DATE_ISO" <<'PY'
import sys
from datetime import datetime

try:
    float(sys.argv[1].strip())
except ValueError:
    raise SystemExit("Error: amount must be numeric")

datetime.strptime(sys.argv[2].strip(), "%Y-%m-%d")
PY

FORMATTED_DATE="$(iso_to_sheet_display "$DATE_ISO")"

BODY=$(jq -n \
  --arg tid "$TRANSACTION_ID" \
  --arg dt "$FORMATTED_DATE" \
  --argjson amt "$AMOUNT" \
  --arg cat "$CATEGORY" \
  --arg desc "$DESCRIPTION" \
  --arg label "$CURRENT_LABEL" \
  --arg notes "$NOTES" \
  --arg acc "$ACCOUNT" \
  '{"values": [[($tid), ($dt), ($amt), ($cat), ($desc), ($label), ($notes), ($acc)]]}')

curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21D${SHEET_ROW}%3AK${SHEET_ROW}?valueInputOption=RAW" \
  -d "$BODY" > /dev/null

CAT_BODY=$(jq -n --arg cat "$CATEGORY" '{"values": [[($cat)]]}')
curl -sf -X PUT \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Expenses%21G${SHEET_ROW}?valueInputOption=USER_ENTERED" \
  -d "$CAT_BODY" > /dev/null

update_master_timestamp

echo "Updated transaction ${TRANSACTION_ID} at row ${SHEET_ROW}"
echo "date=${FORMATTED_DATE}"
echo "notes=${NOTES}"
