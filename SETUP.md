# Setup

This is the shortest reliable setup for a new user.

## 1. Install The Skill

Put this repo at:

```bash
~/.openclaw/skills/simplify-budget
```

## 2. Install The Workspace Wrappers

Also install the matching workspace wrapper repo at:

```bash
~/.openclaw/workspace
```

This is required for Telegram/OpenClaw command routing.

## 3. Copy The Google Sheet Template

Create a copy of the Simplify Budget template in Google Sheets.

The copied sheet must include:
- `Expenses`
- `Income`
- `Recurring`
- `Dontedit`

Do not change the expected column layout unless you also update the scripts.

## 4. Create Or Reuse A Service Account

Create a Google Cloud service account with Sheets access, then download the JSON key.

Put it somewhere local, for example:

```bash
~/.openclaw/sa.json
```

## 5. Share The Sheet With The Service Account

In Google Sheets:
- open the copied sheet
- share it with the service account email from the JSON key
- grant editor access

If you skip this, all writes will fail.

## 6. Set Environment Variables

Add these to your OpenClaw config or shell environment:

```bash
export GOOGLE_SA_FILE="$HOME/.openclaw/sa.json"
export SPREADSHEET_ID="your_google_sheet_id"
export TRACKER_CURRENCY="EUR"
export TRACKER_CURRENCY_SYMBOL="€"
```

Minimum required:
- `GOOGLE_SA_FILE`
- `SPREADSHEET_ID`
- `TRACKER_CURRENCY`

## 7. Verify The Category Table

The sheet template must have active categories in:

```text
Dontedit!L10:O39
```

The scripts read this table directly.

## 8. Restart OpenClaw

```bash
openclaw daemon restart
```

If Telegram is already running, restart after changing config so it picks up the latest skill and wrappers.

## 9. Smoke Test Locally

Expense:

```bash
OPENCLAW_HOME="$HOME/.openclaw" bash "$HOME/.openclaw/workspace/write_expense.sh" \
  --amount 10 \
  --category 4 \
  --description "setup test" \
  --date 2026-03-28 \
  --account Cash
```

Recurring:

```bash
OPENCLAW_HOME="$HOME/.openclaw" bash "$HOME/.openclaw/workspace/write_recurring.sh" \
  --start-date 2026-03-28 \
  --name "setup recurring test" \
  --category "Business 💻️" \
  --type expense \
  --frequency Monthly \
  --amount 10 \
  --account Cash
```

Delete test rows afterward.

## 10. Telegram Setup

If they want Telegram:
- configure the bot token in OpenClaw
- set Telegram allowlist or pairing
- make sure the Telegram direct prompt points to the Simplify Budget skill and workspace wrappers

This repo does not contain the user’s private Telegram token or local OpenClaw config.

## Common Failures

`scripts are missing`
- workspace wrappers were not installed

`permission denied`
- shell script is not executable

`transaction not found`
- the bot guessed the wrong row; use a more specific query

`category not found`
- the template category table is missing or different

`writes go to wrong rows`
- the sheet template layout does not match the expected ledger layout

`Google Sheets auth failure`
- service account is not shared on the sheet

## Expected Behavior

- expenses reuse the first empty row after the expense header block
- income reuses the first empty row after the income header block
- recurring reuses the first empty row after the recurring header block
- recurring expense categories are stored as zategory formulas
- recurring income category is stored as `Income 💵`
