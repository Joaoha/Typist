use crate::audio_toolkit::filter_transcription_output;
use crate::managers::audio::AudioRecordingManager;
use crate::managers::transcription::TranscriptionManager;
use crate::settings::{get_settings, write_settings, ModelUnloadTimeout};
use serde::Serialize;
use specta::Type;
use std::sync::Arc;
use tauri::{AppHandle, Manager, State};

/// Dedicated binding id used for the settings "record a correction" capture, so
/// it never collides with real transcription shortcut bindings.
const WORD_CAPTURE_BINDING: &str = "__word_capture__";

#[derive(Serialize, Type)]
pub struct ModelLoadStatus {
    is_loaded: bool,
    current_model: Option<String>,
}

#[tauri::command]
#[specta::specta]
pub fn set_model_unload_timeout(app: AppHandle, timeout: ModelUnloadTimeout) {
    let mut settings = get_settings(&app);
    settings.model_unload_timeout = timeout;
    write_settings(&app, settings);
}

#[tauri::command]
#[specta::specta]
pub fn get_model_load_status(
    transcription_manager: State<TranscriptionManager>,
) -> Result<ModelLoadStatus, String> {
    Ok(ModelLoadStatus {
        is_loaded: transcription_manager.is_model_loaded(),
        current_model: transcription_manager.get_current_model(),
    })
}

#[tauri::command]
#[specta::specta]
pub fn unload_model_manually(
    transcription_manager: State<TranscriptionManager>,
) -> Result<(), String> {
    transcription_manager
        .unload_model()
        .map_err(|e| format!("Failed to unload model: {}", e))
}

/// Start a one-off recording for the "record a correction" flow in settings.
/// Kicks off model loading so transcription is ready when recording stops.
#[tauri::command]
#[specta::specta]
pub fn start_word_capture(app: AppHandle) -> Result<(), String> {
    app.state::<Arc<TranscriptionManager>>().initiate_model_load();
    app.state::<Arc<AudioRecordingManager>>()
        .try_start_recording(WORD_CAPTURE_BINDING)
}

/// Discard an in-progress correction capture without transcribing.
#[tauri::command]
#[specta::specta]
pub fn cancel_word_capture(app: AppHandle) -> Result<(), String> {
    app.state::<Arc<AudioRecordingManager>>().cancel_recording();
    Ok(())
}

/// Stop the correction capture and return the raw recognizer output — i.e. what
/// the model actually heard. Intentionally skips custom_words / corrections so
/// the user sees the real mistranscription to correct.
#[tauri::command]
#[specta::specta]
pub async fn stop_word_capture(app: AppHandle) -> Result<String, String> {
    let samples = app
        .state::<Arc<AudioRecordingManager>>()
        .stop_recording(WORD_CAPTURE_BINDING)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "No audio was captured. Try holding the recording a bit longer.".to_string())?;

    let tm = app.state::<Arc<TranscriptionManager>>().inner().clone();
    let text = tauri::async_runtime::spawn_blocking(move || tm.transcribe(samples))
        .await
        .map_err(|e| format!("Transcription task failed: {}", e))?
        .map_err(|e| format!("Transcription failed: {}", e))?;

    let settings = get_settings(&app);
    let cleaned = filter_transcription_output(
        text.trim(),
        &settings.app_language,
        &settings.custom_filler_words,
    );
    Ok(cleaned.trim().to_string())
}
