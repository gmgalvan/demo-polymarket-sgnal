import { COLORS, FONT_MONO } from "../theme";

/** Separates the signals students routinely collapse into "monitoring".
 *
 * The rows deliberately mix sources: two come from the platform's record
 * of events, two are live measurements from the kubelet, and two are
 * declared configuration rather than measurement at all. That spread is
 * the lesson - "how much memory?" and "how much memory did we promise
 * it?" are different questions with different answers.
 *
 * CPU and memory are separate rows on purpose: they are measured
 * differently. CPU is a rate derived from a cumulative counter over a
 * window; memory is a working-set reading at an instant.
 *
 * Every command here was run against the real cluster before being put
 * on a slide.
 */

export type Row = {
  question: string;
  source: string;
  read: string;
  /** Live measurement, the platform's own record, or declared config. */
  kind: "record" | "measured" | "declared";
  command?: string;
};

const ROWS: Row[] = [
  {
    question: "What did the application say?",
    source: "container stdout / stderr",
    read: "kubectl logs",
    kind: "record",
    command: "kubectl -n session-5 logs deploy/api-spacy-finance --tail=30",
  },
  {
    question: "What did Kubernetes do to it?",
    source: "kubelet, scheduler, controllers",
    read: "describe → Events",
    kind: "record",
    command: "kubectl -n session-5 describe pod -l app=api-spacy-finance",
  },
  {
    question: "How much CPU is it burning?",
    source: "Metrics Server",
    read: "top · CPU(cores)",
    kind: "measured",
    command: "kubectl top pods -n session-5",
  },
  {
    question: "How much memory is it holding?",
    source: "Metrics Server",
    read: "top · MEMORY",
    kind: "measured",
    command: "kubectl top pods -n session-5",
  },
  {
    question: "What did we promise it?",
    source: "the Pod spec — not measured",
    read: "requests / limits",
    kind: "declared",
    command:
      "kubectl -n session-5 describe pod -l app=api-spacy-finance | grep -A4 Requests",
  },
  {
    question: "And the node overall?",
    source: "Metrics Server",
    read: "top · with a %",
    kind: "measured",
    command: "kubectl top nodes",
  },
  {
    question: "How much of the node is already spoken for?",
    source: "scheduler's accounting",
    read: "describe node",
    kind: "declared",
    // `describe nodes` plural needs no node name, which removes the
    // $(kubectl get nodes -o jsonpath=...) subshell entirely: same output,
    // less than half the characters, and nothing to read out loud.
    command: "kubectl describe nodes | grep -A6 'Allocated resources'",
  },
];

const TONE = {
  record: COLORS.accent,
  measured: COLORS.good,
  declared: COLORS.warn,
} as const;

export const KIND_LEGEND = [
  { kind: "record" as const, label: "what happened" },
  { kind: "measured" as const, label: "measured now" },
  { kind: "declared" as const, label: "declared, not measured" },
];

export function ObservabilityTaxonomy({
  onSelect,
  activeQuestion,
}: {
  /** Given, rows with a command become clickable and hand it back,
   *  turning the table from a reference into a launcher. */
  onSelect?: (row: Row) => void;
  activeQuestion?: string;
} = {}) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "0.32rem" }}>
      <Header interactive={Boolean(onSelect)} />
      {ROWS.map((row) => (
        <RowLine
          key={row.question}
          row={row}
          onSelect={onSelect}
          active={row.question === activeQuestion}
        />
      ))}
      <Legend />
    </div>
  );
}

/* Two columns, not three: this table now sits beside the terminal
   rather than above it, and "where it comes from" no longer has room of
   its own. It reads better stacked under the question anyway - source
   and question are one thought. */
const GRID = "1fr auto";

function Header({ interactive }: { interactive: boolean }) {
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: GRID,
        gap: "0.8rem",
        padding: "0 0.75rem 0.1rem",
        fontFamily: FONT_MONO,
        fontSize: "0.68rem",
        letterSpacing: "0.1em",
        textTransform: "uppercase",
        color: COLORS.dim,
        opacity: 0.7,
      }}
    >
      <span>{interactive ? "Click a question →" : "The question"}</span>
      <span>How you read it</span>
    </div>
  );
}

function Legend() {
  return (
    <div
      style={{
        display: "flex",
        gap: "1.2rem",
        padding: "0.35rem 0.9rem 0",
        fontFamily: FONT_MONO,
        fontSize: "0.7rem",
        color: COLORS.dim,
      }}
    >
      {KIND_LEGEND.map(({ kind, label }) => (
        <span key={kind} style={{ display: "flex", alignItems: "center", gap: "0.35rem" }}>
          <span
            style={{
              width: "10px",
              height: "3px",
              borderRadius: "2px",
              background: TONE[kind],
              display: "inline-block",
            }}
          />
          {label}
        </span>
      ))}
    </div>
  );
}

function RowLine({
  row,
  onSelect,
  active,
}: {
  row: Row;
  onSelect?: (row: Row) => void;
  active?: boolean;
}) {
  const accent = TONE[row.kind];
  const clickable = Boolean(onSelect && row.command);

  return (
    <div
      onClick={clickable ? () => onSelect?.(row) : undefined}
      role={clickable ? "button" : undefined}
      tabIndex={clickable ? 0 : undefined}
      onKeyDown={
        clickable
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                onSelect?.(row);
              }
            }
          : undefined
      }
      style={{
        display: "grid",
        gridTemplateColumns: GRID,
        gap: "0.8rem",
        alignItems: "center",
        padding: "0.4rem 0.75rem",
        borderRadius: "8px",
        background: active ? "rgba(79,140,255,0.14)" : COLORS.panel,
        border: `1px solid ${active ? COLORS.accent : COLORS.border}`,
        borderLeft: `3px solid ${accent}`,
        cursor: clickable ? "pointer" : "default",
        transition: "background 0.15s ease, border-color 0.15s ease",
        minWidth: 0,
      }}
    >
      <span style={{ minWidth: 0 }}>
        <span
          style={{
            display: "block",
            fontSize: "0.88rem",
            color: COLORS.text,
            lineHeight: 1.3,
          }}
        >
          {row.question}
        </span>
        <span
          style={{
            display: "block",
            fontSize: "0.73rem",
            color: COLORS.dim,
            marginTop: "0.05rem",
          }}
        >
          {row.source}
        </span>
      </span>
      <span
        style={{
          fontFamily: FONT_MONO,
          fontSize: "0.76rem",
          color: accent,
          whiteSpace: "nowrap",
        }}
      >
        {row.read}
      </span>
    </div>
  );
}
