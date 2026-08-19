import { COLORS, FONT_MONO, FONT_SANS } from "../theme";

/** A left-to-right chain of labelled stages, for the two metrics
 * pipelines: kubelet → Metrics Server → metrics.k8s.io → kubectl top,
 * and component → /metrics → collector → dashboards.
 *
 * `outside` marks the stages that are NOT part of Kubernetes and have to
 * be installed separately. That distinction is the entire point of both
 * diagrams - neither Metrics Server nor Prometheus ships with a cluster.
 */

export type Stage = {
  label: string;
  sub?: string;
  /** Not part of Kubernetes: rendered dashed, in the "you install this" tone. */
  outside?: boolean;
  /** Present and working on this cluster right now. */
  ok?: boolean;
  /** Absent on this cluster - the broken link in the chain. */
  missing?: boolean;
};

export function Pipeline({ stages }: { stages: Stage[] }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "stretch",
        gap: "0.55rem",
        flexWrap: "wrap",
      }}
    >
      {stages.map((stage, i) => (
        <div key={stage.label} style={{ display: "contents" }}>
          <StageBox stage={stage} />
          {i < stages.length - 1 && (
            <div
              style={{
                display: "flex",
                alignItems: "center",
                color: COLORS.dim,
                fontSize: "1.25rem",
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

function StageBox({ stage }: { stage: Stage }) {
  const edge = stage.missing
    ? COLORS.bad
    : stage.ok
      ? COLORS.good
      : stage.outside
        ? COLORS.warn
        : COLORS.border;
  return (
    <div
      style={{
        flex: 1,
        minWidth: 0,
        background: COLORS.panel,
        border: `1px ${stage.outside || stage.missing ? "dashed" : "solid"} ${edge}`,
        borderRadius: "9px",
        padding: "0.7rem 0.8rem",
        textAlign: "center",
      }}
    >
      <div
        style={{
          fontFamily: FONT_MONO,
          fontSize: "0.9rem",
          color: stage.missing
            ? COLORS.bad
            : stage.ok
              ? COLORS.good
              : stage.outside
                ? COLORS.warn
                : COLORS.text,
          wordBreak: "break-word",
        }}
      >
        {stage.label}
      </div>
      {stage.sub && (
        <div
          style={{
            fontFamily: FONT_SANS,
            fontSize: "0.78rem",
            color: COLORS.dim,
            marginTop: "0.25rem",
          }}
        >
          {stage.sub}
        </div>
      )}
    </div>
  );
}
