# Setup

This is the shortest reliable setup for a real user.

## Before You Start

You must use this exact template, or a direct copy of it:
- [Simplify Budget Template](https://docs.google.com/spreadsheets/d/1fA8lHlDC8bZKVHSWSGEGkXHNmVylqF0Ef2imI_2jkZ8/edit?gid=524897973#gid=524897973)

If you use a different budget sheet, this skill will not work.

## 1. Copy The Template

Make your own copy of the template in Google Sheets.

Your copy must still contain:
- `Expenses`
- `Income`
- `Recurring`
- `Dontedit`

Do not change the expected column layout unless you also change the scripts.

## 2. Install The Skill

Put this skill at:

```bash
~/.openclaw/skills/simplify-budget
```

## 3. Install The Workspace Wrappers

For the best OpenClaw and Telegram behavior, also install the matching workspace wrappers at:

```bash
~/.openclaw/workspace
```

Without the wrappers, the skill can still exist, but Telegram/OpenClaw command routing will be much less reliable.

## 4. Create Or Reuse A Google Service Account

Create a Google Cloud service account with Google Sheets access and download the JSON key.

A common location is:

```bash
~/.openclaw/sa.json
```

## 5. Share The Sheet With The Service Account

Open your copied Google Sheet and share it with the service account email from the JSON key.

Give it editor access.

If you skip this, reads and writes will fail.

## 6. Set Environment Variables

Add these to your OpenClaw config or shell environment:

```bash
export GOOGLE_SA_FILE="$HOME/.openclaw/sa.json"
export SPREADSHEET_ID="your_google_sheet_id"
export TRACKER_CURRENCY="EUR"
export TRACKER_CURRENCY_SYMBOL="€"
```

Required:
- `GOOGLE_SA_FILE`
- `SPREADSHEET_ID`
- `TRACKER_CURRENCY`

Optional:
- `TRACKER_CURRENCY_SYMBOL`

## 7. Verify The Template Assumptions

The skill expects:
- active categories in `Dontedit!L10:O39`
- `Expenses` ledger starts at row `5`
- `Income` ledger starts at row `5`
- `Recurring` ledger starts at row `6`
- expense and recurring expense categories use `=zategory<stableId>`
- recurring income uses `Income 💵`

## 8. Restart OpenClaw

```bash
openclaw daemon restart
```

If Telegram is already connected, restart after config changes so it picks up the new environment and wrappers.

## 9. Smoke Test

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

Delete the test rows afterward.

## 10. Telegram

If the user wants Telegram access too:
- configure the Telegram bot token in OpenClaw
- use pairing or allowlist
- make sure the Telegram prompt routes budget requests to the Simplify Budget wrappers

This repo does not contain any private Telegram token or local OpenClaw config.

## Common Failures

`scripts are missing`
- workspace wrappers were not installed

`category not found`
- the user is not using the real template, or the category table changed

`writes go to wrong rows`
- the user changed the template layout

`Google Sheets auth failure`
- the sheet was not shared with the service account

`transaction not found`
- the bot guessed the wrong row; use a more specific query
