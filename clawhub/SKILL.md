---
name: simplify-budget
description: "Log, find, update, and delete expenses and income in the Simplify Budget Google Sheet, and answer read-only recurring schedule questions. NEVER use sessions_spawn or ACP — ONLY use the exec tool to run bash scripts. Expenses use live categories. Income uses name, account, source, and notes. For edits/deletes, find rows first, then mutate by transaction id. Amounts are always stored in the configured tracker currency. Just do it."
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
        - TRACKER_CURRENCY
      bins:
        - curl
        - jq
        - python3
        - openssl
---

# Simplify Budget Tracker

> **CRITICAL EXECUTION RULE**: You MUST use the `exec` tool to run the bash scripts below. Do NOT call `sessions_spawn`. Do NOT create ACP sessions. These are standalone shell scripts. Resolve script paths relative to this skill directory and run the resulting absolute path with `exec`.

## When to use
- The user mentions spending money, making a purchase, paying for something
- The user says things like "I spent X on Y", "X euros for coffee", "paid X for Y", "log X"
- The user asks to fix, correct, undo, or update the last expense entry
- The user asks to search for or identify an existing expense
- The user asks what they've spent or asks about their budget
- The user wants to add an expense to their budget tracker
- The user wants to log income, salary, withdrawal, remittance, sale proceeds, or any other incoming money
- The user asks what recurring payments are due this month, when something recurring is due, or what subscriptions are upcoming

## Configuration
Required environment variables:
- `GOOGLE_SA_FILE` — absolute path to the Google service account JSON file
- `SPREADSHEET_ID` — the Simplify Budget spreadsheet ID
- `TRACKER_CURRENCY` — the base currency code for the tracker (for example `EUR`)

Optional environment variables:
- `TRACKER_CURRENCY_SYMBOL` — display symbol for the base currency (for example `€`)

## Currency Rules
- The configured `TRACKER_CURRENCY` is the system of record for stored amounts.
- If the user gives an amount without a currency, assume it is already in `TRACKER_CURRENCY`.
- If the user gives an explicit foreign currency, keep that currency in the amount argument you pass to the script, for example `"50 MYR"` or `"12 USD"`.
- The scripts fetch a live ECB FX rate, convert into `TRACKER_CURRENCY`, and store the converted amount in the sheet.
- When conversion happens, the scripts append an `[auto-fx]` audit line to `notes` with the original amount, converted amount, rate, and rate date.
- Never read the sheet to discover the base currency during normal operation. Use the configured environment instead.

## Category Matching Rules
The Simplify Budget sheet has a fixed list of user-defined categories (e.g. "Dining Out 🍽️", "Groceries 🛒", "Transport 🚗"). You MUST:
1. Always fetch the live category list before writing — never guess or hardcode categories
2. Match the user's description to the closest category using common sense:
   - coffee, restaurants, takeaway, lunch, dinner, pizza, fast food → Dining Out
   - supermarket, groceries, food shopping → Groceries
   - uber, taxi, bus, metro, fuel → Transport
   - etc.
3. Always make your best guess — never ask the user to pick a category
4. Construct the category as `=zategory{stableId}` (e.g. `=zategory4`) — never use the fullName string as the write input
5. Only use categories that exist in the live category list. Never invent new category names like "Electronics" if they are not present.
6. The confirmation message must mention the actual resolved category from the live list, not the model's guessed label.

## Workflows

### Log a new expense

When the user provides an expense (amount + description, with optional date/account/notes):

1. Fetch the current active categories:
   ```
   bash <skill_dir>/scripts/get_categories.sh
   ```
   This returns lines of `stableId<TAB>fullName`. Show the fullNames to yourself for matching — do NOT show this raw output to the user.

