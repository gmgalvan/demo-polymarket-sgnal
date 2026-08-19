import { COLORS, FONT_MONO } from "../theme";

/** The three-stage troubleshooting decision tree from
 * learnkube.com/troubleshooting-deployments, redrawn to match the deck.
 *
 * Data-driven so the same diagram can be rendered twice: once as the
 * general map, and once with our two real incidents highlighted, without
 * the two copies drifting apart.
 */

type FailureNode = {
  id: string;
  state: string;
  cause: string;
};

type Stage = {
  n: string;
  title: string;
  entry: string;
  question: string;
  failures: FailureNode[];
};

const STAGES: Stage[] = [
  {
    n: "1",
    title: "POD",
    entry: "kubectl get pods",
    question: "Running AND Ready?",
    failures: [
      {
        id: "pending",
        state: "Pending",
        cause: "no CPU/memory · quota · unbound PVC",
      },
      {
        id: "image",
        state: "ImagePullBackOff",
        cause: "bad image name/tag · missing registry creds",
      },
      {
        id: "crashloop",
        state: "CrashLoopBackOff",
        cause: "app startup error · failing liveness probe",
      },
      {
        id: "notready",
        state: "Running, not Ready",
        cause: "readiness probe failing",
      },
    ],
  },
  {
    n: "2",
    title: "SERVICE",
    entry: "kubectl describe service",
    question: "Any Endpoints listed?",
    failures: [
      {
        id: "noendpoints",
        state: "Endpoints: <none>",
        cause: "Service selector ≠ Pod labels",
      },
      {
        id: "portmismatch",
        state: "Endpoints, but no reply",
        cause: "targetPort ≠ containerPort",
      },
    ],
  },
  {
    n: "3",
    title: "INGRESS",
    entry: "kubectl describe ingress",
    question: "Backend resolved?",
    failures: [
      {
        id: "nobackend",
        state: "Backend empty",
        cause: "service name/port ≠ the Service",
      },
      {
        id: "controller",
        state: "Backend set, no reply",
        cause: "controller or infra — port-forward it to tell which",
      },
    ],
  },
];

export function TroubleshootFlow({
  highlight = [],
}: {
  /** Failure node ids to spotlight; everything else dims. Empty = plain map. */
  highlight?: string[];
}) {
  const spotlighting = highlight.length > 0;

  return (
    <div style={{ display: "flex", alignItems: "stretch", gap: "0.5rem" }}>
      {STAGES.map((stage, i) => (
        <div key={stage.n} style={{ display: "contents" }}>
          <StageColumn
            stage={stage}
            highlight={highlight}
            spotlighting={spotlighting}
          />
          {i < STAGES.length - 1 && (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                color: COLORS.dim,
                fontSize: "1.5rem",
                opacity: spotlighting ? 0.3 : 1,
              }}
            >
              →
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

function StageColumn({
  stage,
  highlight,
  spotlighting,
}: {
  stage: Stage;
  highlight: string[];
  spotlighting: boolean;
}) {
  const stageDim = spotlighting && !stage.failures.some((f) => highlight.includes(f.id));

  return (
    <div
      style={{
        flex: 1,
        minWidth: 0,
        display: "flex",
        flexDirection: "column",
        gap: "0.45rem",
        opacity: stageDim ? 0.35 : 1,
        transition: "opacity 0.2s ease",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: "0.7rem",
            color: COLORS.bg,
            background: COLORS.accent,
            borderRadius: "4px",
            padding: "0.1rem 0.42rem",
            fontWeight: 700,
          }}
        >
          {stage.n}
        </span>
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: "0.9rem",
            color: COLORS.text,
            letterSpacing: "0.08em",
            fontWeight: 700,
          }}
        >
          {stage.title}
        </span>
      </div>

      <div
        style={{
          fontFamily: FONT_MONO,
          fontSize: "0.74rem",
          color: COLORS.accent,
          background: COLORS.accentSoft,
          border: `1px solid ${COLORS.border}`,
          borderRadius: "6px",
          padding: "0.3rem 0.55rem",
          whiteSpace: "nowrap",
          overflow: "hidden",
          textOverflow: "ellipsis",
        }}
      >
        {stage.entry}
      </div>

      <div
        style={{
          fontSize: "0.82rem",
          color: COLORS.text,
          padding: "0.1rem 0.1rem 0.15rem",
        }}
      >
        {stage.question}
      </div>

      {stage.failures.map((failure) => (
        <FailureCard
          key={failure.id}
          failure={failure}
          lit={highlight.includes(failure.id)}
          spotlighting={spotlighting}
        />
      ))}
    </div>
  );
}

function FailureCard({
  failure,
  lit,
  spotlighting,
}: {
  failure: FailureNode;
  lit: boolean;
  spotlighting: boolean;
}) {
  return (
    <div
      style={{
        border: `1px solid ${lit ? COLORS.accent : "rgba(255, 93, 108, 0.3)"}`,
        background: lit ? "rgba(79, 140, 255, 0.14)" : COLORS.panel,
        borderRadius: "7px",
        padding: "0.4rem 0.6rem",
        opacity: spotlighting && !lit ? 0.4 : 1,
        boxShadow: lit ? `0 0 0 2px rgba(79, 140, 255, 0.25)` : "none",
        transition: "opacity 0.2s ease",
      }}
    >
      <div
        style={{
          fontFamily: FONT_MONO,
          fontSize: "0.76rem",
          color: lit ? COLORS.accent : COLORS.bad,
          marginBottom: "0.12rem",
        }}
      >
        {failure.state}
      </div>
      <div style={{ fontSize: "0.72rem", color: COLORS.dim, lineHeight: 1.35 }}>
        {failure.cause}
      </div>
    </div>
  );
}
