# AccountantsNext Mobile — 0.2.0 (build 2)

Native iOS 16+ companion for the Windows AccountantsNext system.

## Supported modules
- **HR:** employee profile and leave settlement viewer.
- **Payments & receipts:** view imported payment/receipt vouchers and create encrypted, on-device **receipt drafts** with supporting files and PDF export.
- **Company information:** view entities, legal document details and supporting files included in the Windows backup.
- **Agent Zee:** local-only record lookup. This is NOT a networked AI agent or Windows automation.

No invoice module, accounting journal editor, or Xero posting. Manager Reporting remains a Windows/Xero workflow.

## Data integrity boundary
1. Import the Windows \`Accountants5_FULL_*.zip\` backup or \`AccountantsNext.db\` via the Company's settings panel.
2. The app copies the snapshot into its own Application Support container.
3. GRDB opens the imported database with \`Configuration.readonly = true\`.
4. Receipt drafts and attachment files are saved **separately** in protected iOS app storage.
5. No cloud sync, network calls, remote LLM data transmission, or writes to the PC database are enabled.
6. Face ID or the device passcode is required to unlock. A device passcode must be configured.
7. The PDF export is clearly marked LOCAL DRAFT, not a posted Windows receipt.

For payroll totals, HR editing, automated Agent Zee actions, sync, and official financial Manager Reports, use the desktop app until the schema and API are formally integrated.

## Building
- XcodeGen project: \`AccountantsMobile/project.yml\`
- Native iOS deployment target: 16.0
- GitHub Actions workflow: \`.github/workflows/build-accountants-mobile-v020.yml\`
- Run \`bash AccountantsMobile/build.sh\` on macOS with Xcode and XcodeGen.
- Output: \`AccountantsMobile/dist/AccountantsMobile-0.2.0.tipa\` and \`.ipa\`
- Bundle: \`com.nextsolution.accountantsmobile\` (upgrade-safe for 0.1.0).

## Security / release limitations
This is a first field-test build, not a claim of complete on-device QA. Do not use it as the sole storage location for critical business records. Keep the original Windows backup. Changes drafted on iPhone do not appear on the PC without a future reviewed synchronization module.
