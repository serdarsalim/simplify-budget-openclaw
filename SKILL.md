---
name: simplify-budget
description: "Log expenses to Simplify Budget Google Sheet via exec. Workflow: 1) Run: bash ~/.openclaw/skills/simplify-budget/scripts/get_categories.sh (returns stableId<TAB>fullName lines). 2) Match description to closest category name (coffee/restaurant=Dining Out, supermarket=Groceries, uber/taxi=Transport). 3) Run: bash ~/.openclaw/skills/simplify-budget/scripts/write_expense.sh AMOUNT STABLEID \"DESCRIPTION\" YYYY-MM-DD (STABLEID is the number from column 1 of step 1, e.g. 4). Default date=today, account=Cash. GOOGLE_SA_FILE and SPREADSHEET_ID are pre-set. Confirm to user when done."
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
   - coffee, restaurants, takeaway, lunch, dinner → Dining Out
   - supermarket, groceries, food shopping → Groceries
   - uber, taxi, bus, metro, fuel → Transport
   - etc.
3. If the match is ambiguous, show the user the list and ask them to pick
4. Use the EXACT fullName string from the sheet (including emoji) when writing

## Workflows

### Log a new expense

When the user provides an expense (amount + description, with optional date/account):

1. Fetch the current active categories:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/get_categories.sh
   ```
   This returns lines of `stableId<TAB>fullName`. Show the fullNames to yourself for matching — do NOT show this raw output to the user.

2. Extract from the user's message:
   - `amount` — numeric (required). Strip currency symbols. If they say "5 bucks" use 5, "14 euros" use 14.
   - `description` — what they bought/paid for (required)
   - `category` — match to the fetched category list using the rules above; use the stableId (the number before the tab, e.g. `4`) NOT the fullName
   - `date` — in YYYY-MM-DD format. Default to today if not specified.
   - `account` — default to "Cash" if not specified

3. If you're not confident about the category match, confirm with the user before writing:
   "I'd put this under [Category]. Does that work?"

4. Write the expense:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/write_expense.sh "<amount>" "<stableId>" "<description>" "<YYYY-MM-DD>" "<account>"
   ```

5. Confirm to the user in a friendly, concise way:
   "✅ Logged [description] — [amount] under [category] on [date]"

6. Write to today's memory so corrections work later:
   ```
   LAST_EXPENSE: transaction_id=<id> | amount=<amount> | category=<category> | description=<description> | date=<YYYY-MM-DD> | account=<account>
   ```

### Fix or correct the last expense

When the user says things like "fix that", "that was wrong", "change the amount", "put that under X instead", "it was 4 not 5":

1. Search today's memory for the most recent `LAST_EXPENSE:` line to get the transaction ID and current values.

2. Show the user what was logged:
   "Last entry: [description] — [amount] under [category]. What needs changing?"

3. Ask for or infer the correction from their message (amount, category, description, date, or account).

4. For category corrections, fetch the category list again and match:
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/get_categories.sh
   ```

5. Run the update with the corrected values (keep unchanged fields as-is):
   ```
   bash /Users/slm/.openclaw/skills/simplify-budget/scripts/update_expense.sh "<transaction_id>" "<amount>" "<category_fullname>" "<description>" "<YYYY-MM-DD>" "<account>"
   ```

6. Confirm: "✅ Updated — now [description] — [amount] under [category]"

7. Update the memory entry with the corrected values.

### Undo / delete last expense
If the user asks to undo or delete an entry, explain that direct deletion isn't supported via the bot yet, and suggest they open Simplify Budget to remove it manually. Provide the transaction ID from memory so they can find it.

## Rules
- Never hardcode category names — always fetch them live
- Never show raw script output to the user — parse it and respond naturally
- Always confirm what you logged — the user should never have to guess if it worked
- If a script returns an error, tell the user clearly and do not silently retry
- Default date is always today in the user's local timezone
- Default account is always "Cash" unless the user specifies otherwise
- Amounts are always stored as plain numbers (no currency symbols)
- The 🤖 label on written rows identifies bot-added entries in the sheet
