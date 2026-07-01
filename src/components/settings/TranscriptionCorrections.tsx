import React, { useState } from "react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import { Mic, Square, Loader2, ArrowRight, X } from "lucide-react";
import { commands } from "@/bindings";
import type { PhraseCorrection } from "@/bindings";
import { useSettings } from "../../hooks/useSettings";
import { Input } from "../ui/Input";
import { Button } from "../ui/Button";
import { SettingContainer } from "../ui/SettingContainer";

interface TranscriptionCorrectionsProps {
  descriptionMode?: "inline" | "tooltip";
  grouped?: boolean;
}

type Phase = "idle" | "recording" | "transcribing" | "review";

/**
 * "Record a correction" flow: the user records themselves saying a word, sees
 * exactly what the recognizer heard, then types what they meant. The pair is
 * stored as an exact (from -> to) transcription correction.
 */
export const TranscriptionCorrections: React.FC<TranscriptionCorrectionsProps> =
  ({ descriptionMode = "tooltip", grouped = false }) => {
    const { t } = useTranslation();
    const { getSetting, updateSetting, isUpdating } = useSettings();
    const corrections = (getSetting("transcription_corrections") ||
      []) as PhraseCorrection[];

    const [phase, setPhase] = useState<Phase>("idle");
    const [heard, setHeard] = useState("");
    const [intended, setIntended] = useState("");

    const saving = isUpdating("transcription_corrections");

    const reset = () => {
      setPhase("idle");
      setHeard("");
      setIntended("");
    };

    const startRecording = async () => {
      const res = await commands.startWordCapture();
      if (res.status === "error") {
        toast.error(res.error);
        return;
      }
      setPhase("recording");
    };

    const stopRecording = async () => {
      setPhase("transcribing");
      const res = await commands.stopWordCapture();
      if (res.status === "error") {
        toast.error(res.error);
        setPhase("idle");
        return;
      }
      const text = res.data.trim();
      if (!text) {
        toast.error(t("settings.advanced.corrections.nothingHeard"));
        setPhase("idle");
        return;
      }
      setHeard(text);
      setIntended(text);
      setPhase("review");
    };

    const cancel = async () => {
      if (phase === "recording") {
        await commands.cancelWordCapture().catch(() => {});
      }
      reset();
    };

    const save = () => {
      const from = heard.trim();
      const to = intended.trim();
      if (!from || !to) return;
      const next: PhraseCorrection[] = [
        ...corrections.filter(
          (c) => c.from.toLowerCase() !== from.toLowerCase(),
        ),
        { from, to },
      ];
      updateSetting("transcription_corrections", next);
      reset();
    };

    const remove = (from: string) => {
      updateSetting(
        "transcription_corrections",
        corrections.filter((c) => c.from !== from),
      );
    };

    return (
      <>
        <SettingContainer
          title={t("settings.advanced.corrections.title")}
          description={t("settings.advanced.corrections.description")}
          descriptionMode={descriptionMode}
          grouped={grouped}
          layout="stacked"
        >
          <div className="flex flex-col gap-2 w-full">
            {phase === "idle" && (
              <Button
                onClick={startRecording}
                variant="primary"
                size="md"
                className="inline-flex items-center gap-2 self-start"
              >
                <Mic className="w-4 h-4" />
                {t("settings.advanced.corrections.record")}
              </Button>
            )}

            {phase === "recording" && (
              <div className="flex items-center gap-2">
                <Button
                  onClick={stopRecording}
                  variant="primary"
                  size="md"
                  className="inline-flex items-center gap-2"
                >
                  <Square className="w-4 h-4" />
                  {t("settings.advanced.corrections.stop")}
                </Button>
                <span className="text-sm text-mid-gray inline-flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
                  {t("settings.advanced.corrections.listening")}
                </span>
              </div>
            )}

            {phase === "transcribing" && (
              <span className="text-sm text-mid-gray inline-flex items-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t("settings.advanced.corrections.transcribing")}
              </span>
            )}

            {phase === "review" && (
              <div className="flex flex-col gap-2">
                <div className="text-sm">
                  <span className="text-mid-gray">
                    {t("settings.advanced.corrections.heardLabel")}
                  </span>{" "}
                  <span className="font-mono">{heard}</span>
                </div>
                <div className="flex items-center gap-2 flex-wrap">
                  <Input
                    type="text"
                    value={intended}
                    onChange={(e) => setIntended(e.target.value)}
                    placeholder={t(
                      "settings.advanced.corrections.intendedPlaceholder",
                    )}
                    variant="compact"
                    className="max-w-60"
                  />
                  <Button
                    onClick={save}
                    disabled={!intended.trim() || saving}
                    variant="primary"
                    size="md"
                  >
                    {t("settings.advanced.corrections.save")}
                  </Button>
                  <Button onClick={cancel} variant="secondary" size="md">
                    {t("settings.advanced.corrections.cancel")}
                  </Button>
                </div>
              </div>
            )}
          </div>
        </SettingContainer>

        {corrections.length > 0 && (
          <div
            className={`px-4 p-2 ${grouped ? "" : "rounded-lg border border-mid-gray/20"} flex flex-col gap-1`}
          >
            {corrections.map((c) => (
              <div key={c.from} className="flex items-center gap-2 text-sm">
                <span className="font-mono text-mid-gray truncate max-w-40">
                  {c.from}
                </span>
                <ArrowRight className="w-3 h-3 shrink-0 text-mid-gray" />
                <span className="font-mono truncate max-w-40">{c.to}</span>
                <Button
                  onClick={() => remove(c.from)}
                  disabled={isUpdating("transcription_corrections")}
                  variant="secondary"
                  size="sm"
                  className="ml-auto inline-flex items-center"
                  aria-label={t("settings.advanced.corrections.remove", {
                    word: c.from,
                  })}
                >
                  <X className="w-3 h-3" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </>
    );
  };
