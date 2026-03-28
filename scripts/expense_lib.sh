#!/usr/bin/env bash
# Shared helpers for Simplify Budget expense scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN="$("$SCRIPT_DIR/get_token.sh")"
TRACKER_CURRENCY="${TRACKER_CURRENCY:-}"
TRACKER_CURRENCY_SYMBOL="${TRACKER_CURRENCY_SYMBOL:-}"

if [[ -z "$TRACKER_CURRENCY" ]]; then
  echo "Error: TRACKER_CURRENCY environment variable is required" >&2
  exit 1
fi

TRACKER_CURRENCY="$(printf '%s' "$TRACKER_CURRENCY" | tr '[:lower:]' '[:upper:]')"

if [[ -z "$TRACKER_CURRENCY_SYMBOL" ]]; then
  case "$TRACKER_CURRENCY" in
    EUR) TRACKER_CURRENCY_SYMBOL="€" ;;
    USD) TRACKER_CURRENCY_SYMBOL="$" ;;
    GBP) TRACKER_CURRENCY_SYMBOL="£" ;;
    JPY) TRACKER_CURRENCY_SYMBOL="¥" ;;
    MYR) TRACKER_CURRENCY_SYMBOL="RM" ;;
    SGD) TRACKER_CURRENCY_SYMBOL="S$" ;;
    AUD) TRACKER_CURRENCY_SYMBOL="A$" ;;
    CAD) TRACKER_CURRENCY_SYMBOL="C$" ;;
    *) TRACKER_CURRENCY_SYMBOL="$TRACKER_CURRENCY" ;;
  esac
fi

EXPENSES_RANGE_ENCODED="Expenses%21D5%3AK"
EXPENSES_RANGE_A1="Expenses!D5:K"
FX_CACHE_FILE="${TMPDIR:-/tmp}/simplify-budget-ecb-rates.json"

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

fetch_fx_rates_json() {
  local cache_ttl_seconds=43200
  local needs_refresh=1

  if [[ -s "$FX_CACHE_FILE" ]]; then
    if python3 - "$FX_CACHE_FILE" "$cache_ttl_seconds" <<'PY'
import os
import sys
import time

path = sys.argv[1]
ttl = int(sys.argv[2])
age = time.time() - os.path.getmtime(path)
raise SystemExit(0 if age < ttl else 1)
PY
    then
      needs_refresh=0
    fi
  fi

  if [[ "$needs_refresh" -eq 1 ]]; then
    local xml tmp_cache
    xml="$(curl -sfL "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")"
    tmp_cache="$(mktemp)"
    FX_XML="$xml" python3 - <<'PY' >"$tmp_cache"
import json
import os
import sys
import xml.etree.ElementTree as ET

xml_payload = os.environ["FX_XML"]
root = ET.fromstring(xml_payload)
rates = {"EUR": 1.0}
rate_date = ""

for elem in root.iter():
    currency = elem.attrib.get("currency")
    rate = elem.attrib.get("rate")
    if currency and rate:
        rates[currency.upper()] = float(rate)
    if not rate_date and "time" in elem.attrib:
        rate_date = elem.attrib["time"]

print(json.dumps({"base": "EUR", "date": rate_date, "rates": rates}, ensure_ascii=True))
PY
    mv "$tmp_cache" "$FX_CACHE_FILE"
  fi

  cat "$FX_CACHE_FILE"
}

