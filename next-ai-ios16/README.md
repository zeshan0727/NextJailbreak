# Next AI 0.3.0 — Turbo: offline chat + photos
Target: iPhone 14 Pro Max, iOS 16.0, TrollStore. Install NextAI-0.3.0-Turbo.tipa over the existing Next AI. Do not uninstall first: app data is retained by an in-place update.

## Chat
Existing Qwen model selection and chats are retained. Chat and photo workloads are serialized to control memory. Chat streaming UI updates are throttled; reading earlier messages no longer forces the screen to the bottom. Menu includes Copy last answer. File picker and direct folder model selection remain available.

## Fast SD-Turbo
Download the complete SD-Turbo Q4_0 model (about 2.19 GB):
https://huggingface.co/gpustack/stable-diffusion-v2-1-turbo-GGUF/resolve/main/stable-diffusion-v2-1-turbo-Q4_0.gguf?download=true
Model card: https://huggingface.co/gpustack/stable-diffusion-v2-1-turbo-GGUF

Select Photos → Fast SD-Turbo, then import/select that model. Keep its original filename containing turbo. Start at 384×384 / 2 steps; use 1 step for the fastest preview or 4 for another quality option. Standard and Turbo model selections are stored separately. Turbo disables negative prompts, uses Euler with trailing timesteps, explicit epsilon prediction, and disables classifier-free guidance. Actual speed must be measured on the phone; model loading and decoding still take time. Results show total, load, and render seconds. 512×512 is also available.

## Standard photo generation
Download the complete SD 1.5 Q4_0 model (about 1.57 GB):
https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf?download=true
Model card and license: https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF

Copy the downloaded .gguf into Files → On My iPhone → Next AI. Open the Photos tab → Models / Gallery → Use image model from Next AI folder. Choose SD 1.5, not Qwen. Import from Files is also available. Models remain separate; do not replace your chat model.

Start with 384×384 / 20 steps. 512×512 and 12/24 steps are optional. Write an English description for best results with this model. Negative prompt and seed are optional. Blank seed selects a random seed. Keep the app in the foreground; auto-lock is disabled during generation. This initial photo engine does not provide mid-generation cancellation. Model memory is released after each image, so loading happens for each generation.

Images are saved as PNGs under Documents/Generated Images alongside prompt/settings JSON. The latest image reopens when the app launches. Models / Gallery lists the latest 20 images; all older images remain accessible in Files. Use Share to export or Save to Photos to grant add-only Photos access and save. Generated images are not uploaded anywhere.

## Validation and limits
Build checks: native arm64 compilation for iOS 16, embedded framework linkage, isolated photo-engine symbols, and nested ad-hoc signatures. These do not establish on-device generation speed or memory stability. This is a device test build. Large models, SDXL/FLUX, image editing, and video are outside this version. Use the linked complete SD 1.5 or SD-Turbo GGUF in its matching mode.

Test: launch after update; reopen a chat; generate one 384×384 image in airplane mode; export/save it; reopen it in gallery; return to chat and send a message. If iOS closes the app during generation, relaunch and report the resolution/step count used.

Source engines: llama.cpp b5046 and stable-diffusion.cpp 0d9d6659a7ebb7fc51902d6a96f2ea60bd0e82d6 (MIT). The photo engine has its own isolated framework because its GGML version differs from the chat engine. Metal kernels are embedded; no external library download is needed on the phone.
