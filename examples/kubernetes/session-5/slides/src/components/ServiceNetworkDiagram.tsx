import { useEffect, useState } from "react";
import { COLORS, FONT_MONO, FONT_SANS } from "../theme";

/** What is actually involved when one Pod calls another by Service name,
 * walked one leg at a time.
 *
 * Four pieces, three of which nobody mentions until they break:
 *  - CoreDNS turns the name into a ClusterIP. It lives in the control
 *    plane, not on the node.
 *  - The Service is a virtual IP. There is no process behind it - which
 *    is why you cannot ssh to it, ping it usefully, or read its logs.
 *  - kube-proxy is what makes that virtual IP mean anything: it watches
 *    Services and Endpoints and programs the node's packet-filter rules.
 *    Drawn ABOVE the Service and receiving an arrow FROM it, because it
 *    reacts to the Service object rather than sitting in the data path.
 *  - The CNI plugin gave each Pod its IP and its network namespace in
 *    the first place - the dash-dot circles.
 *
 * The stepping is presenter-driven rather than a timed loop, because the
 * captions are things to be said out loud and rooms move at different
 * speeds. `play` exists for rehearsal and stops at the last step instead
 * of cycling, so it can never race ahead of you mid-sentence.
 *
 * LAYOUT RULES (same discipline as ArchitectureDiagram):
 *  - The viewBox is deliberately squat (1000x470, ratio 2.13). Height is
 *    what limits this drawing on a slide, so vertical air costs width:
 *    every 40px of viewBox height trimmed makes the rendered diagram
 *    wider at the same maxHeight. Do not "give it room to breathe".
 *  - Boundary labels sit at y+24 and every child box starts below that,
 *    so no title is ever crossed by a box edge. Tightest margin is 10px
 *    (CoreDNS to the control-plane floor).
 *  - The CNI dotted paths drop at x=250 and x=750, which are 65px from
 *    the circle centres - just outside r=62. Clearance here is
 *    horizontal, not vertical: at y=414 the circles are still very much
 *    in range, they are simply narrower than the line is far out.
 *  - The Pod→Service arrows start 70px from those centres, so they leave
 *    the namespace boundary rather than crossing it.
 *  - The DNS leg climbs at x=185: left of every box (all start at
 *    x>=380) and right of the "Worker node" label (ends at x~141). It
 *    does cross Pod A's namespace circle, which is the one crossing that
 *    is meant to happen - the query leaves the namespace.
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

/** Opacity applied to everything not involved in the current step. Low
 * enough to recede from the back of a room, high enough that the shape
 * of the whole system stays readable. */
const MUTED = 0.22;

type Step = {
  id: string;
  chip: string;
  /** Boxes lit for this step. */
  lit: string[];
  /** Path(s) the packet travels, in SVG path syntax. */
  legs: string[];
  /** Said out loud while this step is on screen. */
  caption: string;
};

const STEPS: Step[] = [
  {
    id: "dns",
    chip: "1 · resolve",
    lit: ["podA", "coredns"],
    legs: ["M 185 342 L 185 99 L 391 99"],
    caption:
      "Pod A asks for a name. CoreDNS answers with a ClusterIP — and CoreDNS is a Deployment like any other, so it can be down, slow, or misconfigured.",
  },
  {
    id: "rules",
    chip: "2 · program",
    lit: ["service", "kubeproxy"],
    legs: ["M 500 264 L 500 238"],
    caption:
      "This already happened. kube-proxy watches Services and Endpoints and writes the node's packet rules ahead of time — it is not a hop the packet takes.",
  },
  {
    id: "send",
    chip: "3 · send",
    lit: ["podA", "service"],
    legs: ["M 250 340 L 378 316"],
    caption:
      "Pod A sends to the ClusterIP. Nothing is listening on that address — no process, no container, no logs. It is a virtual IP.",
  },
  {
    id: "rewrite",
    chip: "4 · rewrite",
    lit: ["service", "podB"],
    legs: ["M 622 316 L 750 340"],
    caption:
      "The node's rules rewrite the destination to one real Pod IP, picked from the Endpoints list. That rewrite is the entire Service. Empty list, nowhere to go — that was bug 2.",
  },
  {
    id: "cni",
    chip: "5 · addresses",
    lit: ["podA", "podB", "cni"],
    legs: ["M 403 414 L 250 414 L 250 390", "M 597 414 L 750 414 L 750 390"],
    caption:
      "None of it works without the CNI plugin, which gave each Pod its own network namespace and the IP everything above is routing to.",
  },
];

