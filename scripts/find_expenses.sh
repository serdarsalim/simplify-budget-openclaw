#!/usr/bin/env bash
# Finds expenses by matching query text across name, notes, category, account, amount, date, and transaction id.
# Usage: find_expenses.sh [query] [limit]
set -euo pipefail

QUERY="${1:-}"
LIMIT="${2:-10}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/Users/slm/.openclaw/skills/simplify-budget/scripts/expense_lib.sh
source "$SCRIPT_DIR/expense_lib.sh"

DATA="$(fetch_expenses_values)"

python3 -c '
import json
import sys
from datetime import datetime

query = sys.argv[1].strip().lower()
limit = int(sys.argv[2])
payload = json.load(sys.stdin)
rows = payload.get("values", [])

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

results = []
for idx, row in enumerate(rows):
    padded = row + [""] * (8 - len(row))
    if not padded[0]:
        continue
    record = {
        "rowNumber": idx + 5,
        "transactionId": padded[0],
        "dateDisplay": padded[1],
        "dateIso": to_iso(padded[1]),
        "amount": padded[2],
        "category": padded[3],
        "description": padded[4],
        "label": padded[5],
        "notes": padded[6],
        "account": padded[7],
    }
    haystack = " ".join(
        str(record[key] or "")
        for key in ("transactionId", "dateDisplay", "dateIso", "amount", "category", "description", "notes", "account")
    ).lower()
    if query and query not in haystack:
        continue
    results.append(record)

results = list(reversed(results))[:limit]
print(json.dumps(results, ensure_ascii=True))
' "$QUERY" "$LIMIT" <<<"$DATA"
