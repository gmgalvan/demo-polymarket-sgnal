import { COLORS, FONT_MONO, FONT_SANS } from "../theme";

/** The path a single log line takes, and where it stops.
 *
 * The teaching point is the fork near the end: `kubectl logs` reads the
 * file on the node through the kubelet, so it can only ever show you
 * what is still on that node. Delete or evict the Pod and those files go
 * with it. That is the whole argument for a node agent shipping lines
 * somewhere else while they still exist.
 *
 * Structure follows the CNCF practical logging guide and the Kubernetes
 * logging docs; drawn here rather than screenshotted.
 */

const C = {
  box: COLORS.panel,
  edge: "#2c3345",
  accent: COLORS.accent,
  text: COLORS.text,
  dim: COLORS.dim,
  bad: COLORS.bad,
  good: COLORS.good,
};

export function LogJourney() {
  return (
    <svg
      viewBox="0 0 1040 300"
      style={{ width: "100%", maxHeight: "330px", display: "block" }}
      role="img"
      aria-label="A log line travels from the application's stdout through the container runtime to files on the node, where kubectl logs reads it; a node agent ships it to a central backend before the Pod is deleted"
    >
      <defs>
        <marker id="lj" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.accent} />
        </marker>
        <marker id="ljGood" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.good} />
        </marker>
        <marker id="ljDim" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.dim} />
        </marker>
        <path id="logPath" d="M 148 76 L 838 76" fill="none" />
      </defs>

      {/* the node boundary: everything inside dies with the node */}
      <rect x={16} y={22} width={860} height={186} rx={10} fill="none" stroke={C.edge} strokeWidth="1.2" strokeDasharray="6 4" />
      <text x={30} y={42} fontSize="12.5" fill={C.dim} fontFamily={FONT_MONO} letterSpacing="0.06em">
        the node
      </text>

      <Box x={36} y={54} w={112} h={44} title="your app" sub="print / logger" />
      <Box x={214} y={54} w={132} h={44} title="stdout / stderr" mono />
      <Box x={412} y={54} w={148} h={44} title="container runtime" />
      <Box x={626} y={54} w={212} h={44} title="/var/log/containers" sub="files, rotated" mono />

      <Arrow d="M 148 76 L 212 76" />
      <Arrow d="M 346 76 L 410 76" />
      <Arrow d="M 560 76 L 624 76" />

      {/* down to kubectl logs - reads the file, nothing more */}
      <path d="M 732 98 L 732 142" fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#lj)" />
      <Box x={626} y={144} w={212} h={46} title="kubectl logs" sub="via the kubelet" mono accent />

      {/* the fork: ship it off the node while it still exists */}
      <path d="M 838 76 L 900 76 L 900 166 L 916 166" fill="none" stroke={C.good} strokeWidth="1.6" strokeDasharray="5 3" markerEnd="url(#ljGood)" />
      <text x={846} y={64} fontSize="11.5" fill={C.good} fontFamily={FONT_MONO}>
        node agent
      </text>

      <g>
        <rect x={918} y={142} width={108} height={48} rx={8} fill={C.box} stroke={C.good} strokeWidth="1.5" />
        <text x={972} y={163} fontSize="13" fill={C.good} fontFamily={FONT_MONO} textAnchor="middle">
          central
        </text>
        <text x={972} y={179} fontSize="11.5" fill={C.dim} fontFamily={FONT_SANS} textAnchor="middle">
          backend
        </text>
      </g>

      {/* the warning that makes the fork necessary */}
      <text x={36} y={240} fontSize="13" fill={C.bad} fontFamily={FONT_MONO}>
        Pod deleted or evicted
      </text>
      <path d="M 200 235 L 246 235" fill="none" stroke={C.bad} strokeWidth="1.4" markerEnd="url(#ljDim)" opacity="0.8" />
      <text x={254} y={240} fontSize="13" fill={C.dim} fontFamily={FONT_SANS}>
        the files go with it, and so does everything
        <tspan fill={C.accent} fontFamily={FONT_MONO}> kubectl logs </tspan>
        could ever have shown you.
      </text>

      {/* a line making the trip, drawn last so it rides over the boxes */}
      <circle r="4" fill={C.accent}>
        <animateMotion dur="5s" repeatCount="indefinite">
          <mpath href="#logPath" />
        </animateMotion>
      </circle>
    </svg>
  );
}

function Arrow({ d }: { d: string }) {
  return <path d={d} fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#lj)" />;
}

function Box({
  x,
  y,
  w,
  h,
  title,
  sub,
  mono = false,
  accent = false,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  title: string;
  sub?: string;
  mono?: boolean;
  accent?: boolean;
}) {
  const cx = x + w / 2;
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={8} fill={C.box} stroke={accent ? C.accent : C.edge} strokeWidth={accent ? 1.5 : 1.2} />
      <text
        x={cx}
        y={sub ? y + h / 2 - 1 : y + h / 2 + 5}
        fontSize="13.5"
        fill={accent ? C.accent : C.text}
        fontFamily={mono ? FONT_MONO : FONT_SANS}
        fontWeight={600}
        textAnchor="middle"
      >
        {title}
      </text>
      {sub && (
        <text x={cx} y={y + h / 2 + 15} fontSize="11.5" fill={C.dim} fontFamily={FONT_SANS} textAnchor="middle">
          {sub}
        </text>
      )}
    </g>
  );
}