export function ServiceNetworkDiagram() {
  // -1 is the overview: nothing muted, nothing moving. The slide opens
  // here so the room sees the whole shape before it is taken apart.
  const [step, setStep] = useState(-1);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!playing) return;
    if (step >= STEPS.length - 1) {
      setPlaying(false);
      return;
    }
    const t = setTimeout(() => setStep((s) => s + 1), 4600);
    return () => clearTimeout(t);
  }, [playing, step]);

  const active = step >= 0 ? STEPS[step] : undefined;
  const o = (name: string) => (!active || active.lit.includes(name) ? 1 : MUTED);
  /** Static connectors recede while a leg is being walked, so the
   * animated line is the only one drawn at full strength. */
  const wire = active ? MUTED : 1;

  return (
    <div>
      <svg
        viewBox="0 0 1000 470"
        style={{ width: "100%", maxHeight: "430px", display: "block" }}
        role="img"
        aria-label="Inside a cluster: CoreDNS in the control plane resolves a Service name; on the worker node kube-proxy programs the rules for the Service, which fronts Pod A and Pod B, each in its own network namespace created by the CNI plugin"
      >
        <defs>
          <marker id="nArrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill={C.accent} />
          </marker>
          <marker id="nArrowDim" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill={C.dim} />
          </marker>
          <radialGradient id="netGlow">
            <stop offset="0%" stopColor={C.accent} stopOpacity="0.5" />
            <stop offset="100%" stopColor={C.accent} stopOpacity="0" />
          </radialGradient>
        </defs>

        <Boundary x={8} y={8} w={984} h={454} label="Kubernetes cluster" />

        {/* ---- control plane ---- */}
        <Boundary x={30} y={42} w={940} h={92} label="Control plane" tight />
        <Node x={395} y={74} w={210} h={50} title="CoreDNS" sub="name → ClusterIP" mono opacity={o("coredns")} />

        {/* ---- worker node ---- */}
        <Boundary x={30} y={150} w={940} h={300} label="Worker node" tight />

        <Node x={395} y={186} w={210} h={48} title="kube-proxy" sub="programs the rules" mono opacity={o("kubeproxy")} />

        {/* Service → kube-proxy: kube-proxy WATCHES the Service, it is not
            a hop the packet takes. Dashed, and pointing up, for that reason. */}
        <g opacity={wire} style={{ transition: "opacity 0.35s ease" }}>
          <path d="M 500 264 L 500 238" fill="none" stroke={C.dim} strokeWidth="1.4" strokeDasharray="5 3" markerEnd="url(#nArrowDim)" />
          <text x={514} y={254} fontSize="12.5" fill={C.dim} fontFamily={FONT_SANS}>
            watches
          </text>
        </g>

        <Node x={380} y={266} w={240} h={48} title="Service" sub="a virtual IP, not a process" accent mono opacity={o("service")} />

        {/* ---- the two Pods, each in its own network namespace ---- */}
        <NetNs cx={185} cy={366} opacity={o("podA")} />
        <Node x={120} y={344} w={130} h={44} title="Pod A" good opacity={o("podA")} />

        <NetNs cx={815} cy={366} opacity={o("podB")} />
        <Node x={750} y={344} w={130} h={44} title="Pod B" good opacity={o("podB")} />

        {/* Pod → Service, in the clear diagonal corridors */}
        <g opacity={wire} style={{ transition: "opacity 0.35s ease" }}>
          <path d="M 250 340 L 378 316" fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#nArrow)" />
          <path d="M 750 340 L 622 316" fill="none" stroke={C.accent} strokeWidth="1.6" markerEnd="url(#nArrow)" />
        </g>

        {/* CNI → each namespace */}
        <g opacity={wire} style={{ transition: "opacity 0.35s ease" }}>
          <path d="M 250 390 L 250 414 L 403 414" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="3 3" />
          <path d="M 750 390 L 750 414 L 597 414" fill="none" stroke={C.dim} strokeWidth="1.3" strokeDasharray="3 3" />
        </g>
        {/* Caption lives INSIDE the box: as a separate line under it, its
            descenders came within 3px of the worker-node border. */}
        <Node x={405} y={392} w={190} h={46} title="CNI plugin" sub="gives each Pod its IP" mono titleSize={15} opacity={o("cni")} />

        {/* ---- the travelling packet ----
            Keyed by step so React remounts this group and the SMIL
            animation restarts from the beginning on every change. */}
        {active && (
          <g key={active.id}>
            {active.legs.map((d, i) => (
              <g key={i}>
                <path id={`leg-${active.id}-${i}`} d={d} fill="none" stroke={C.accent} strokeWidth="2" opacity={0.9} />
                <circle r="14" fill="url(#netGlow)">
                  <animateMotion dur="2.2s" repeatCount="indefinite">
                    <mpath href={`#leg-${active.id}-${i}`} />
                  </animateMotion>
                </circle>
                <circle r="5" fill={C.accent}>
                  <animateMotion dur="2.2s" repeatCount="indefinite">
                    <mpath href={`#leg-${active.id}-${i}`} />
                  </animateMotion>
                </circle>
              </g>
            ))}
          </g>
        )}
      </svg>

      {/* ---- controls ---- */}
      <div style={{ display: "flex", gap: "0.4rem", alignItems: "center", marginTop: "0.5rem", flexWrap: "wrap" }}>
        <Chip label="overview" on={step === -1} onClick={() => { setPlaying(false); setStep(-1); }} />
        {STEPS.map((s, i) => (
          <Chip key={s.id} label={s.chip} on={step === i} onClick={() => { setPlaying(false); setStep(i); }} />
        ))}
        <Chip
          label={playing ? "⏸ pause" : "▶ play"}
          on={playing}
          onClick={() => {
            // Restart from the top if we are sitting on the last step,
            // otherwise play would stop immediately.
            if (!playing && step >= STEPS.length - 1) setStep(-1);
            setPlaying((p) => !p);
          }}
        />
      </div>

      {/* Fixed height so stepping never reflows the diagram above it. */}
      <div
        style={{
          minHeight: "2.7rem",
          marginTop: "0.5rem",
          fontFamily: FONT_SANS,
          fontSize: "0.92rem",
          lineHeight: 1.45,
          color: active ? COLORS.text : COLORS.dim,
          transition: "color 0.3s ease",
        }}
      >
        {active
          ? active.caption
          : "Four moving parts, and only one of them is an object you can kubectl at. Step through to see which."}
      </div>
    </div>
  );
}

