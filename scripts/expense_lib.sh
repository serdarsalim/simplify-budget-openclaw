#!/usr/bin/env bash
# Shared helpers for Simplify Budget expense scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN="$("$SCRIPT_DIR/get_token.sh")"

EXPENSES_RANGE_ENCODED="Expenses%21D5%3AK"
EXPENSES_RANGE_A1="Expenses!D5:K"

fetch_expenses_values() {
  curl -sf \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${EXPENSES_RANGE_ENCODED}"
}

sheet_display_to_iso() {
  python3 - "$1" <<'PY'
import sys
from datetime import datetime

raw = sys.argv[1].strip()
if not raw:
    print("")
    raise SystemExit(0)

for fmt in ("%d-%b-%Y", "%m/%d/%Y", "%-d-%b-%Y", "%-m/%-d/%Y"):
    try:
        print(datetime.strptime(raw, fmt).strftime("%Y-%m-%d"))
        raise SystemExit(0)
    except ValueError:
        pass

print(raw)
PY
}

iso_to_sheet_display() {
  python3 - "$1" <<'PY'
import sys
from datetime import datetime

raw = sys.argv[1].strip()
dt = datetime.strptime(raw, "%Y-%m-%d")
print(f"{dt.day}-{dt.strftime('%b')}-{dt.year}")
PY
}

update_master_timestamp() {
  local iso_now ts_body
  iso_now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  ts_body=$(jq -n --arg ts "$iso_now" '{"values": [[($ts)]]}')
  curl -sf -X PUT \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/Dontedit%21J9?valueInputOption=RAW" \
    -d "$ts_body" > /dev/null
}

normalize_category_formula() {
  local category="$1"
  if [[ "$category" =~ ^[0-9]+$ ]]; then
    printf '=zategory%s\n' "$category"
  else
    printf '%s\n' "$category"
  fi
}

find_expense_row_json() {
  local transaction_id="$1"
  local data
  data="$(curl -sf \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}?ranges=Expenses%21D5%3AK&includeGridData=true&fields=sheets(data(rowData(values(formattedValue,userEnteredValue,effectiveValue))))")"
  python3 -c '
import json
import sys
from datetime import datetime

transaction_id = sys.argv[1]
payload = json.load(sys.stdin)
row_data = (
    payload.get("sheets", [{}])[0]
    .get("data", [{}])[0]
    .get("rowData", [])
)

def string_from_cell(cell):
    if "formattedValue" in cell:
        return cell["formattedValue"]
    user = cell.get("userEnteredValue", {})
    if "stringValue" in user:
        return user["stringValue"]
    if "formulaValue" in user:
        return user["formulaValue"]
    effective = cell.get("effectiveValue", {})
    if "numberValue" in effective:
        number = effective["numberValue"]
        return str(int(number) if float(number).is_integer() else number)
    return ""

def to_iso(raw):
    raw = (raw or "").strip()
    if not raw:
        return ""
    for fmt in ("%d-%b-%Y", "%m/%d/%Y"):
        try:
            return datetime.strptime(raw, fmt).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return raw

for idx, row in enumerate(row_data):
    cells = row.get("values", [])
    padded = cells + [{}] * (8 - len(cells))
    transaction = string_from_cell(padded[0])
    if transaction != transaction_id:
        continue
    amount_effective = padded[2].get("effectiveValue", {}).get("numberValue")
    amount_number = "" if amount_effective is None else str(int(amount_effective) if float(amount_effective).is_integer() else amount_effective)
    category_formula = padded[3].get("userEnteredValue", {}).get("formulaValue", "")
    result = {
        "rowNumber": idx + 5,
        "transactionId": transaction,
        "dateDisplay": string_from_cell(padded[1]),
        "dateIso": to_iso(string_from_cell(padded[1])),
        "amount": string_from_cell(padded[2]),
        "amountNumber": amount_number,
        "category": string_from_cell(padded[3]),
        "categoryFormula": category_formula,
        "description": string_from_cell(padded[4]),
        "label": string_from_cell(padded[5]),
        "notes": string_from_cell(padded[6]),
        "account": string_from_cell(padded[7]),
    }
    print(json.dumps(result))
    raise SystemExit(0)

raise SystemExit(1)
' "$transaction_id" <<<"$data"
}