resolve_amount_and_notes_json() {
  local raw_amount="$1"
  local existing_notes="${2:-}"
  local fx_json
  fx_json="$(fetch_fx_rates_json)"

  FX_JSON="$fx_json" python3 - "$raw_amount" "$existing_notes" "$TRACKER_CURRENCY" "$TRACKER_CURRENCY_SYMBOL" <<'PY'
import json
import os
import re
import sys
from decimal import Decimal, ROUND_HALF_UP

raw_amount = sys.argv[1].strip()
existing_notes = sys.argv[2]
tracker_currency = sys.argv[3].strip().upper()
tracker_symbol = sys.argv[4]
fx_payload = json.loads(os.environ["FX_JSON"])
rates = {code.upper(): Decimal(str(value)) for code, value in fx_payload.get("rates", {}).items()}
rate_date = fx_payload.get("date", "")

if tracker_currency not in rates:
    raise SystemExit(f"Error: tracker currency {tracker_currency} is not supported by the FX feed")

SPECIAL_PREFIXES = {
    "HK$": "HKD",
    "S$": "SGD",
    "A$": "AUD",
    "C$": "CAD",
    "NZ$": "NZD",
    "R$": "BRL",
    "RM": "MYR",
}

SPECIAL_SUFFIXES = {
    "HK$": "HKD",
    "S$": "SGD",
    "A$": "AUD",
    "C$": "CAD",
    "NZ$": "NZD",
}

SYMBOL_MAP = {
    "€": "EUR",
    "£": "GBP",
    "¥": "JPY",
    "₹": "INR",
    "₩": "KRW",
    "₱": "PHP",
    "฿": "THB",
    "$": "USD",
}

WORD_ALIASES = {
    "EUR": ["eur", "euro", "euros"],
    "USD": ["usd", "us dollar", "us dollars", "dollar", "dollars"],
    "GBP": ["gbp", "pound", "pounds", "british pound", "sterling"],
    "MYR": ["myr", "ringgit", "malaysian ringgit"],
    "SGD": ["sgd", "singapore dollar", "singapore dollars"],
    "AUD": ["aud", "australian dollar", "australian dollars"],
    "CAD": ["cad", "canadian dollar", "canadian dollars"],
    "NZD": ["nzd", "new zealand dollar", "new zealand dollars"],
    "JPY": ["jpy", "yen", "japanese yen"],
    "CNY": ["cny", "rmb", "yuan", "renminbi"],
    "HKD": ["hkd", "hong kong dollar", "hong kong dollars"],
    "THB": ["thb", "baht", "thai baht"],
    "IDR": ["idr", "rupiah", "indonesian rupiah"],
    "INR": ["inr", "rupee", "rupees", "indian rupee"],
    "CHF": ["chf", "swiss franc", "swiss francs", "franc", "francs"],
    "TRY": ["try", "turkish lira", "lira"],
}

def clean_auto_fx_notes(text):
    lines = [line for line in text.splitlines() if not line.startswith("[auto-fx] ")]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(lines)

def append_note(base, extra):
    base = base.strip()
    if not extra:
        return base
    return f"{base}\n{extra}".strip() if base else extra

def format_decimal(value):
    text = format(value.normalize(), "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text

def normalize_number(raw):
    raw = raw.strip()
    if "," in raw and "." in raw:
        raw = raw.replace(",", "")
    elif "," in raw:
        raw = raw.replace(",", ".")
    return Decimal(raw)

def detect_currency(text):
    compact = text.strip()
    lowered = compact.lower()

    for marker, code in SPECIAL_PREFIXES.items():
        if compact.startswith(marker):
            return code
    for marker, code in SPECIAL_SUFFIXES.items():
        if compact.endswith(marker):
            return code

    for symbol, code in SYMBOL_MAP.items():
        if compact.startswith(symbol) or compact.endswith(symbol):
            return code

    padded = f" {lowered} "
    for code, aliases in WORD_ALIASES.items():
        for alias in aliases:
            if f" {alias.lower()} " in padded:
                return code

    token_codes = set(re.findall(r"\b[A-Za-z]{3}\b", compact.upper()))
    for code in token_codes:
        if code in rates:
            return code

    return tracker_currency

number_match = re.search(r"[-+]?\d[\d,]*(?:\.\d+)?|[-+]?\d+(?:,\d+)?", raw_amount)
if not number_match:
    raise SystemExit("Error: amount must include a numeric value")

source_currency = detect_currency(raw_amount)
if source_currency not in rates:
    raise SystemExit(f"Error: unsupported currency {source_currency}")

source_amount = normalize_number(number_match.group(0))
if source_currency == "EUR":
    eur_amount = source_amount
else:
    eur_amount = source_amount / rates[source_currency]

if tracker_currency == "EUR":
    tracker_amount = eur_amount
else:
    tracker_amount = eur_amount * rates[tracker_currency]

tracker_amount = tracker_amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
clean_notes = clean_auto_fx_notes(existing_notes)

converted = source_currency != tracker_currency
if converted:
    per_unit = (tracker_amount / source_amount).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP) if source_amount else Decimal("0")
    fx_note = (
        f"[auto-fx] original={source_currency} {format_decimal(source_amount)}; "
        f"converted={tracker_currency} {format_decimal(tracker_amount)}; "
        f"rate=1 {source_currency} = {tracker_currency} {format_decimal(per_unit)}; "
        f"source=ECB {rate_date}"
    )
    clean_notes = append_note(clean_notes, fx_note)

amount_str = format_decimal(tracker_amount)

print(json.dumps({
    "amount": amount_str,
    "notes": clean_notes,
    "trackerCurrency": tracker_currency,
    "trackerCurrencySymbol": tracker_symbol,
    "sourceCurrency": source_currency,
    "converted": converted,
    "rateDate": rate_date,
}, ensure_ascii=True))
PY
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
