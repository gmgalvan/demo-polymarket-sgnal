import { useState } from "react";
import { COLORS, FONT_MONO } from "../theme";
import { LiveTerminal, type TerminalRequest } from "./LiveTerminal";
import { setLastCopied } from "../clipboard";

/** The deck's investigation layout: numbered QUESTIONS on the left, a
 * real terminal on the right. Clicking a step expands the terminal with
 * that step's command typed at the prompt, unrun.
 *
 * Steps are labelled by the question they answer, not by command
 * category - "What does the cluster know?" beats "useful kubectl
 * commands", because the audience should leave with questions they can
 * ask, not a command list they'll forget.
 */

export type Step = {
  /** The question this step answers. */
  question: string;
  /** Real, runnable command. Never a command we haven't verified. */
  command: string;
  /** What the presenter should point out in the output. */
  expect?: string;
  /** Copy to the clipboard instead of typing into the deck's terminal.
   *
   * For commands that do not return: `port-forward`, `logs -f`, `top`.
   * Running one of those in the embedded terminal occupies the single
   * console the rest of the demo depends on, and recovering from that
   * live means Ctrl+C in front of the room. These are meant to be
   * pasted into a second terminal instead, so the deck's own stays
   * free. */
  copyOnly?: boolean;
  /** A URL this step makes reachable, rendered as a button that opens in
   * a new tab. Paired with copyOnly: the command opens the tunnel in
   * another terminal, this opens what is now on the other end of it. */
  link?: { href: string; label: string };
};

export function InvestigationPanel({
  steps,
  terminalHeight = "52vh",
  leftWidth = "46%",
  onStepChange,
}: {
  steps: Step[];
  terminalHeight?: string;
  leftWidth?: string;
  /** Fires with the index of the step just clicked, so a slide can react
   * to where the investigation has got to - see CollectorPipeline, which
   * uses it to redraw its diagram once the install step is reached. */
  onStepChange?: (index: number) => void;
}) {
  const [request, setRequest] = useState<TerminalRequest | undefined>();
  const [active, setActive] = useState<number>();

  return (
    <div
      style={{
        display: "flex",
        gap: "1.4rem",
        alignItems: "stretch",
        height: terminalHeight,
      }}
    >
      <div
        style={{
          flex: `0 0 ${leftWidth}`,
          minWidth: 0,
          display: "flex",
          flexDirection: "column",
          gap: "0.5rem",
          overflowY: "auto",
        }}
      >
        {steps.map((step, i) => (
          <StepCard
            key={step.question}
            index={i}
            step={step}
            active={active === i}
            onClick={() => {
              setActive(i);
              // copyOnly steps deliberately never reach the terminal.
              if (!step.copyOnly) {
                setRequest({ command: step.command, nonce: Date.now() });
              }
              onStepChange?.(i);
            }}
          />
        ))}
      </div>
      <div style={{ flex: "1 1 auto", minWidth: 0 }}>
        <LiveTerminal height="100%" request={request} />
      </div>
    </div>
  );
}

function StepCard({
  index,
  step,
  active,
  onClick,
}: {
  index: number;
  step: Step;
  active: boolean;
  onClick: () => void;
}) {
  const [copied, setCopied] = useState(false);

  async function handleClick() {
    if (step.copyOnly) {
      // Recorded even if the write below fails, so LiveTerminal's
      // right-click paste can still produce it.
      setLastCopied(step.command);
      try {
        await navigator.clipboard.writeText(step.command);
      } catch {
        // Clipboard blocked - the fallback above covers it.
      }
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    }
    onClick();
  }

  return (
    <div
      onClick={handleClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          handleClick();
        }
      }}
      style={{
        background: active ? "rgba(79,140,255,0.12)" : COLORS.panel,
        border: `1px solid ${active ? COLORS.accent : COLORS.border}`,
        borderRadius: "9px",
        padding: "0.6rem 0.8rem",
        cursor: "pointer",
        transition: "background 0.15s ease, border-color 0.15s ease",
      }}
    >
      <div
        style={{
          display: "flex",
          gap: "0.6rem",
          alignItems: "baseline",
          justifyContent: "space-between",
          marginBottom: "0.35rem",
        }}
      >
        <span
          style={{
            display: "flex",
            gap: "0.6rem",
            alignItems: "baseline",
            minWidth: 0,
          }}
        >
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: "0.72rem",
              color: active ? COLORS.accent : COLORS.dim,
            }}
          >
            {String(index + 1).padStart(2, "0")}
          </span>
          <span style={{ fontSize: "0.95rem", color: COLORS.text }}>
            {step.question}
          </span>
        </span>
        {step.copyOnly && (
          <span
            style={{
              flex: "0 0 auto",
              fontFamily: FONT_MONO,
              fontSize: "0.68rem",
              color: copied ? COLORS.good : COLORS.warn,
              border: `1px solid ${copied ? COLORS.good : COLORS.border}`,
              borderRadius: "5px",
              padding: "0.1rem 0.4rem",
              whiteSpace: "nowrap",
              transition: "color 0.15s ease, border-color 0.15s ease",
            }}
          >
            {copied ? "✓ copied" : "⧉ other terminal"}
          </span>
        )}
      </div>
      <code
        style={{
          display: "block",
          fontFamily: FONT_MONO,
          fontSize: "0.78rem",
          color: COLORS.accent,
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          lineHeight: 1.45,
        }}
      >
        {step.command}
      </code>
      {step.expect && (
        <div
          style={{
            fontSize: "0.75rem",
            color: COLORS.dim,
            marginTop: "0.3rem",
          }}
        >
          {step.expect}
        </div>
      )}
      {step.link && (
        <a
          href={step.link.href}
          target="_blank"
          rel="noreferrer"
          // Without this the card's own handler also fires, re-copying
          // the command and stealing focus as the new tab opens.
          onClick={(e) => e.stopPropagation()}
          style={{
            display: "inline-flex",
            alignItems: "center",
            gap: "0.35rem",
            marginTop: "0.45rem",
            padding: "0.2rem 0.55rem",
            fontFamily: FONT_MONO,
            fontSize: "0.76rem",
            color: COLORS.accent,
            border: `1px solid ${COLORS.accent}`,
            borderRadius: "6px",
            textDecoration: "none",
          }}
        >
          ↗ {step.link.label}
        </a>
      )}
    </div>
  );
}
