# Marketplace gap audit

Audit of the Railway Marketplace for an existing Receipt Wrangler (or equivalent receipt
scanning / expense reconciliation) template.

- **Audit timestamp (UTC):** 2026-09-11T17:51:37Z (initial); pre-publication rerun recorded below
- **Tool:** `npx -y @railway/cli@latest templates search "<query>" --json --limit 50` (Railway CLI 5.52.1)
- **Secondary:** web search for `site:railway.com/deploy` plus product name and aliases

## Queries and results

| # | Query | Class | Result |
|---|---|---|---|
| 1 | `receipt wrangler` | exact product name | 0 results |
| 2 | `receipt-wrangler` | repository name | 0 results |
| 3 | `receipt` | generic need | 3 results: notal, SplitPro, Homebox |
| 4 | `receipts` | generic need | same 3 results |
| 5 | `expense receipts` | generic need | 0 results |
| 6 | `receipt scanner` | core use case | 0 results |
| 7 | `receipt ocr` | core capability | 0 results |
| 8 | `reimbursement` | commercial alternative category | 0 results |

### Adjacent matches inspected

| Template | Code | What it is | Overlap with Receipt Wrangler |
|---|---|---|---|
| SplitPro | `splitpro` | shared-expense app (my own earlier template) | partial: attaches receipt images to an expense, but no OCR/AI extraction, no line items, no receipt workflow/status, no email ingestion |
| Homebox | `homebox-2` | home inventory with warranties and receipts | none: inventory items, receipts are attachments |
| notal | `notal` | Markdown work queue, "receipts" in the audit-trail sense | none |

No template scans a receipt image, extracts merchant/total/line items with OCR or an AI provider,
and splits the result between people, which is Receipt Wrangler's purpose.

### Web search

`site:railway.com/deploy receipt wrangler OR "receipt scanner" OR "receipt ocr"` returned no
railway.com/deploy page for Receipt Wrangler.

## Conclusion (initial audit)

**Clean gap.** No exact or alias match; the adjacent templates solve different problems.
Proceeding with Receipt Wrangler.

## Re-audit before publication

| Timestamp (UTC) | Queries | Result |
|---|---|---|
