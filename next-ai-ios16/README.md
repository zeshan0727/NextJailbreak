# Next AI — iOS 16 / TrollStore Test 1
Native UIKit offline text chat powered by llama.cpp b5046 (MIT).

Download the NextAI-TrollStore-Test1 artifact from the build's Actions page, unzip it, and open NextAI-Test1.tipa in TrollStore. No model is bundled.

Recommended test model (Apache 2.0, official Qwen):
https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true

Save the model to Files. Open Next AI → Menu → Import model. Keep the app open during copying and generation. First load may take time. Model imports are copied into the app's Documents/Models folder; keep at least 3 GB free before importing. Model and chats stay on device. No networking or telemetry code is included.

Features: streaming chat, Stop, saved chats, new chat, deletion confirmation, copying conversations, GGUF validation, background cancellation. 2048 context tokens, maximum 384 output tokens. Oversized conversations show an explicit error rather than silently dropping history. Models over 2.2 GB are rejected for this first device test. Model switches occur through import; older copies can be removed through Files when the app is idle. Model template compatibility depends on llama.cpp b5046; newer architectures may not work.

Device test checklist:
1. Install and launch on iOS 16.0 through TrollStore.
2. Import the recommended complete GGUF; send 'Say hello in one sentence'.
3. Turn on airplane mode and send a follow-up.
4. Tap Stop during a longer reply; send another message.
5. Start a new chat, then reopen the old chat through Saved chats.
6. Quit/relaunch and reopen a saved chat; verify model selection remains.
7. Delete a chat and confirm it remains deleted after relaunch.
8. Try a wrong file and a long prompt; confirm helpful errors.

Builds use a macOS runner, CMake/Xcode, arm64 iPhoneOS 16.0 target and embedded Metal source. The app is ad-hoc signed for TrollStore. It does not request root, private entitlements, or filesystem access outside its container and user-selected files. On-device performance and memory stability require real hardware testing.
