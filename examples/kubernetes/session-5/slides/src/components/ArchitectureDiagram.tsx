import { COLORS, FONT_MONO, FONT_SANS } from "../theme";

/** What's actually deployed. The nesting carries as much meaning as the
 * boxes: AWS ⊃ EKS ⊃ namespace, and the EBS volume is drawn OUTSIDE the
 * cluster on purpose - the volume outlives any Pod, node, or cluster.
 *
 * A dot travels the real request path on a loop. It is the one piece of
 * motion here and it teaches something: the order components are
 * touched, which is also the order you debug them in.
 *
 * LAYOUT RULES this geometry obeys (each one earned by a bug):
 *  - The ALB→Ingress arrow runs at x=423, to the RIGHT of every
 *    container title. Earlier it ran at x=278 and cut straight through
 *    "352-demo-dev-eks", "Graviton arm64" and "namespace: session-5".
 *  - Container titles are kept short for exactly that reason: the
 *    longest one now ends at x≈360, leaving a clear corridor.
 *  - Anything outside AWS stays left of x=160.
 *  - Per-hop captions ("proxy", "27017") were removed: they only fit in
 *    the 34px gaps between boxes, where they collided with the
 *    namespace border. The arrows say it without them.
 */

const C = {
  boundary: COLORS.border,
  box: COLORS.panel,
  boxEdge: "#2c3345",
  accent: COLORS.accent,
  text: COLORS.text,
  dim: COLORS.dim,
  good: COLORS.good,
};

/** Browser → ALB → Ingress → frontend → backend → mongo → volume. */
const REQUEST_PATH =
  "M 120 223 L 142 223 L 142 62 L 423 62 L 423 220 L 960 220 L 960 340";

export function ArchitectureDiagram() {
  return (
    <svg
      viewBox="0 0 1100 400"
      style={{ width: "100%", maxHeight: "430px", display: "block" }}
      role="img"
      aria-label="Architecture: a browser reaches an ALB, which routes through an Ingress to the frontend, backend and MongoDB inside the EKS session-5 namespace, with MongoDB backed by an EBS volume outside the cluster"
    >
      <defs>
        <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.accent} />
        </marker>
        <marker id="arrowGood" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.good} />
        </marker>
        <marker id="arrowDim" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 0 L 10 5 L 0 10 z" fill={C.dim} />
        </marker>
        <path id="requestPath" d={REQUEST_PATH} fill="none" />
        <radialGradient id="pulseGlow">
          <stop offset="0%" stopColor={C.accent} stopOpacity="0.55" />
          <stop offset="100%" stopColor={C.accent} stopOpacity="0" />
        </radialGradient>
      </defs>

      {/* ---- boundaries, outermost first ---- */}
      <Boundary x={160} y={8} w={932} h={376} label="AWS · us-east-1" />
      <Boundary x={180} y={112} w={892} h={178} label="EKS cluster" />
      <Boundary x={196} y={158} w={860} h={112} label="namespace: session-5" tight />

      {/* ---- outside AWS ----
          Labels sit BELOW the browser: above it they ran past the AWS
          border and the routing arrow's vertical leg cut through them. */}
      <Node x={8} y={196} w={112} h={54} title="Browser" />
      <text x={8} y={272} fontSize="11.5" fill={C.accent} fontFamily={FONT_MONO}>
        finance.example.com
      </text>
      <text x={8} y={289} fontSize="11.5" fill={C.dim} fontFamily={FONT_MONO}>
        Route 53 · A record
      </text>

      {/* browser → ALB, routed up the gutter left of the AWS border */}
      <path d="M 120 223 L 142 223 L 142 62 L 319 62" fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#arrow)" />

      <Node
        x={321}
        y={36}
        w={204}
        h={52}
        title="Application Load Balancer"
        sub="internet-facing · HTTPS"
        accent
        titleSize={14}
      />

      {/* ALB → Ingress: clear of every container title (all end by x≈360) */}
      <path d="M 423 88 L 423 188" fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#arrow)" />

      {/* ---- the workload row ---- */}
      <Node x={358} y={190} w={130} h={60} title="Ingress" mono />
      <Node x={522} y={190} w={145} h={60} title="frontend ×2" sub="nginx + React" />
      <Node x={701} y={190} w={155} h={60} title="backend ×2" sub="FastAPI + spaCy" />
      {/* ×1 with strategy: Recreate - an RWO EBS volume attaches to one
          node at a time, so a rolling update would deadlock on itself. */}
      <Node x={890} y={190} w={140} h={60} title="mongo ×1" sub="Recreate" />

      <Hop from={488} to={520} y={220} />
      <Hop from={667} to={699} y={220} />
      <Hop from={856} to={888} y={220} />

      {/* mongo → volume: crosses the namespace AND the cluster boundary,
          which is the entire point being made. */}
      <path d="M 960 250 L 960 316" fill="none" stroke={C.good} strokeWidth="1.6" strokeDasharray="5 3" markerEnd="url(#arrowGood)" />

      <Node x={850} y={318} w={220} h={48} title="EBS gp3 · 10Gi" sub="PVC via aws-ebs-csi-driver" good mono titleSize={14} />

      {/* ---- registry ----
          Forks to BOTH app Pods: both images live in ECR. mongo is
          excluded deliberately - it runs the public mongo:7 image. */}
      <Node x={581} y={318} w={210} h={48} title="ECR" sub="both images, multi-arch" mono titleSize={14} />
      <path d="M 686 316 L 686 302" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="4 3" />
      <path d="M 594 302 L 779 302" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="4 3" />
      <path d="M 594 302 L 594 252" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="4 3" markerEnd="url(#arrowDim)" />
      <path d="M 779 302 L 779 252" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="4 3" markerEnd="url(#arrowDim)" />

      {/* ---- the travelling request ----
          Drawn last so it passes over the boxes rather than under them.
          The glow leads, the dot follows, both on the same path. */}
      <circle r="13" fill="url(#pulseGlow)">
        <animateMotion dur="7s" repeatCount="indefinite" rotate="auto">
          <mpath href="#requestPath" />
        </animateMotion>
      </circle>
      <circle r="4.5" fill={C.accent}>
        <animateMotion dur="7s" repeatCount="indefinite" rotate="auto">
          <mpath href="#requestPath" />
        </animateMotion>
      </circle>
    </svg>
  );
}