2. Extract from the user's message:
   - `amount` — required. If the user mentions a foreign currency, preserve it in the amount string you pass to the script, for example `"50 MYR"` or `"12 USD"`. If they give no currency, pass a plain number like `10`.
   - `description` — what they bought/paid for (required)
   - `category` — match to the fetched category list; construct `=zategory{stableId}` (e.g. `=zategory4` for Dining Out, `=zategory2` for Transport)
   - `date` — in YYYY-MM-DD format. Default to today if not specified.
   - `account` — default to "Cash" if not specified
   - `notes` — optional supporting context. Keep the main purchase title in `description` and extra detail in `notes`

3. Write the expense:
   ```
   bash <skill_dir>/scripts/write_expense.sh "<amount_or_amount_with_currency>" "=zategory<stableId>" "<description>" "<YYYY-MM-DD>" "<account>" "<notes>"
   ```

   If the user asks to add multiple expenses in one message, split them into separate `write_expense.sh` calls. Never try to pass multiple amounts into one command.
   Examples:
   - `add 3 test expenses with 1 2 and 3 euro`
   - run three separate writes for `1`, `2`, and `3`
   - use distinct descriptions like `test expense 1 euro`, `test expense 2 euro`, `test expense 3 euro`
   - keep the same date/account defaults unless the user says otherwise

4. Confirm to the user in a friendly, concise way:
   "✅ Logged [description] — [amount] under [actual resolved category] on [date]"
   Include notes only when present.
   Always name the category you actually used.

### Log an expense from a receipt image

When the user uploads a receipt image or asks you to log a receipt:

1. Read the receipt visually and extract the likely:
   - merchant
   - final charged total or grand total
   - transaction date if visible
   - broad purchase type
2. Default to exactly one expense row per receipt.
3. Do NOT create one expense per line item unless the user explicitly asks to split the receipt.
4. Prefer the actual charged total, final total, or grand total.
   - Do not use subtotal unless that is the only total shown.
   - Do not sum visible item lines if a final total is already present.
5. Use the merchant name or a short summary as the `description`.
6. Best-match the whole receipt into one real category using the live category list.
7. If the receipt is materially mixed, such as fuel plus snacks:
   - default to one expense using the dominant purpose
   - ask one short clarification only if the split is important or the category is genuinely ambiguous
8. Then run the normal expense write flow.

Examples:
- grocery receipt with 10 items -> one Groceries expense using the grand total
- restaurant receipt with food and tax lines -> one Dining Out expense using the final total
- petrol station receipt with mostly fuel and a small snack -> one Transport expense by default unless the user asks to split it

### Find or inspect expenses

When the user wants to inspect, fix, or delete an expense, resolve it from the sheet first:

1. Build a short natural-language query from the user's message.
2. Search the sheet:
   ```
   bash <skill_dir>/scripts/find_expenses.sh "<query>" 10
   ```
3. Matching MUST consider both `description` and `notes`.
4. If one clear match exists, proceed. If multiple plausible matches exist, ask one short disambiguation question.

### Log a new income

When the user provides income (amount + name, with optional date/account/source/notes):

1. Extract from the user's message:
   - `amount` — required. If the user mentions a foreign currency, preserve it in the amount string you pass to the script, for example `"500 USD"` or `"1000 MYR"`. If they give no currency, pass a plain number.
   - `name` — required. This is the income title, e.g. `Salary`, `BMW Sale`, `Etoro withdrawal`
   - `date` — in YYYY-MM-DD format. Default to today if not specified.
   - `account` — default to `Other` if not specified.
   - `source` — default to `Other` if not specified. Use the user’s wording when it is clear, e.g. `Salary`, `Capital Gains`, `Remittance`, `Crypto`, `MTS`.
   - `notes` — optional supporting context.

2. Write the income:
   ```
   bash <skill_dir>/scripts/write_income.sh "<amount_or_amount_with_currency>" "<name>" "<YYYY-MM-DD>" "<account>" "<source>" "<notes>"
   ```

3. Confirm to the user in a concise way:
   "✅ Logged income [name] — [amount] into [account] from [source] on [date]"
   Include notes only when present.

