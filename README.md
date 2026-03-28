# Simplify Budget

Google Sheets backed budgeting skill for OpenClaw.

It supports:
- expenses: add, find, update, delete
- income: add, find, update, delete
- recurring items: add, find, update, delete
- recurring questions: due this month, next due date, subscriptions
- FX conversion into a configured base currency

This skill assumes the user also has the matching Simplify Budget Google Sheet template.

## What Is Included

- `SKILL.md`: agent behavior and command contract
- `scripts/`: shell scripts that talk to Google Sheets

This skill is designed to work together with the workspace wrapper repo at:
- `~/.openclaw/workspace`

The wrappers are what Telegram/OpenClaw tends to call directly.

## Required Sheet Structure

The shared Google Sheet template must include these tabs:
- `Expenses`
- `Income`
- `Recurring`
- `Dontedit`

Important template assumptions:
- `Expenses` ledger starts at row `5`, with real data starting from row `6`
- `Income` ledger starts at row `5`
- `Recurring` ledger starts at row `6`
- active categories live in `Dontedit!L10:O39`
- expense and recurring expense categories use `=zategory<stableId>` formulas
- recurring income uses literal `Income 💵`

## Required Environment

Set these:
- `GOOGLE_SA_FILE`
- `SPREADSHEET_ID`
- `TRACKER_CURRENCY`

Optional:
- `TRACKER_CURRENCY_SYMBOL`

Example:

```bash
export GOOGLE_SA_FILE="$HOME/.openclaw/sa.json"
export SPREADSHEET_ID="your_google_sheet_id"
export TRACKER_CURRENCY="EUR"
export TRACKER_CURRENCY_SYMBOL="€"
```

## How It Works

- expenses and recurring expenses resolve category from the live category table
- recurring expense categories are written as zategory formulas
- income is separate from expenses
- recurring rows are stored in `Recurring`, not in `Expenses` or `Income`
- deletes clear content from existing rows; they do not delete sheet rows
- amounts are stored in the configured base currency
- foreign currency inputs are converted through ECB rates and annotated in notes

## Runtime Expectations

For the best experience, install both:
- this skill repo in `~/.openclaw/skills/simplify-budget`
- the workspace wrapper repo in `~/.openclaw/workspace`

The Telegram/OpenClaw bot should be configured to use the workspace wrappers such as:
- `./write_expense.sh`
- `./write_income.sh`
- `./write_recurring.sh`
- `./find_recurring.sh`
- `./add_subscription.sh`

## Good Test Prompts

Expenses:
- `log a coffee expense for 10 euro`
- `change that coffee expense to 5 euro`
- `delete that coffee expense`

Income:
- `log income of 100 euro today named test income`
- `change that income account to Revolut`
- `delete that income`

Recurring:
- `add a monthly test subscription for 10 euro in simplify budget`
- `change that subscription category to business`
- `when is that subscription due`
- `delete that subscription`

## Sharing This With Someone Else

Give them:
- the Google Sheet template
- this skill repo
- the workspace wrapper repo
- service account JSON credentials
- the setup steps in `SETUP.md`

If they use the same template, setup is mostly configuration, not development.
