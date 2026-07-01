# Typist

**A free, open source, and extensible speech-to-text application that works completely offline.**

Typist is a cross-platform desktop application that provides simple, privacy-focused speech transcription. Press a shortcut, speak, and have your words appear in any text field — entirely on your own computer, without sending anything to the cloud.

> **Typist is a fork of [Handy](https://github.com/cjpais/Handy)** by CJ Pais, an open-source speech-to-text app built to be the most forkable one. Typist builds on that foundation with its own branding and direction. Huge thanks to CJ and the Handy contributors. Typist is an independent, unofficial fork and is not affiliated with or endorsed by the Handy project.

## How It Works

1. **Press** a configurable keyboard shortcut to start/stop recording (or use push-to-talk mode)
2. **Speak** your words while the shortcut is active
3. **Release** and Typist processes your speech locally
4. **Get** your transcribed text pasted directly into whatever app you're using

The process is entirely local:

- Silence is filtered using VAD (Voice Activity Detection) with Silero
- Transcription uses your choice of models:
  - **Whisper models** (Small/Medium/Turbo/Large) with GPU acceleration when available
  - **Parakeet V3** — CPU-optimized model with excellent performance and automatic language detection
- Works on Windows, macOS, and Linux

## Building from Source

Typist is currently distributed as source. To build and run it:

**Prerequisites:** [Rust](https://rustup.rs/) (latest stable) and [Bun](https://bun.sh/).

```bash
# Install dependencies
bun install

# Download the required VAD model
mkdir -p src-tauri/resources/models
curl -o src-tauri/resources/models/silero_vad_v4.onnx https://blob.handy.computer/silero_vad_v4.onnx

# Run in development
bun run tauri dev
# If you hit a cmake error on macOS:
CMAKE_POLICY_VERSION_MINIMUM=3.5 bun run tauri dev

# Build a production bundle
bun run tauri build
```

For detailed platform-specific build setup, see [BUILD.md](BUILD.md). For architecture and contribution notes, see [AGENTS.md](AGENTS.md).

## Speech Models

Transcription models are downloaded on first use from the upstream Handy model host. Whisper variants:

- Small (487 MB): `https://blob.handy.computer/ggml-small.bin`
- Medium (492 MB): `https://blob.handy.computer/whisper-medium-q4_1.bin`
- Turbo (1600 MB): `https://blob.handy.computer/ggml-large-v3-turbo.bin`
- Large (1100 MB): `https://blob.handy.computer/ggml-large-v3-q5_0.bin`

Parakeet variants:

- V2 (473 MB): `https://blob.handy.computer/parakeet-v2-int8.tar.gz`
- V3 (478 MB): `https://blob.handy.computer/parakeet-v3-int8.tar.gz`

## Data Location

Typist stores its settings, models, and history under the app data directory:

- **macOS**: `~/Library/Application Support/com.joao.typist/`
- **Windows**: `C:\Users\{username}\AppData\Roaming\com.joao.typist\`
- **Linux**: `~/.config/com.joao.typist/`

## License

MIT License — see [LICENSE](LICENSE). Typist is a fork of Handy and retains the original
copyright notice as required by the MIT license.

The **Typist** name and icon are this fork's own branding. The **Handy** name, logo, icon, and
brand assets belong to the Handy project and are not used here; this fork ships its own.

## Acknowledgments

- **[Handy](https://github.com/cjpais/Handy)** by CJ Pais — the upstream project Typist is forked from
- **Whisper** by OpenAI for the speech recognition model
- **whisper.cpp and ggml** for cross-platform whisper inference/acceleration
- **Silero** for great lightweight VAD
- **Parakeet** for the CPU-optimized transcription model
- **Tauri** team for the excellent Rust-based app framework