### Find or inspect income

When the user wants to inspect, fix, or delete income, resolve it from the sheet first:

1. Build a short natural-language query from the user's message.
2. Search the sheet:
   ```
   bash <skill_dir>/scripts/find_income.sh "<query>" 10
   ```
3. Matching MUST consider `name`, `source`, and `notes`.
4. If one clear match exists, proceed. If multiple plausible matches exist, ask one short disambiguation question.

### Inspect recurring schedule

When the user asks read-only recurring questions like:
- `what is due this month`
- `when is capcut due`
- `what subscriptions are due next`

Use the recurring query script. Do NOT write anything into `Expenses` or `Income`.

Examples:
```
bash <skill_dir>/scripts/find_recurring.sh --month 2026-03
bash <skill_dir>/scripts/find_recurring.sh --query "CapCut" --date 2026-03-28
bash <skill_dir>/scripts/find_recurring.sh --query "CapCut" --mode next --date 2026-03-28
```

Rules:
1. This is read-only. Never materialize recurring rows into the ledgers.
2. The script calculates cycles from `Recurring` using the same recurrence rules as the existing Apps Script logic.
3. For month-style questions, return the current-month cycle entries.
4. For `when is X due`, prefer `--mode next`.
5. Respond concisely with the due date, amount, account, and whether it is expense or income.

### Fix or delete recurring items

When the user wants to change or delete a recurring item in the `Recurring` tab:

1. Resolve the target recurring row using `find_recurring.sh`.
2. If one clear match exists, mutate the `Recurring` row itself. Never write anything into `Expenses` or `Income` for this task.
3. To update a recurring row, use `__KEEP__` for unchanged fields and `__CLEAR__` for optional end date / notes / source:
   ```
   bash <skill_dir>/scripts/update_recurring.sh "<recurring_id>" "<YYYY-MM-DD_or___KEEP__>" "<name_or___KEEP__>" "<category_or___KEEP__>" "<expense_or_income_or___KEEP__>" "<Monthly_or_Quarterly_or_Yearly_or___KEEP__>" "<amount_or___KEEP__>" "<account_or___KEEP__>" "<YYYY-MM-DD_or___KEEP___or___CLEAR__>" "<notes_or___KEEP___or___CLEAR__>" "<source_or___KEEP___or___CLEAR__>"
   ```
4. To delete a recurring row, clear the row by recurring id:
   ```
   bash <skill_dir>/scripts/delete_recurring.sh "<recurring_id>"
   ```
5. Confirm concisely what changed.

### Add a recurring item

When the user wants to add a recurring expense or recurring income to the `Recurring` tab:

1. Extract:
   - `start_date` in `YYYY-MM-DD`
   - `name`
   - `category` must use the live active category list; never invent a category
   - `type` as `expense` or `income`
   - `frequency` as `Monthly`, `Quarterly`, or `Yearly`
   - `amount`
   - optional `account`, `end_date`, `notes`, `source`
2. Write it with:
   ```
   bash <skill_dir>/scripts/write_recurring.sh "<YYYY-MM-DD>" "<name>" "<category>" "<expense_or_income>" "<Monthly_or_Quarterly_or_Yearly>" "<amount>" "<account>" "<YYYY-MM-DD_optional_end_date>" "<notes>" "<source>"
   ```
3. This must reuse the first empty row in `Recurring` starting from row 6, matching the SB_LIVE hole-reuse behavior.
4. Recurring categories follow SB_LIVE rules:
   - expense recurring items must store a `=zategory<stableId>` formula derived from the live category list
   - recurring income is the only case that may store the literal `Income 💵`
5. Never ask the user to pick a category unless they explicitly want to choose. Best-match into an existing category.
6. Confirm concisely.

### Fix or correct income

When the user wants to change amount, name, date, account, source, or notes for an income row:

