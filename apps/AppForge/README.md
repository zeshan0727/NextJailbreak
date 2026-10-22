# AppForge — native iOS 16+ app builder

A SwiftUI / MVVM app that converts a requirement to a prompt, calls a user-chosen OpenAI-compatible chat API to generate Swift source, creates an XcodeGen project, commits to GitHub, watches GitHub Actions, and downloads IPA/TIPA release assets. No backend, analytics, or third-party runtime SDKs.

## Build AppForge (without your own Mac)

1. Create an empty **public** GitHub repository and upload these files **including** `.github/workflows/build-appforge.yml` (or push with Git).
2. In the repository **Settings → Actions → General → Workflow permissions**, permit read/write access for `GITHUB_TOKEN` so that the job can publish releases.
3. Open **Actions → Build AppForge → Run workflow**. It installs XcodeGen and runs Xcode's command-line build on `macos-latest`.
4. When completed, open **Releases** and download `AppForge.ipa` or `AppForge.tipa` (also in Actions artifacts).
5. Use a compatible on-device signing/installation method. These archives are **unsigned**; renaming an IPA to TIPA is not code signing. Ordinary non-jailbroken iPhones will not install an unsigned IPA. TrollStore compatibility depends on device, OS, payload and signing approach.

To change target iOS version, edit `project.yml` / deployment target (the Settings control affects generated projects only). The source targets iOS 16 and has no commercial dependencies.

## Configure inside the app

1. Open **Settings** (gear) and enter an OpenAI-compatible HTTPS base URL such as `https://api.groq.com/openai/v1`, the provider's **exact** model ID, and your own key. Free-tier availability, quotas, and model names change.
2. Create a GitHub token with **Contents write**, **Actions read/write**, **Workflows write** for the repos in scope. If creating repos from the app is unavailable with a fine-grained token, create the repo on GitHub first; token type and organization policy can restrict repository creation.
3. Allow Actions to run and publish releases (`contents: write` is declared in workflows, subject to repo policy).
4. Generate Prompt → Send to Code → Generate Code → Send to GitHub → Push & Build → Downloads.
5. On build failure use **Fix with AI**. Inspect corrections before pushing. The fixed scaffold cannot guarantee arbitrary AI-generated Swift will compile.

## Key implementation notes

- Stored secrets: iOS Keychain, ThisDeviceOnly accessibility. Other settings and capped prompt history: UserDefaults.
- Source export: ZIP method 0 (stored, no compression), standard ZIP CRC32; no ZIP dependency.
- GitHub push uses `git/blobs` → `git/trees` (with parent tree) → `git/commits` → update or create `refs/heads/...`.
- GitHub Actions may not dispatch a newly added workflow on a non-default branch; the push event is primary. The app retries a `workflow_dispatch` only if no run appears, which requires the workflow on the **default** branch.
- Logs are fetched via job-specific log endpoint (text). Run progress refreshes every 8 seconds while the Build tab is active. Local success notifications occur when the app detects completion; iOS may suspend polling in the background, so this is not a remote push notification service.
- Release downloads use GitHub's asset API, which may be blocked by provider permissions or storage policies; errors are surfaced. Files appear in Files → On My iPhone → AppForge when supported by the installation environment.
- The generated app workflow packages an unsigned `.app` as `Payload/*.app` inside `.ipa`, then copies it as `.tipa`. It does **not** make a regular iOS installable, provisioned app.

## Cost qualification (October 2026)

Standard GitHub-hosted runners in **public** repositories are free; private repositories consume account allowance and may incur fees. Free-tier AI APIs are subject to provider quotas. This setup can cost zero **within those conditions**, not unconditionally. Public repositories expose your source code.

## Structure

`project.yml`, `AppForge/` (Swift code and icon assets), `.github/workflows/build-appforge.yml`.
