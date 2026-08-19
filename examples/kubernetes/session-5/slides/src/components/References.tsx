import { COLORS, FONT_MONO, FONT_SANS } from "../theme";

/** Where to go next, grouped the way the talk was.
 *
 * Titles are the pages' real <title> text, not paraphrases: someone
 * photographing this slide should be able to search the exact string and
 * land on the page. Same reason the host is shown - kubernetes.io and a
 * CNCF blog post carry different weight, and the audience deserves to
 * see which is which without clicking.
 *
 * Official Kubernetes docs first within each group, supporting material
 * after.
 */

type Ref = { title: string; url: string };
type Group = { heading: string; refs: Ref[] };

const GROUPS: Group[] = [
  {
    heading: "Logging",
    refs: [
      {
        title: "Logging in Kubernetes",
        url: "https://kubernetes.io/docs/tasks/debug/logging/",
      },
      {
        title: "Determine the Reason for Pod Failure",
        url: "https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/",
      },
      {
        title: "A Practical Guide to Kubernetes Logging",
        url: "https://www.cncf.io/blog/2020/10/05/a-practical-guide-to-kubernetes-logging/",
      },
    ],
  },
  {
    heading: "Metrics",
    refs: [
      {
        title: "Resource metrics pipeline",
        url: "https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/",
      },
      {
        title: "Metrics For Kubernetes System Components",
        url: "https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/",
      },
      {
        title: "Kubernetes Metrics Reference",
        url: "https://kubernetes.io/docs/reference/instrumentation/metrics/",
      },
    ],
  },
  {
    heading: "Wider picture",
    refs: [
      {
        title: "Observability",
        url: "https://kubernetes.io/docs/concepts/cluster-administration/observability/",
      },
      {
        title: "Traces For Kubernetes System Components",
        url: "https://kubernetes.io/docs/concepts/cluster-administration/system-traces/",
      },
      {
        title: "Using CoreDNS for Service Discovery",
        url: "https://kubernetes.io/docs/tasks/administer-cluster/coredns/",
      },
    ],
  },
];

export function References() {
  return (
    <div
      style={{
        display: "grid",
        gridTemplateColumns: "repeat(3, 1fr)",
        gap: "1.1rem",
        width: "100%",
      }}
    >
      {GROUPS.map((group) => (
        <div key={group.heading}>
          <div
            style={{
              fontFamily: FONT_MONO,
              fontSize: "0.74rem",
              letterSpacing: "0.09em",
              textTransform: "uppercase",
              color: COLORS.accent,
              paddingBottom: "0.4rem",
              marginBottom: "0.6rem",
              borderBottom: `1px solid ${COLORS.border}`,
            }}
          >
            {group.heading}
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: "0.55rem" }}>
            {group.refs.map((ref) => (
              <a
                key={ref.url}
                href={ref.url}
                target="_blank"
                rel="noreferrer"
                style={{ textDecoration: "none", display: "block" }}
              >
                <div
                  style={{
                    fontFamily: FONT_SANS,
                    fontSize: "0.86rem",
                    lineHeight: 1.3,
                    color: COLORS.text,
                  }}
                >
                  {ref.title}
                </div>
                <div
                  style={{
                    fontFamily: FONT_MONO,
                    fontSize: "0.68rem",
                    color: COLORS.dim,
                    marginTop: "0.1rem",
                    // Long doc paths would otherwise force the grid column
                    // wider than its third and break the three-up layout.
                    overflowWrap: "anywhere",
                  }}
                >
                  {shortPath(ref.url)}
                </div>
              </a>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

/** host + a trimmed path: enough to show provenance and to retype, without
 * printing 70 characters of URL at 0.68rem.
 *
 * Keeps the last two segments, except when the second-to-last is purely
 * numeric - blog URLs carry a /2020/10/05/ date, and ".../05/the-slug"
 * reads as noise rather than as a path. */
function shortPath(url: string): string {
  const { host, pathname } = new URL(url);
  const segments = pathname.split("/").filter(Boolean);
  const penultimate = segments[segments.length - 2];
  const keep = penultimate && /^\d+$/.test(penultimate) ? 1 : 2;
  return `${host.replace(/^www\./, "")}/…/${segments.slice(-keep).join("/")}`;
}
