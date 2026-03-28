# Simplify Budget

This skill lets OpenClaw log and manage money in a Google Sheets budget tracker.

It supports:
- expenses: add, edit, delete, search
- income: add, edit, delete, search
- recurring items: add, edit, delete, inspect
- recurring questions like `what is due this month` or `when is CapCut due`
- automatic FX conversion into your base tracker currency
- receipt image logging

## Important

This skill only works with the Simplify Budget template, or a direct copy of it.

Template:
- [Simplify Budget Template](https://docs.google.com/spreadsheets/d/1fA8lHlDC8bZKVHSWSGEGkXHNmVylqF0Ef2imI_2jkZ8/edit?gid=524897973#gid=524897973)

If someone uses a different sheet layout, this skill will not work correctly.

## What The User Needs

To make this work, the user needs:
- a copy of the template above
- a Google service account JSON file
- the copied sheet shared with that service account
- these environment variables:
  - `GOOGLE_SA_FILE`
  - `SPREADSHEET_ID`
  - `TRACKER_CURRENCY`

Optional:
- `TRACKER_CURRENCY_SYMBOL`

## Install Summary

1. Copy the Google Sheet template
2. Share the copied sheet with the service account email
3. Install this skill in `~/.openclaw/skills/simplify-budget`
4. Set the required environment variables
5. Restart OpenClaw

For the exact steps, read [SETUP.md](./SETUP.md).

## Expected Sheet Structure

The copied template must contain these tabs:
- `Expenses`
- `Income`
- `Recurring`
- `Dontedit`

The skill depends on these template assumptions:
- `Expenses` ledger starts at row `5`
- `Income` ledger starts at row `5`
- `Recurring` ledger starts at row `6`
- active categories live in `Dontedit!L10:O39`
- expense and recurring expense categories use `=zategory<stableId>`
- recurring income uses literal `Income 💵`

## Best Experience

For the best OpenClaw and Telegram behavior, the user should also install the matching workspace wrappers.

The wrappers are what the bot tends to call directly for commands such as:
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

Receipts:
- `log this receipt`
- `add this grocery receipt to simplify budget`
- `what category would you use for this receipt`
- `split this receipt into fuel and snack`

## Receipt Behavior

By default, one receipt becomes one expense.

That means:
- use the final charged total, not every line item
- use the merchant name or a short summary as the description
- pick one best-fit category
- do not create multiple expenses from one receipt unless the user explicitly asks

Examples:
- a grocery receipt with 10 items should usually become one grocery expense
- a mixed receipt like fuel plus ice cream should still default to one expense unless the user asks to split it

## For Agents

Agent-specific operating details live in [AGENTS.md](./AGENTS.md).
