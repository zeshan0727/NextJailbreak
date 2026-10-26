# Next Accountant — GitHub Free Preview

This folder is intentionally a **static, browser-local preview** so it can run on the existing GitHub Pages site at zero server cost.

## URL

https://nextjailbreak.com/accountants/

## Security boundary

The preview must never contain:
- AccountantsNext.db
- company/customer/employee records
- uploaded business documents
- OpenAI API keys
- passwords or access tokens
- production backups

Data entered in this preview is stored only in the browser's localStorage and can be exported/imported as JSON for test purposes.

## Why AI and sync are disabled

GitHub Pages cannot safely hold server-side secrets or operate PostgreSQL. OpenAI document reading, multi-user authentication, multi-device sync and authoritative company data will be enabled only after a secure backend is introduced.

## Migration design

The UI is deliberately separated from future persistence. When the project moves to a secure backend, the local preview store will be replaced with authenticated API/database services while preserving the web workflow.
