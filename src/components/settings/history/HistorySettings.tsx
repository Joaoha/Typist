import React, { useCallback, useEffect, useRef, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import { readFile } from "@tauri-apps/plugin-fs";
import {
  ArrowRight,
  BookPlus,
  Check,
  Copy,
  FolderOpen,
  RotateCcw,
  Star,
  Trash2,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { toast } from "sonner";
import {
  commands,
  events,
  type HistoryEntry,
  type HistoryUpdatePayload,
  type PhraseCorrection,
} from "@/bindings";
import { useOsType } from "@/hooks/useOsType";
import { useSettings } from "@/hooks/useSettings";
import { formatDateTime } from "@/utils/dateFormat";
import { AudioPlayer } from "../../ui/AudioPlayer";
import { Button } from "../../ui/Button";
import { Input } from "../../ui/Input";

const IconButton: React.FC<{
  onClick: () => void;
  title: string;
  disabled?: boolean;
  active?: boolean;
  children: React.ReactNode;
}> = ({ onClick, title, disabled, active, children }) => (
  <button
    onClick={onClick}
    disabled={disabled}
    className={`p-1.5 rounded-md flex items-center justify-center transition-colors cursor-pointer disabled:cursor-not-allowed disabled:text-text/20 ${
      active
        ? "text-logo-primary hover:text-logo-primary/80"
        : "text-text/50 hover:text-logo-primary"
    }`}
    title={title}
  >
    {children}
  </button>
);

const PAGE_SIZE = 30;

interface OpenRecordingsButtonProps {
  onClick: () => void;
  label: string;
}

const OpenRecordingsButton: React.FC<OpenRecordingsButtonProps> = ({
  onClick,
  label,
}) => (
  <Button
    onClick={onClick}
    variant="secondary"
    size="sm"
    className="flex items-center gap-2"
    title={label}
  >
    <FolderOpen className="w-4 h-4" />
    <span>{label}</span>
  </Button>
);

export const HistorySettings: React.FC = () => {
  const { t } = useTranslation();
  const osType = useOsType();
  const [entries, setEntries] = useState<HistoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [hasMore, setHasMore] = useState(true);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const entriesRef = useRef<HistoryEntry[]>([]);
  const loadingRef = useRef(false);

  // Keep ref in sync for use in IntersectionObserver callback
  useEffect(() => {
    entriesRef.current = entries;
  }, [entries]);

  const loadPage = useCallback(async (cursor?: number) => {
    const isFirstPage = cursor === undefined;
    if (!isFirstPage && loadingRef.current) return;
    loadingRef.current = true;

    if (isFirstPage) setLoading(true);

    try {
      const result = await commands.getHistoryEntries(
        cursor ?? null,
        PAGE_SIZE,
      );
      if (result.status === "ok") {
        const { entries: newEntries, has_more } = result.data;
        setEntries((prev) =>
          isFirstPage ? newEntries : [...prev, ...newEntries],
        );
        setHasMore(has_more);
      }
    } catch (error) {
      console.error("Failed to load history entries:", error);
    } finally {
      setLoading(false);
      loadingRef.current = false;
    }
  }, []);

  // Initial load
  useEffect(() => {
    loadPage();
  }, [loadPage]);

  // Infinite scroll via IntersectionObserver
  useEffect(() => {
    if (loading) return;

    const sentinel = sentinelRef.current;
    if (!sentinel || !hasMore) return;

    const observer = new IntersectionObserver(
      (observerEntries) => {
        const first = observerEntries[0];
        if (first.isIntersecting) {
          const lastEntry = entriesRef.current[entriesRef.current.length - 1];
          if (lastEntry) {
            loadPage(lastEntry.id);
          }
        }
      },
      { threshold: 0 },
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [loading, hasMore, loadPage]);

  // Listen for new entries added from the transcription pipeline
  useEffect(() => {
    const unlisten = events.historyUpdatePayload.listen((event) => {
      const payload: HistoryUpdatePayload = event.payload;
      if (payload.action === "added") {
        setEntries((prev) => [payload.entry, ...prev]);
      } else if (payload.action === "updated") {
        setEntries((prev) =>
          prev.map((e) => (e.id === payload.entry.id ? payload.entry : e)),
        );
      }
      // "deleted" and "toggled" are handled by optimistic updates only,
      // so we intentionally ignore them here to avoid double-mutation.
    });

    return () => {
      unlisten.then((fn) => fn());
    };
  }, []);

  const toggleSaved = async (id: number) => {
    // Optimistic update
    setEntries((prev) =>
      prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
    );
    try {
      const result = await commands.toggleHistoryEntrySaved(id);
      if (result.status !== "ok") {
        // Revert on failure
        setEntries((prev) =>
          prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
        );
      }
    } catch (error) {
      console.error("Failed to toggle saved status:", error);
      // Revert on failure
      setEntries((prev) =>
        prev.map((e) => (e.id === id ? { ...e, saved: !e.saved } : e)),
      );
    }
  };

  const copyToClipboard = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
    } catch (error) {
      console.error("Failed to copy to clipboard:", error);
    }
  };

  const getAudioUrl = useCallback(
    async (fileName: string) => {
      try {
        const result = await commands.getAudioFilePath(fileName);
        if (result.status === "ok") {
          if (osType === "linux") {
            const fileData = await readFile(result.data);
            const blob = new Blob([fileData], { type: "audio/wav" });
            return URL.createObjectURL(blob);
          }
          return convertFileSrc(result.data, "asset");
        }
        return null;
      } catch (error) {
        console.error("Failed to get audio file path:", error);
        return null;
      }
    },
    [osType],
  );

  const deleteAudioEntry = async (id: number) => {
    // Optimistically remove
    setEntries((prev) => prev.filter((e) => e.id !== id));
    try {
      const result = await commands.deleteHistoryEntry(id);
      if (result.status !== "ok") {
        // Reload on failure
        loadPage();
      }
    } catch (error) {
      console.error("Failed to delete entry:", error);
      loadPage();
    }
  };

  const retryHistoryEntry = async (id: number) => {
    const result = await commands.retryHistoryEntryTranscription(id);
    if (result.status !== "ok") {
      throw new Error(String(result.error));
    }
  };

  const openRecordingsFolder = async () => {
    try {
      const result = await commands.openRecordingsFolder();
      if (result.status !== "ok") {
        throw new Error(String(result.error));
      }
    } catch (error) {
      console.error("Failed to open recordings folder:", error);
    }
  };

  let content: React.ReactNode;

  if (loading) {
    content = (
      <div className="px-4 py-3 text-center text-text/60">
        {t("settings.history.loading")}
      </div>
    );
  } else if (entries.length === 0) {
    content = (
      <div className="px-4 py-3 text-center text-text/60">
        {t("settings.history.empty")}
      </div>
    );
  } else {
    content = (
      <>
        <div className="divide-y divide-mid-gray/20">
          {entries.map((entry) => (
            <HistoryEntryComponent
              key={entry.id}
              entry={entry}
              onToggleSaved={() => toggleSaved(entry.id)}
              onCopyText={() => copyToClipboard(entry.transcription_text)}
              getAudioUrl={getAudioUrl}
              deleteAudio={deleteAudioEntry}
              retryTranscription={retryHistoryEntry}
            />
          ))}
        </div>
        {/* Sentinel for infinite scroll */}
        <div ref={sentinelRef} className="h-1" />
      </>
    );
  }

  return (
    <div className="max-w-3xl w-full mx-auto space-y-6">
      <div className="space-y-2">
        <div className="px-4 flex items-center justify-between">
          <div>
            <h2 className="text-xs font-medium text-mid-gray uppercase tracking-wide">
              {t("settings.history.title")}
            </h2>
          </div>
          <OpenRecordingsButton
            onClick={openRecordingsFolder}
            label={t("settings.history.openFolder")}
          />
        </div>
        <div className="bg-background border border-mid-gray/20 rounded-lg overflow-visible">
          {content}
        </div>
      </div>
    </div>
  );
};

interface HistoryEntryProps {
  entry: HistoryEntry;
  onToggleSaved: () => void;
  onCopyText: () => void;
  getAudioUrl: (fileName: string) => Promise<string | null>;
  deleteAudio: (id: number) => Promise<void>;
  retryTranscription: (id: number) => Promise<void>;
}

const HistoryEntryComponent: React.FC<HistoryEntryProps> = ({
  entry,
  onToggleSaved,
  onCopyText,
  getAudioUrl,
  deleteAudio,
  retryTranscription,
}) => {
  const { t, i18n } = useTranslation();
  const { getSetting, updateSetting } = useSettings();
  const [showCopied, setShowCopied] = useState(false);
  const [retrying, setRetrying] = useState(false);
  const [showAdder, setShowAdder] = useState(false);
  const [fromText, setFromText] = useState("");
  const [toText, setToText] = useState("");

  const hasTranscription = entry.transcription_text.trim().length > 0;
  // The cleaned (post-processed) text is what got pasted; show it alongside the
  // original so the original mistranscription stays visible and teachable.
  const cleaned = entry.post_processed_text?.trim() ?? "";
  const hasCleaned = cleaned.length > 0 && cleaned !== entry.transcription_text.trim();

  // Distinct word tokens from the original transcription, for quick "tap to grab".
  const tokens = Array.from(
    new Set(
      entry.transcription_text
        .split(/\s+/)
        .map((w) => w.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ""))
        .filter((w) => w.length > 0),
    ),
  );

  const customWords = (getSetting("custom_words") || []) as string[];
  const corrections = (getSetting("transcription_corrections") ||
    []) as PhraseCorrection[];

  // Tapping a token (from the original) builds the "Heard" phrase.
  const appendHeard = (tok: string) => {
    setFromText((prev) => (prev.trim() ? `${prev.trim()} ${tok}` : tok));
  };

  // Add the corrected word to the fuzzy Custom Words list.
  const addWord = () => {
    const word = toText.trim().replace(/[<>"'&]/g, "");
    if (!word || word.includes(" ") || word.length > 50) return;
    if (customWords.some((w) => w.toLowerCase() === word.toLowerCase())) {
      toast.error(t("settings.history.dictionary.duplicate", { word }));
      return;
    }
    updateSetting("custom_words", [...customWords, word]);
    toast.success(t("settings.history.dictionary.added", { word }));
  };

  // Save an exact (heard -> meant) correction, reusing the mistranscription as
  // the "from" — same store the "record a correction" flow writes to.
  const saveCorrection = () => {
    const from = fromText.trim();
    const to = toText.trim();
    if (!from || !to) return;
    if (corrections.some((c) => c.from.toLowerCase() === from.toLowerCase())) {
      toast.error(
        t("settings.history.dictionary.correctionDuplicate", { from }),
      );
      return;
    }
    updateSetting("transcription_corrections", [...corrections, { from, to }]);
    toast.success(
      t("settings.history.dictionary.correctionAdded", { from, to }),
    );
    setFromText("");
    setToText("");
  };

  const handleLoadAudio = useCallback(
    () => getAudioUrl(entry.file_name),
    [getAudioUrl, entry.file_name],
  );

  const handleCopyText = () => {
    if (!hasTranscription) {
      return;
    }

    onCopyText();
    setShowCopied(true);
    setTimeout(() => setShowCopied(false), 2000);
  };

  const handleDeleteEntry = async () => {
    try {
      await deleteAudio(entry.id);
    } catch (error) {
      console.error("Failed to delete entry:", error);
      toast.error(t("settings.history.deleteError"));
    }
  };

  const handleRetranscribe = async () => {
    try {
      setRetrying(true);
      await retryTranscription(entry.id);
    } catch (error) {
      console.error("Failed to re-transcribe:", error);
      toast.error(t("settings.history.retranscribeError"));
    } finally {
      setRetrying(false);
    }
  };

  const formattedDate = formatDateTime(String(entry.timestamp), i18n.language);

  return (
    <div className="px-4 py-2 pb-5 flex flex-col gap-3">
      <div className="flex justify-between items-center">
        <p className="text-sm font-medium">{formattedDate}</p>
        <div className="flex items-center">
          <IconButton
            onClick={handleCopyText}
            disabled={!hasTranscription || retrying}
            title={t("settings.history.copyToClipboard")}
          >
            {showCopied ? (
              <Check width={16} height={16} />
            ) : (
              <Copy width={16} height={16} />
            )}
          </IconButton>
          <IconButton
            onClick={() => setShowAdder((v) => !v)}
            disabled={!hasTranscription || retrying}
            active={showAdder}
            title={t("settings.history.dictionary.title")}
          >
            <BookPlus width={16} height={16} />
          </IconButton>
          <IconButton
            onClick={onToggleSaved}
            disabled={retrying}
            active={entry.saved}
            title={
              entry.saved
                ? t("settings.history.unsave")
                : t("settings.history.save")
            }
          >
            <Star
              width={16}
              height={16}
              fill={entry.saved ? "currentColor" : "none"}
            />
          </IconButton>
          <IconButton
            onClick={handleRetranscribe}
            disabled={retrying}
            title={t("settings.history.retranscribe")}
          >
            <RotateCcw
              width={16}
              height={16}
              style={
                retrying
                  ? { animation: "spin 1s linear infinite reverse" }
                  : undefined
              }
            />
          </IconButton>
          <IconButton
            onClick={handleDeleteEntry}
            disabled={retrying}
            title={t("settings.history.delete")}
          >
            <Trash2 width={16} height={16} />
          </IconButton>
        </div>
      </div>

      {hasCleaned && !retrying && (
        <span className="-mb-2 text-[10px] font-semibold uppercase tracking-wide text-mid-gray">
          {t("settings.history.originalLabel")}
        </span>
      )}
      <p
        className={`italic text-sm pb-2 ${
          retrying
            ? ""
            : hasTranscription
              ? "text-text/90 select-text cursor-text whitespace-pre-wrap break-words"
              : "text-text/40"
        }`}
        style={
          retrying
            ? { animation: "transcribe-pulse 3s ease-in-out infinite" }
            : undefined
        }
      >
        {retrying && (
          <style>{`
            @keyframes transcribe-pulse {
              0%, 100% { color: color-mix(in srgb, var(--color-text) 40%, transparent); }
              50% { color: color-mix(in srgb, var(--color-text) 90%, transparent); }
            }
          `}</style>
        )}
        {retrying
          ? t("settings.history.transcribing")
          : hasTranscription
            ? entry.transcription_text
            : t("settings.history.transcriptionFailed")}
      </p>

      {hasCleaned && !retrying && (
        <div className="-mt-1">
          <span className="text-[10px] font-semibold uppercase tracking-wide text-mid-gray">
            {t("settings.history.cleanedLabel")}
          </span>
          <p className="text-sm text-text/90 select-text whitespace-pre-wrap break-words">
            {cleaned}
          </p>
        </div>
      )}

      {showAdder && hasTranscription && (
        <div className="flex flex-col gap-3 rounded-lg border border-mid-gray/20 p-3">
          <p className="text-xs text-mid-gray">
            {t("settings.history.dictionary.hint")}
          </p>
          <div className="flex flex-wrap gap-1">
            {tokens.map((tok) => (
              <button
                key={tok}
                onClick={() => appendHeard(tok)}
                className="px-1.5 py-0.5 rounded bg-mid-gray/15 hover:bg-logo-primary/30 text-xs font-mono cursor-pointer transition-colors"
              >
                {tok}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <Input
              type="text"
              value={fromText}
              onChange={(e) => setFromText(e.target.value)}
              placeholder={t("settings.history.dictionary.heardPlaceholder")}
              variant="compact"
              className="max-w-40"
            />
            <ArrowRight className="w-4 h-4 shrink-0 text-mid-gray" />
            <Input
              type="text"
              value={toText}
              onChange={(e) => setToText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  if (fromText.trim() && toText.trim()) saveCorrection();
                }
              }}
              placeholder={t("settings.history.dictionary.correctPlaceholder")}
              variant="compact"
              className="max-w-40"
            />
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <Button
              onClick={saveCorrection}
              disabled={!fromText.trim() || !toText.trim()}
              variant="primary"
              size="md"
            >
              {t("settings.history.dictionary.saveCorrection")}
            </Button>
            <Button
              onClick={addWord}
              disabled={
                !toText.trim() ||
                toText.includes(" ") ||
                toText.trim().length > 50
              }
              variant="secondary"
              size="md"
            >
              {t("settings.history.dictionary.addWord")}
            </Button>
          </div>
        </div>
      )}

      <AudioPlayer onLoadRequest={handleLoadAudio} className="w-full" />
    </div>
  );
};
