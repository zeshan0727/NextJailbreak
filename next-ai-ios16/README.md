# Next AI 1.0
Your ideas. On your iPhone.

Created by Zeeshan Barvi · Next Jailbreak · https://nextjailbreak.com

## Install
Install NextAI-1.0.0.ipa using TrollStore on your supported iOS 16+ device. Install over Next AI to retain existing models, conversations and images. This is an ad-hoc TrollStore package, not an App Store or normally provisioned distribution build. Models are not bundled.

## What's new
- Original copper / teal / navy icon and branded interface.
- Light, Dark and System appearance.
- Optional cross-chat memory: Settings → Remember across chats → Edit saved memory. Save your own preferences or facts, up to 1,000 characters. Only these explicit notes carry into new chats. Disable memory to stop including notes; Clear saved memory permanently removes notes. This is prompt context, not model training or automatic recall of every conversation.
- Saved or temporary chats, optional resume of the last saved chat.
- Conversation sharing, copying and retrying the last message.
- Chat prompt starters and image prompt inspiration.
- About, creator credits and bundled open-source licenses.
- Existing SD 1.5 and SD-Turbo image engines and timing display retained.

Saving off starts a temporary conversation when returning to Chat. It does not erase earlier saved chats. Conversations and notes are stored in the app sandbox; device backups may contain them. No account or automatic cloud upload is used.

## Models
Chat Qwen2.5 1.5B Instruct Q4_K_M (about 1.12 GB):
https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true

Fast image SD-Turbo Q4_0 (about 2.19 GB):
https://huggingface.co/gpustack/stable-diffusion-v2-1-turbo-GGUF/resolve/main/stable-diffusion-v2-1-turbo-Q4_0.gguf?download=true
Select Create → Fast SD-Turbo, import or select this model from Library, start at 384 × 384 and 2 steps. 1 and 4 steps are also available. Keep the model's original filename.

Standard image SD 1.5 Q4_0 (about 1.57 GB):
https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf?download=true
Select Standard SD 1.5; 12 / 20 / 24 steps. Each mode remembers its own selected model.

Download completely, then import from Files. Alternatively copy into Files → On My iPhone → Next AI and select it from the app's folder picker. Model cards and license terms are available through Settings → Model downloads.

## Short intro video
1. Show the new Home Screen icon and open Chat.
2. Show Settings, switch to Dark, and add a short preference under saved memory.
3. Enable Remember across chats, start a new chat and demonstrate the preference.
4. Open Create, select Fast SD-Turbo, use Inspire me and generate an image.
5. Show Share / Save to Photos, then About & credits.
Use your own non-sensitive memory notes and chats for the recording.

## Validation and limits
Native arm64 iOS 16 build, Turbo schedule tests, framework isolation, icon presence and nested signatures are checked by CI. On-device layout, generation, memory behavior and actual speed require testing before public promotion. Chat context is 2,048 tokens with replies up to 384 tokens; memory uses some context. Long chats need a new conversation. Image generation must stay in the foreground and cannot be cancelled mid-generation. Model loading occurs for each generation.

llama.cpp b5046 and stable-diffusion.cpp 0d9d6659a7ebb7fc51902d6a96f2ea60bd0e82d6 use separate GGML instances. The NextPhoto framework preserves symbol isolation and embedded Metal kernels. Third-party licenses are bundled and readable in Settings.