function Hop({ from, to, y }: { from: number; to: number; y: number }) {
  return (
    <path
      d={`M ${from} ${y} L ${to} ${y}`}
      fill="none"
      stroke={C.accent}
      strokeWidth="1.6"
      markerEnd="url(#arrow)"
    />
  );
}

function Boundary({
  x,
  y,
  w,
  h,
  label,
  sub,
  tight = false,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  label: string;
  sub?: string;
  tight?: boolean;
}) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={10} fill="none" stroke={C.boundary} strokeWidth="1.2" strokeDasharray="6 4" />
      <text x={x + 14} y={y + 20} fontSize={tight ? 12.5 : 13.5} fill={C.dim} fontFamily={FONT_MONO} letterSpacing="0.06em">
        {label}
      </text>
      {sub && (
        <text x={x + 14} y={y + 37} fontSize="12" fill={C.dim} fontFamily={FONT_SANS} opacity={0.7}>
          {sub}
        </text>
      )}
    </g>
  );
}

function Node({
  x,
  y,
  w,
  h,
  title,
  sub,
  accent = false,
  good = false,
  mono = false,
  titleSize = 15,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  title: string;
  sub?: string;
  accent?: boolean;
  good?: boolean;
  mono?: boolean;
  titleSize?: number;
}) {
  const cx = x + w / 2;
  const edge = accent ? C.accent : good ? C.good : C.boxEdge;
  const titleColor = accent ? C.accent : good ? C.good : C.text;
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={8} fill={C.box} stroke={edge} strokeWidth={accent || good ? 1.5 : 1.2} />
      <text
        x={cx}
        y={sub ? y + h / 2 - 1 : y + h / 2 + 5}
        fontSize={titleSize}
        fill={titleColor}
        fontFamily={mono ? FONT_MONO : FONT_SANS}
        fontWeight={600}
        textAnchor="middle"
      >
        {title}
      </text>
      {sub && (
        <text x={cx} y={y + h / 2 + 17} fontSize="12" fill={C.dim} fontFamily={FONT_SANS} textAnchor="middle">
          {sub}
        </text>
      )}
    </g>
  );
}