function Chip({ label, on, onClick }: { label: string; on: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      style={{
        fontFamily: FONT_MONO,
        fontSize: "0.74rem",
        color: on ? COLORS.bg : COLORS.accent,
        background: on ? COLORS.accent : "transparent",
        border: `1px solid ${on ? COLORS.accent : COLORS.border}`,
        borderRadius: "6px",
        padding: "0.2rem 0.6rem",
        cursor: "pointer",
        whiteSpace: "nowrap",
        transition: "background 0.15s ease, color 0.15s ease, border-color 0.15s ease",
      }}
    >
      {label}
    </button>
  );
}

/** The Pod's own network namespace: its own interfaces, its own routing
 * table. Dash-dot to distinguish it from a boundary you can kubectl at -
 * this one only exists on the node. */
function NetNs({ cx, cy, opacity = 1 }: { cx: number; cy: number; opacity?: number }) {
  return (
    <circle
      cx={cx}
      cy={cy}
      r={62}
      fill="none"
      stroke={C.dim}
      strokeWidth="1.2"
      strokeDasharray="10 4 2 4"
      opacity={opacity * 0.75}
      style={{ transition: "opacity 0.35s ease" }}
    />
  );
}

function Boundary({
  x,
  y,
  w,
  h,
  label,
  tight = false,
}: {
  x: number;
  y: number;
  w: number;
  h: number;
  label: string;
  tight?: boolean;
}) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={10} fill="none" stroke={C.boundary} strokeWidth="1.2" strokeDasharray="6 4" />
      <text x={x + 16} y={y + 24} fontSize={tight ? 14 : 15} fill={C.dim} fontFamily={FONT_MONO} letterSpacing="0.06em">
        {label}
      </text>
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
  titleSize = 17,
  opacity = 1,
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
  opacity?: number;
}) {
  const cx = x + w / 2;
  const edge = accent ? C.accent : good ? C.good : C.boxEdge;
  const titleColor = accent ? C.accent : good ? C.good : C.text;
  return (
    <g opacity={opacity} style={{ transition: "opacity 0.35s ease" }}>
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
        <text x={cx} y={y + h / 2 + 18} fontSize="12.5" fill={C.dim} fontFamily={FONT_SANS} textAnchor="middle">
          {sub}
        </text>
      )}
    </g>
  );
}
