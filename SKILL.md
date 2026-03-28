---
name: simplify-budget
description: "Log, find, update, and delete expenses in the Simplify Budget Google Sheet. NEVER use sessions_spawn or ACP — ONLY use the exec tool to run bash scripts. Workflow: 1) exec get_categories.sh and match a live category. 2) exec write_expense.sh with amount, category, description, date, optional account, optional notes. 3) For edits/deletes, exec find_expenses.sh first, then mutate by transaction id with update_expense.sh or delete_expense.sh. Default date=today, account=Cash. Just do it."
version: 1.0.0
user-invocable: true
metadata:
  openclaw:
    primaryEnv: GOOGLE_SA_FILE
    emoji: "💸"
    requires:
      env:
        - GOOGLE_SA_FILE
        - SPREADSHEET_ID
      bins:
        - curl
        - jq
        - python3
        - openssl
---

# Simplify Budget Expense Tracker

> **CRITICAL EXECUTION RULE**: You MUST use the `exec` tool to run the bash scripts below. Do NOT call `sessions_spawn`. Do NOT create ACP sessions. These are standalone shell scripts — just run them with `exec` and the absolute path `/Users/slm/.openclaw/skills/simplify-budget/scripts/<script>.sh`.

## When to use
- The user mentions spending money, making a purchase, paying for something
- The user says things like "I spent X on Y", "X euros for coffee", "paid X for Y", "log X"
- The user asks to fix, correct, undo, or update the last expense entry
- The user asks to search for or identify an existing expense
- The user asks what they've spent or asks about their budget
- The user wants to add an expense to their budget tracker

## Configuration
Required environment variables:
- `GOOGLE_SA_FILE` — absolute path to the Google service account JSON file
- `SPREADSHEET_ID` — the Simplify Budget spreadsheet ID

## Category Matching Rules
The Simplify Budget sheet has a fixed list of user-defined categories (e.g. "Dining Out 🍽️", "Groceries 🛒", "Transport 🚗"). You MUST:
1. Always fetch the live category list before writing — never guess or hardcode categories
2. Match the user's description to the closest category using common sense:
   - coffee, restaurants, takeaway, lunch, dinner, pizza, fast food → Dining Out
   - supermarket, groceries, food shopping → Groceries
   - uber, taxi, bus, metro, fuel → Transport
   - etc.
3. Always make your best guess — never ask the user to pick a category
4. Construct the category as `=zategory{stableId}` (e.g. `=zategory4`) — never use the fullName string

## Workflows

### Log a new expense

When the user provides an expense (amount + description, with optional date/account/notes):

1. Fetch the current active categories:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/get_categories.sh
   ```
   This returns lines of `stableId<TAB>fullName`. Show the fullNames to yourself for matching — do NOT show this raw output to the user.

2. Extract from the user's message:
   - `amount` — numeric (required). Strip currency symbols. If they say "5 bucks" use 5, "14 euros" use 14.
   - `description` — what they bought/paid for (required)
   - `category` — match to the fetched category list; construct `=zategory{stableId}` (e.g. `=zategory4` for Dining Out, `=zategory2` for Transport)
   - `date` — in YYYY-MM-DD format. Default to today if not specified.
   - `account` — default to "Cash" if not specified
   - `notes` — optional supporting context. Keep the main purchase title in `description` and extra detail in `notes`

3. Write the expense:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/write_expense.sh "<amount>" "=zategory<stableId>" "<description>" "<YYYY-MM-DD>" "<account>" "<notes>"
   ```

4. Confirm to the user in a friendly, concise way:
   "✅ Logged [description] — [amount] under [category] on [date]"
   Include notes only when present.

### Find or inspect expenses

When the user wants to inspect, fix, or delete an expense, resolve it from the sheet first:

1. Build a short natural-language query from the user's message.
2. Search the sheet:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/find_expenses.sh "<query>" 10
   ```
3. Matching MUST consider both `description` and `notes`.
4. If one clear match exists, proceed. If multiple plausible matches exist, ask one short disambiguation question.

### Fix or correct the last expense

When the user says things like "fix that", "that was wrong", "change the amount", "put that under X instead", "it was 4 not 5":

1. Resolve the target expense from the sheet using `find_expenses.sh`. Do NOT trust chat memory as the source of truth.

2. Ask for or infer the correction from their message (amount, category, description, date, account, or notes).

3. For category corrections, fetch the category list again and match:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/get_categories.sh
   ```

4. Run the update with the corrected values. Use `__KEEP__` for unchanged fields and `__CLEAR__` to blank notes:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/update_expense.sh "<transaction_id>" "<amount_or___KEEP__>" "<=zategory<stableId>_or___KEEP__>" "<description_or___KEEP__>" "<YYYY-MM-DD_or___KEEP__>" "<account_or___KEEP__>" "<notes_or___KEEP___or___CLEAR__>"
   ```

5. Confirm: "✅ Updated — now [description] — [amount] under [category]"
   Include notes only when present.

### Undo / delete last expense
If the user asks to undo or delete an entry:

1. Resolve the target expense from the sheet using `find_expenses.sh`.
2. If there is one clear match, clear the row by transaction id:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/delete_expense.sh "<transaction_id>"
   ```
3. Confirm that the expense row was cleared.
4. Never delete sheet rows. Clear the existing row contents instead.

## Rules
- Never hardcode category names — always fetch them live
- Never show raw script output to the user — parse it and respond naturally
- Always confirm what you logged — the user should never have to guess if it worked
- If a script returns an error, tell the user clearly and do not silently retry
- Default date is always today in the user's local timezone
- Default account is always "Cash" unless the user specifies otherwise
- Amounts are always stored as plain numbers (no currency symbols)
- Notes are a first-class field. Search them, preserve them on update unless changed, and clear them on delete.
- For edits and deletes, the sheet is the source of truth. Resolve the target row from the sheet before mutating anything.
- The 🤖 label on written rows identifies bot-added entries in the sheet
