# Next IPA Factory 1.1 — GitHub iPhone Build

Isolated build branch: `feature/next-ipa-factory-v1` (do not merge into the NextJailbreak website main branch).

- GitHub Actions uses `macos-15`, XcodeGen, Xcode, and no signing for compile/package.
- The resulting `NextIPAFactory-1.1-unsigned.ipa` is an unsigned iOS app archive.
- The `.tipa` is byte-identical, for testing with TrollStore on compatible devices.
- UI: request input, configurable 4–12 agent count, task progress, source ZIP export, agent IDs.
- Editable agent IDs saved by authenticated backend `PUT /agents`, mirrored to iPhone cache; API secret stays on server.
- The separate Python backend must be deployed over HTTPS with `OPENAI_API_KEY` and `FACTORY_TOKEN` configured before the app can run tasks.
- GitHub compilation does NOT validate that agent execution has produced a correct final generated IPA; those are distinct stages.
- This branch is intentionally not deployed to nextjailbreak.com.