1. Resolve the target income from the sheet using `find_income.sh`. Do NOT trust chat memory as the source of truth.
2. Infer the correction from their message. If the new amount is in a foreign currency, preserve that currency in the amount argument you pass to the script.
3. Run the update. Use `__KEEP__` for unchanged fields and `__CLEAR__` to blank notes:
   ```
   bash <skill_dir>/scripts/update_income.sh "<transaction_id>" "<amount_or_amount_with_currency_or___KEEP__>" "<name_or___KEEP__>" "<YYYY-MM-DD_or___KEEP__>" "<account_or___KEEP__>" "<source_or___KEEP__>" "<notes_or___KEEP___or___CLEAR__>"
   ```
4. Confirm: "✅ Updated income — now [name] — [amount] into [account] from [source]"

### Delete income

If the user asks to undo or delete an income entry:

1. Resolve the target income from the sheet using `find_income.sh`.
2. If there is one clear match, clear the row by transaction id:
   ```
   bash <skill_dir>/scripts/delete_income.sh "<transaction_id>"
   ```
3. Confirm that the income row was cleared.
4. Never delete sheet rows. Clear the existing row contents instead.


### Fix or correct the last expense

When the user says things like "fix that", "that was wrong", "change the amount", "put that under X instead", "it was 4 not 5":

1. Resolve the target expense from the sheet using `find_expenses.sh`. Do NOT trust chat memory as the source of truth.

2. Ask for or infer the correction from their message (amount, category, description, date, account, or notes). If the new amount is in a foreign currency, preserve that currency in the amount argument you pass to the script.

3. For category corrections, fetch the category list again and match:
   ```
   bash <skill_dir>/scripts/get_categories.sh
   ```

4. Run the update with the corrected values. Use `__KEEP__` for unchanged fields and `__CLEAR__` to blank notes:
   ```
   bash <skill_dir>/scripts/update_expense.sh "<transaction_id>" "<amount_or_amount_with_currency_or___KEEP__>" "<=zategory<stableId>_or___KEEP__>" "<description_or___KEEP__>" "<YYYY-MM-DD_or___KEEP__>" "<account_or___KEEP__>" "<notes_or___KEEP___or___CLEAR__>"
   ```

5. Confirm: "✅ Updated — now [description] — [amount] under [actual resolved category]"
   Include notes only when present.
   Always name the category you actually used.

### Undo / delete last expense
If the user asks to undo or delete an entry:

1. Resolve the target expense from the sheet using `find_expenses.sh`.
2. If there is one clear match, clear the row by transaction id:
   ```
   bash <skill_dir>/scripts/delete_expense.sh "<transaction_id>"
   ```
3. Confirm that the expense row was cleared.
4. Never delete sheet rows. Clear the existing row contents instead.

## Rules
- Never hardcode category names — always fetch them live
- Never claim a category that does not exist in the live category list
- For new expenses, always best-match into one of the real categories and tell the user which category was used
- For income, never invent hidden structure. Use the explicit `name`, `account`, `source`, and `notes` columns on the Income tab.
- Never show raw script output to the user — parse it and respond naturally
- Always confirm what you logged — the user should never have to guess if it worked
- If a script returns an error, tell the user clearly and do not silently retry
- Default date is always today in the user's local timezone
- Default account is always "Cash" unless the user specifies otherwise
- Default income account is always "Other" unless the user specifies otherwise
- Default income source is always "Other" unless the user specifies otherwise
- Amounts are always stored as plain numbers in `TRACKER_CURRENCY`
- If a foreign currency is provided, keep it in the script input and let the script convert it into `TRACKER_CURRENCY`
- Notes are a first-class field. Search them, preserve them on update unless changed, and clear them on delete.
- For edits and deletes, the sheet is the source of truth. Resolve the target row from the sheet before mutating anything.
- Recurring schedule questions are read-only. Never create expense or income rows just because the user asked what is due.
- The 🤖 label on written rows identifies bot-added entries in the sheet
