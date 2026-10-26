# Next Accountant — Static Web Preview (not production)

Preview: https://nextjailbreak.com/accountants/

This GitHub Pages folder is an **isolated, browser-local test application**, not an accounting database and not the authoritative Windows/Xero source.

## Available test flows

- Create temporary demo entities, customers and projects.
- Define contract payment installments separately from actual received payments.
- Record payments, generate generic payment receipts and allocate multiple partial receipts to one installment.
- Unassign, edit or delete demo payments subject to demo validation.
- Enter demo invoices and view a Customer Statement of Account using invoice charges and actual payment credits.
- Export a **demo-only** statement CSV; it is **not** the official Windows PDF or Xero SOA.
- Export/import a browser-local JSON test backup.

## Data and security boundaries

- Never place AccountantsNext.db, employee/customer/company records, signed receipts, real account information, API keys, plaintext passwords, or backups in this public repository or GitHub Pages.
- No live business writes are issued from this preview, and no ads or tracking scripts are included.
- Demo records reside in browser localStorage. Do not enter confidential business information here.
- Cloudflare Workers + D1 + private R2 buckets provide the separate staging and future production backends.
- Staging infrastructure availability does **not** imply that the Windows V6 business backup has been imported, reconciled, or approved for production.
- The staging-only import is initiated by the Windows migrator against a verified copy of the protected business backup.

## Validation

GitHub Actions: `.github/workflows/test-next-accountant-web-preview.yml` runs JavaScript checks, browser DOM integration tests for three receipts against one installment, and invoice-backed Customer SOA checks. It rejects accidental advertisement inclusion and remote writes from the demo modules.

## Cutover gate

Deploy production accounting access only after secure owner authentication, verified staging import, complete count/file-hash/financial reconciliation, correct Windows-format report exports, recovery testing, and module parity. Preserve Windows ACCOUNTANTS V6 as the recovery baseline.
