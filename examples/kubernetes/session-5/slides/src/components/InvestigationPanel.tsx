import { useState } from "react";
import { COLORS, FONT_MONO } from "../theme";
import { LiveTerminal, type TerminalRequest } from "./LiveTerminal";

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
};

export function InvestigationPanel({
  steps,
  terminalHeight = "52vh",
  leftWidth = "46%",
}: {
  steps: Step[];
  terminalHeight?: string;
  leftWidth?: string;
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
              setRequest({ command: step.command, nonce: Date.now() });
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
  return (
    <div
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick();
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
          marginBottom: "0.35rem",
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
    </div>
  );
}
