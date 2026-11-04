# Aspire Maintenance 1.0.1 Test

Private business app for **Aspire Green Garden Designing and Works LLC**.

## First-test features

- Permanent monthly-maintenance customer register
- Planned visits per month and completed visit logs
- Single and bulk monthly invoice generation
- Aspire-branded PDF invoices
- Gmail Direct delivery through the existing scheduler/connector approach
- Apple Mail assisted delivery and PDF sharing fallback
- Invoice status, payment recording, outstanding balance and overdue tracking
- Receivables aging: current, 1–30, 31–60, 61–90 and 90+ days
- Long-overdue local notification alerts
- Expense recording including fuel, labour, materials, equipment and vehicle costs
- Monthly invoice income, expenses and profit/loss
- Complete JSON backup export and import

## Branding and data

The app, bundle ID and generated invoices use Aspire branding only. No Next Solution or Bin Noman branding is used. The first launch contains no real customer data. Optional demo data can be added from Settings and deleted after testing.

## Build

The GitHub Actions workflow generates an unsigned iOS 16+ `.tipa` for TrollStore.
