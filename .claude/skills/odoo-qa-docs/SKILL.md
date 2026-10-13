---
name: odoo-qa-docs
description: Odoo 18 QA & documentation for Thai implementation projects — writes Test Cases, UAT scripts, User Manuals (คู่มือการใช้งาน) and Bug Reports, exports to Excel/Word. Use when the user asks for test case, เทสเคส, UAT, SIT, test script, คู่มือ, manual, SOP, bug report, รายงานบั๊ก, or QA for an Odoo module/process (Sales, Purchase, Inventory, Accounting, MRP, POS, CRM).
---

# Odoo QA & Docs (Odoo 18, Thailand)

## Token rules (always follow)
1. Load ONLY the files needed: one template + only the module file(s) in scope. Never load all modules.
2. Do not echo the user's input, do not explain the template, no preamble. Output the deliverable directly.
3. Ask at most ONE round of questions, only if module/process is unknown. Otherwise assume defaults below and list assumptions in ≤3 bullets at the end.
4. Use tables, not prose. One line per step. No repeated text across rows — put shared preconditions/data once in a header block.
5. Large requests (>30 test cases or >1 module): write straight to a file in batches per module; reply with path + counts only, not the content.
6. Exports go through `scripts/export.py` (run it, do not read it).

## Defaults (unless user says otherwise)
- Odoo 18 (Community/Enterprise per user), company in Thailand, currency THB, VAT 7%.
- Document language: Thai, Odoo menu/button/field names in English exactly as in UI (e.g. `Sales > Orders > Quotations`, button **Confirm**).
- Output folder: `docs/<type>/` in the working project. File name: `<TYPE>_<MODULE>_<yyyymmdd>.md`.

## Pick the mode → load that template
| User asks for | Template | Typical export |
|---|---|---|
| Test case / SIT / เทสเคส | `templates/test-case.md` | xlsx |
| UAT script / sign-off | `templates/uat-script.md` | xlsx + docx |
| คู่มือ / user manual / SOP | `templates/user-manual.md` | docx |
| Bug / defect report | `templates/bug-report.md` | md (paste to tracker) |

## Module knowledge → load only what is in scope
`modules/sales.md`, `modules/purchase.md`, `modules/inventory.md`, `modules/accounting-th.md`, `modules/mrp.md`, `modules/pos.md`, `modules/crm.md`.
If a module is not listed, use your own Odoo 18 knowledge and mark uncertain menu paths with `(verify)`.

## Accuracy
- Never invent customer-specific config. Customizations / Studio fields from the user's spec (FSD, BRD, Fit-Gap) take priority over standard behavior.
- If an Odoo MCP/agent connection is available and the user asks to verify, check menu/field names against the live instance instead of guessing.
- Mark anything that depends on configuration as `[CONFIG]` in the Remark column.

## Export
```bash
python3 .claude/skills/odoo-qa-docs/scripts/export.py <file.md> [--xlsx] [--docx]
```
- `--xlsx`: every Markdown table → one sheet (styled header, wrap text, Thai font, freeze header, Status dropdown).
- `--docx`: whole Markdown → Word via pandoc (headings, tables, image placeholders kept).
Default with no flag: both.
