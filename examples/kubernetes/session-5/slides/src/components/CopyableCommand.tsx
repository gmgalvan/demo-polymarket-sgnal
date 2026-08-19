import { useState } from "react";
import { COLORS, FONT_MONO } from "../theme";
import { setLastCopied } from "../clipboard";

/** A single shell command, click-to-copy. Built for the live-demo slide:
 * during a talk, clicking beats select-and-drag under pressure. Also
 * records the text so <LiveTerminal>'s right-click paste can use it
 * even if the browser blocks clipboard reads. */
export function CopyableCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    setLastCopied(command);
    try {
      await navigator.clipboard.writeText(command);
    } catch {
      // Clipboard write unavailable - right-click paste still works via
      // the module-scope fallback set above.
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <button
      onClick={handleCopy}
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: "0.9rem",
        width: "100%",
        margin: "0 0 0.55rem 0",
        padding: "0.6rem 0.9rem",
        background: copied ? "rgba(53, 212, 136, 0.06)" : "#05070c",
        border: `1px solid ${copied ? COLORS.good : COLORS.border}`,
        borderRadius: "8px",
        cursor: "pointer",
        textAlign: "left",
        transition: "border-color 0.15s ease, background 0.15s ease",
      }}
    >
      <code
        style={{
          fontFamily: FONT_MONO,
          fontSize: "0.98rem",
          lineHeight: 1.45,
          color: COLORS.text,
          // Wrap instead of scrolling: a horizontal scrollbar inside a
          // slide is unusable from three metres away, and these commands
          // are long enough to need one at this width.
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          minWidth: 0,
        }}
      >
        {command}
      </code>
      <span
        style={{
          flexShrink: 0,
          fontFamily: FONT_MONO,
          fontSize: "0.72rem",
          color: copied ? COLORS.good : COLORS.dim,
          minWidth: "4rem",
          textAlign: "right",
        }}
      >
        {copied ? "✓ copied" : "copy"}
      </span>
    </button>
  );
}
