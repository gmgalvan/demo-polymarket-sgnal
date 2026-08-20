import { useState } from "react";
import { Deck, Slide, Heading, Text, FlexBox, FullScreen, Notes } from "spectacle";
import { COLORS, deckTheme } from "./theme";
import { Kicker } from "./components/Kicker";
import { LogJourney } from "./components/LogJourney";
import { SectionDivider } from "./components/SectionDivider";
import { ObservabilityTaxonomy } from "./components/ObservabilityTaxonomy";
import { Pipeline } from "./components/Pipeline";
import { CollectorPipeline } from "./components/CollectorPipeline";
import { LiveTerminal, type TerminalRequest } from "./components/LiveTerminal";
import { InvestigationPanel } from "./components/InvestigationPanel";
import { CopyableCommand } from "./components/CopyableCommand";
import { TroubleshootFlow } from "./components/TroubleshootFlow";
import { ArchitectureDiagram } from "./components/ArchitectureDiagram";
import { ServiceNetworkDiagram } from "./components/ServiceNetworkDiagram";
import { References } from "./components/References";

function K({ children }: { children: React.ReactNode }) {
  return (
    <span
      style={{
        fontFamily: '"SF Mono", Consolas, monospace',
        background: COLORS.accentSoft,
        color: COLORS.accent,
        padding: "0.1rem 0.4rem",
        borderRadius: "5px",
      }}
    >
      {children}
    </span>
  );
}

/** One-line architecture recap for slides that need a reminder without
 * repeating the full boxed diagram from slide 3 - avoids the node chain
 * wrapping into a lopsided second row when the column is narrower. */
function MiniArch() {
  return (
    <Text
      fontFamily='"SF Mono", Consolas, monospace'
      fontSize="1rem"
      color={COLORS.dim}
      textAlign="left"
      margin="0"
    >
      Browser <span style={{ color: COLORS.accent }}>→</span> ALB{" "}
      <span style={{ color: COLORS.accent }}>→</span> nginx{" "}
      <span style={{ color: COLORS.accent }}>→</span> FastAPI{" "}
      <span style={{ color: COLORS.accent }}>→</span> Mongo
    </Text>
  );
}

/** The taxonomy slide's body: the table doubles as a launcher.
 *
 * Clicking a question expands the terminal with that question's real
 * command typed at the prompt but NOT executed - so the presenter reads
 * it aloud, then presses Enter. One shell for the whole slide, because
 * the terminal stays mounted underneath rather than being opened and
 * closed per click (remounting would kill the session every time).
 */
function TaxonomyInvestigation() {
  const [request, setRequest] = useState<TerminalRequest | undefined>();
  const [activeQuestion, setActiveQuestion] = useState<string>();
  const send = (command: string, key: string) => {
    setActiveQuestion(key);
    // A new nonce every click, so picking the same row twice still
    // re-sends instead of looking unchanged to the effect.
    setRequest({ command, nonce: Date.now() });
  };

  return (
    <>
      {/* Table left, terminal right - stacked, the terminal only got a
          20vh sliver and long output scrolled out of sight immediately.
          Side by side, the question stays visible while its answer
          arrives, which is the whole point of the slide. */}
      <div
        style={{
          display: "flex",
          gap: "1.2rem",
          alignItems: "stretch",
          height: "440px",
        }}
      >
        <div style={{ flex: "0 0 52%", minWidth: 0, overflowY: "auto" }}>
          <ObservabilityTaxonomy
            activeQuestion={activeQuestion}
            onSelect={(row) => row.command && send(row.command, row.question)}
          />
        </div>
        <div style={{ flex: "1 1 auto", minWidth: 0 }}>
          <LiveTerminal height="100%" request={request} />
        </div>
      </div>
    </>
  );
}

const footerTemplate = ({
  slideNumber,
  numberOfSlides,
}: {
  slideNumber: number;
  numberOfSlides: number;
}) => (
  <FlexBox
    position="absolute"
    bottom={0}
    left={0}
    right={0}
    justifyContent="space-between"
    alignItems="center"
    padding="0.6rem 1.4rem"
    fontFamily='"SF Mono", Consolas, monospace'
    fontSize="0.75rem"
    color={COLORS.dim}
  >
    <span>Module 5 — Observability, Logging, Monitoring &amp; Troubleshooting</span>
    <FlexBox alignItems="center" style={{ gap: "1rem" }}>
      <span>
        {slideNumber} / {numberOfSlides}
      </span>
      <FullScreen color={COLORS.dim} />
    </FlexBox>
  </FlexBox>
);

export default function App() {
  return (
    <Deck theme={deckTheme} template={footerTemplate} backgroundImage={`none`}>
      {/* 1: Title */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <FlexBox height="100%" flexDirection="column" justifyContent="center" alignItems="flex-start">
          <Kicker>Module 5</Kicker>
          <Heading fontSize="3.6rem" color={COLORS.text} textAlign="left" margin="0 0 0.4em 0">
            Observability, Logging,
            <br />
            Monitoring &amp; Troubleshooting
          </Heading>
          <Text fontSize="1.35rem" color={COLORS.dim} textAlign="left" maxWidth="46rem">
            A real incident report from a real EKS cluster — not slideware.
          </Text>
        </FlexBox>
      </Slide>

      {/* 2: Monitoring &amp; Logging */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <SectionDivider
          n="01"
          title="Monitoring &amp; Logging"
          subtitle="What the system is, and how we watch it while it runs."
        />
      </Slide>

      {/* 3: The app */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>What's deployed</Kicker>
        <Heading fontSize="2rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          A small finance Q&amp;A service
        </Heading>
        <Text fontSize="0.95rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          Everything CPU-only, on one Graviton node. The only thing outside the
          cluster boundary is the volume — and that's the point.
        </Text>
        <ArchitectureDiagram />
      </Slide>

      {/* 4: Live demo */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Live demo</Kicker>
        <Heading fontSize="2.2rem" color={COLORS.text} textAlign="left" margin="0 0 0.3em 0">
          Let's actually look
        </Heading>
        <MiniArch />
        {/* Raw flexbox, not Spectacle's Box/FlexBox `flex` prop - that
            prop isn't a real styled-system field and was silently
            dropped, so both columns fell back to content-based sizing
            and starved the terminal of width. Fixed row height so both
            columns end at the same line instead of leaving dead space
            under the shorter one. */}
        <div
          style={{
            display: "flex",
            gap: "1.6rem",
            marginTop: "1.1rem",
            alignItems: "stretch",
            height: "430px",
          }}
        >
          <div
            style={{
              flex: "0 0 40%",
              minWidth: 0,
              display: "flex",
              flexDirection: "column",
            }}
          >
            <Text fontSize="0.92rem" color={COLORS.dim} margin="0 0 0.7em 0" textAlign="left">
              1. click a command &nbsp;·&nbsp; 2. right-click the terminal to paste
            </Text>
            <CopyableCommand command="kubectl -n session-5 get pvc,pods" />
            <CopyableCommand command="kubectl -n session-5 describe pod -l app=api-spacy-finance" />
            <CopyableCommand command="curl https://finance.example.com/health" />
            <CopyableCommand command="kubectl -n session-5 logs deploy/api-spacy-finance" />
            <Text
              fontSize="0.85rem"
              color={COLORS.dim}
              textAlign="left"
              margin="auto 0 0 0"
              style={{ opacity: 0.7 }}
            >
              Everything comes back healthy — that's the <em>after</em>. The next
              slides are how it got there.
            </Text>
          </div>
          <div style={{ flex: "1 1 60%", minWidth: 0 }}>
            <LiveTerminal height="100%" />
          </div>
        </div>
      </Slide>

      {/* 5: Where a log line actually goes */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Logging, before the tools</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.2em 0">
          Where does a log line actually go?
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.6rem 0">
          Your app prints a line. Follow it — the interesting part is where it
          stops.
        </Text>
        <LogJourney />
        <div style={{ marginTop: "0.7rem" }}>
          <InvestigationPanel
            terminalHeight="215px"
            leftWidth="52%"
            steps={[
              {
                question: "Read what the app is printing",
                command: "kubectl -n session-5 logs deploy/api-spacy-finance --tail=15",
                expect: "The health checks hitting it, live",
              },
              {
                question: "And the container that died before this one?",
                command: "kubectl -n session-5 logs deploy/mongo --previous --tail=15",
                expect: "One restart back — that's as far as it goes",
              },
            ]}
          />
        </div>
        <Notes>
          Walk the diagram left to right. Nothing writes a log file on purpose:
          the app prints to stdout, the container runtime captures it, and it
          lands as files on the node under /var/log/containers. `kubectl logs`
          does not stream from your app — it asks the kubelet to read that file.
          {"\n\n"}
          Which is why --previous only goes back ONE container, and why nothing
          survives the Pod being deleted or evicted, or the node going away.
          Log rotation on the node quietly bounds it further.
          {"\n\n"}
          That gap is the entire reason for the green branch: a node agent, run
          as a DaemonSet, tails those same files and ships each line somewhere
          that outlives the node. Kubernetes does not do this for you — same
          shape as the Metrics Server story we're about to hit.
          {"\n\n"}
          References: Kubernetes — Logging
          https://kubernetes.io/docs/tasks/debug/logging/ and the CNCF
          practical guide
          https://www.cncf.io/blog/2020/10/05/a-practical-guide-to-kubernetes-logging/
        </Notes>
      </Slide>

      {/* 6: Where the numbers come from */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Under the hood</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.2em 0">
          Where would CPU and memory come from?
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.6rem 0">
          This much is running right now, without anyone installing anything.
          The question is what comes after it.
        </Text>
        {/* Only what actually exists on this cluster. Drawing the
            missing boxes - even unnamed - still told the room the shape
            of the answer. Showing the chain simply STOP is the honest
            picture, and the next slide is where the rest appears. */}
        <Pipeline
          stages={[
            { label: "cAdvisor", sub: "in the kubelet", ok: true },
            { label: "kubelet", sub: "/metrics/resource", ok: true },
          ]}
        />
        <div style={{ marginTop: "0.7rem" }}>
          <InvestigationPanel
            terminalHeight="300px"
            leftWidth="50%"
            steps={[
              {
                question: "Name the node",
                command: "NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}'); echo $NODE",
                expect: "Must print a node name. Run this one FIRST",
              },
              {
                question: "Its metrics endpoint",
                command: 'RES="/api/v1/nodes/$NODE/proxy/metrics/resource"; echo $RES',
                expect: "If you see nodes// with a double slash, redo step 1",
              },
              {
                question: "Is anything being produced at all?",
                command: "kubectl get --raw $RES | grep working_set | grep session-5",
                expect: "Real memory for our own Pods — no add-on involved",
              },
              {
                question: "And the API that should serve it?",
                command: "kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes",
                expect: "NotFound — the data exists, nothing serves it",
              },
              {
                // Only produces output once Metrics Server exists, so this is
                // the step to come back to after the next slide. The raw reply
                // is a wall of node labels; these three fields are the lesson,
                // and window in particular is what the add-on adds.
                question: "Same call, readable — once it works",
                command:
                  "kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq '.items[] | {node: .metadata.name, window, usage}'",
                expect: "Come back here after installing — watch the window field",
              },
            ]}
          />
        </div>
        <Notes>
          These steps are ordered and the shell remembers: 1 sets $NODE, 2
          uses it. Clicking 2 before 1 builds a path with an empty node name
          — /api/v1/nodes//proxy/... — and the failure is nasty, because the
          apiserver answers it with the exact same "NotFound: the server
          could not find the requested resource" that step 4 produces for a
          completely different reason. Both steps now echo what they set, so
          a double slash is visible immediately.
          {"\n\n"}
          Walk the pipeline first, then prove the left half of it is alive. Step
          3 is the surprise: cAdvisor inside the kubelet has been collecting
          this the whole time, and the kubelet publishes it at
          /metrics/resource. Nothing was installed to make that happen.
          {"\n\n"}
          Step 4 sets up the next slide. The aggregated API — the one kubectl
          top and the autoscalers actually read — answers NotFound. The data
          exists; nothing is serving it in the shape those consumers need.
          {"\n\n"}
          Worth naming here: what the kubelet gives you is a cumulative
          counter. What the Metrics API gives you is a rate already computed
          over a window, usually 30 seconds. That conversion is the work the
          missing component does.
          {"\n\n"}
          Reference: Kubernetes — Resource Metrics Pipeline
          https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
        </Notes>
      </Slide>

      {/* 7: Install the missing piece */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker tone="good">The missing piece has a name</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.2em 0">
          Metrics Server
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          One manifest, and the chain connects. It is an add-on — Kubernetes
          does not ship it.
        </Text>
        <Pipeline
          stages={[
            { label: "cAdvisor", sub: "already there", ok: true },
            { label: "kubelet", sub: "already there", ok: true },
            { label: "Metrics Server", sub: "installing now", ok: true },
            { label: "metrics.k8s.io", sub: "registers itself", ok: true },
            { label: "kubectl top · HPA", sub: "can read at last", ok: true },
          ]}
        />
        <div style={{ marginTop: "0.8rem" }}>
          <InvestigationPanel
            terminalHeight="300px"
            leftWidth="50%"
            steps={[
              {
                question: "Install it",
                command:
                  "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",
                expect: "An add-on — Kubernetes does not ship it",
              },
              {
                question: "Wait for it",
                command: "kubectl -n kube-system rollout status deploy/metrics-server",
                expect: "Give it one scrape window",
              },
              {
                question: "Did the API register itself?",
                command: "kubectl api-versions | grep -i metrics",
                expect: "metrics.k8s.io/v1beta1 has appeared",
              },
            ]}
          />
        </div>
        <Notes>
          This is the whole fix: one manifest. Nothing about the app, the
          kubelet or the node changes — we add the component that scrapes every
          kubelet and implements the aggregated API, and the gap closes.
          {"\n\n"}
          Step 3 is the proof: metrics.k8s.io registers ITSELF as an
          APIService. Nobody edits the API server. That is how aggregated APIs
          extend Kubernetes.
          {"\n\n"}
          What Metrics Server actually does with the data: the kubelet hands
          out a cumulative counter, and Metrics Server turns it into a rate
          averaged over a window. That is also its limit — it keeps no history,
          so you only ever get the latest snapshot. Say plainly: Metrics Server
          is NOT Prometheus.
          {"\n\n"}
          We remove it again at the end of the session, so the next run of this
          deck starts from the same failing state.
          {"\n\n"}
          Reference: Kubernetes — Resource Metrics Pipeline
          https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/
        </Notes>
      </Slide>

      {/* 8: The taxonomy */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Locking it in</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Seven questions, seven different answers
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.8rem 0">
          All of these get called "monitoring". Click one and the terminal
          answers it, live.
        </Text>
        <TaxonomyInvestigation />
        <Notes>
          Click each row in order — the terminal expands with that question's
          real command typed at the prompt, unrun. Read it aloud, press Enter,
          and the room sees the actual answer.
          {"\n\n"}
          The two beats worth landing:
          {"\n"}
          1. CPU and memory are separate rows because they are measured
          differently. CPU is a rate derived from a cumulative counter across a
          window; memory is a working-set reading at an instant. Same endpoint,
          different kind of number.
          {"\n"}
          2. Rows 5 and 6 are not measurements at all — requests/limits are what
          we *promised*, and the node's allocated resources are what the
          scheduler has *committed*. Neither tells you what is actually being
          used. Ask both questions or you will size things by guesswork.
          {"\n\n"}
          Reference: Kubernetes — Observability
          https://kubernetes.io/docs/concepts/cluster-administration/observability/
          {"\n\n"}
          Reference: Kubernetes — Observability
          https://kubernetes.io/docs/concepts/cluster-administration/observability/
          — validates keeping metrics, logs and traces distinct, and Events as
          its own thing again.
        </Notes>
      </Slide>

      {/* 9: /metrics and Prometheus-style collection */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Beyond right now</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          When CPU and memory aren't enough
        </Heading>
        <Text fontSize="0.88rem" color={COLORS.dim} textAlign="left" margin="0 0 0.6rem 0">
          Metrics Server keeps no history. For anything over time you need a
          collector — and, again, Kubernetes does not ship one.
        </Text>
        <CollectorPipeline
          revealAtStep={1}
          before={[
            { label: "Kubernetes component", sub: "kubelet, apiserver, …", ok: true },
            { label: "/metrics", sub: "Prometheus-compatible text", ok: true },
            { label: "a collector", sub: "you install this", outside: true },
            { label: "dashboards · alerts", sub: "you install this", outside: true },
          ]}
          after={[
            { label: "Kubernetes component", sub: "kubelet, apiserver, …", ok: true },
            { label: "/metrics", sub: "Prometheus-compatible text", ok: true },
            { label: "Prometheus", sub: "scrapes it, stores history", ok: true },
            { label: "Grafana · Alertmanager", sub: "queries it, alerts on it", ok: true },
          ]}
          steps={[
            {
              question: "Add the chart repo",
              command:
                "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",
            },
            {
              question: "Install collector + dashboards in one go",
              command:
                "helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace --set grafana.adminPassword=admin",
              expect: "~60s. Prometheus, Grafana, Alertmanager, exporters",
            },
            {
              question: "What did that actually bring?",
              command: "kubectl -n monitoring get pods",
              expect: "Six Pods — none of this existed a minute ago",
            },
            {
              question: "Where is the Grafana password kept?",
              command:
                'kubectl -n monitoring get secret monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo',
              expect: "A Secret, base64 — encoded, not encrypted",
            },
            {
              question: "Open Grafana",
              command:
                "kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80",
              expect: "Paste in a second terminal, then open the tab. admin / admin",
              copyOnly: true,
              link: { href: "http://localhost:3000", label: "localhost:3000 — Grafana" },
            },
            {
              question: "Ask something kubectl top cannot",
              command:
                "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090",
              expect: "Same again, then query rate(...[5m]) in the tab",
              copyOnly: true,
              link: { href: "http://localhost:9090", label: "localhost:9090 — Prometheus" },
            },
          ]}
        />
        <Notes>
          The distinction to keep sharp: Metrics Server answers "right now" for
          CPU and memory only, and keeps nothing. Prometheus scrapes /metrics
          from many components, stores a time series, and answers questions
          about the past. They are not competitors and a cluster can have
          either, both, or neither.
          {"\n\n"}
          The diagram above fills in when you click step 2: the two amber
          "you install this" boxes become Prometheus and Grafana. That is the
          whole slide in one gesture — the chain was always incomplete, and you
          are the one completing it.
          {"\n\n"}
          upgrade --install rather than install, so re-running it on a cluster
          that already has the release succeeds instead of failing with
          "cannot reuse a name that is still in use".
          {"\n\n"}
          Steps 4 and 5 are marked "other terminal" and only copy to the
          clipboard — they never touch the terminal on this slide. port-forward
          does not return, so running it here would occupy the one console the
          rest of the demo needs. Have a second terminal open and paste there.
          {"\n\n"}
          Each of those two steps carries an ↗ link that opens the tunnel's
          far end in a new tab, so there is no typing a URL in front of the
          room. The link only works once the port-forward is actually running
          — that is the order: copy, paste, then click.
          {"\n\n"}
          Step 4 is worth the twenty seconds even though we set the password
          ourselves with --set: the chart stores it in a Secret, and base64 -d
          is all it takes to read it back. Encoded, not encrypted — the same
          point from the Secrets session, now on a component the audience
          actually wants to log into. Without that --set flag the chart
          generates a random password and this step stops being optional.
          {"\n\n"}
          In Grafana log in with admin / admin; the bundled Kubernetes
          dashboards are already populated, no dashboard building required.
          Dashboards → "Kubernetes / Compute Resources / Namespace (Pods)",
          then set the namespace variable to session-5 to see our own Pods. It
          defaults to a one-hour window — which is the point: an hour of
          history that kubectl top never had.
          {"\n\n"}
          If you open Prometheus instead (step 5), the query worth typing is
          {'rate(container_cpu_usage_seconds_total{namespace="session-5"}[5m])'}{" "}
          — a rate over a window you choose, computed from history. That is
          precisely what kubectl top cannot do: it only ever knows the latest
          scrape.
          {"\n\n"}
          Say plainly, one more time: none of this ships with Kubernetes.
          Components expose /metrics in a Prometheus-compatible format; nothing
          collects it until you deploy something that does.
          {"\n\n"}
          Uninstall with: helm uninstall monitoring -n monitoring
          {"\n\n"}
          References: Kubernetes — System Metrics
          https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/
          and the Metrics Reference
          https://kubernetes.io/docs/reference/instrumentation/metrics/
        </Notes>
      </Slide>

      {/* 10: Troubleshooting */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <SectionDivider
          n="02"
          title="Troubleshooting"
          subtitle="When it breaks: which layer, which command, which evidence."
        />
      </Slide>

      {/* 11: The general map */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Zooming out</Kicker>
        <Heading fontSize="2rem" color={COLORS.text} textAlign="left" margin="0 0 0.2em 0">
          The whole decision tree
        </Heading>
        <Text fontSize="0.95rem" color={COLORS.dim} textAlign="left" margin="0 0 1rem 0">
          Debug bottom-up: Pod first, then Service, then Ingress. Never skip
          ahead — a broken Pod looks exactly like a broken Ingress from the
          browser.
        </Text>
        <TroubleshootFlow />
        <Text fontSize="0.78rem" color={COLORS.dim} textAlign="left" margin="1rem 0 0 0" style={{ opacity: 0.65 }}>
          Structure from learnkube.com/troubleshooting-deployments
        </Text>
      </Slide>

      {/* 12: Break 1 - Pod layer */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 1 of 3 · the Pod layer</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Ship a tag that does not exist
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          The most ordinary deploy mistake there is: a typo in an image tag.
          Run it, then watch what the rolling update does — and what it
          refuses to do.
        </Text>
        <InvestigationPanel
          terminalHeight="400px"
          leftWidth="50%"
          steps={[
            {
              question: "Break it",
              command:
                "kubectl -n session-5 set image deploy/api-spacy-finance api=111122223333.dkr.ecr.us-east-1.amazonaws.com/api-spacy-finance:v99",
              expect: "Give it ~20s, then go to the next slide",
            },
            {
              question: "Is the site down?",
              command: "curl -s -o /dev/null -w '%{http_code}\\n' https://finance.example.com/",
              expect: "200. The old Pods are still serving — that is the point",
            },
          ]}
        />
        <Notes>
          Run step 1, then step 2 immediately. The site answers 200 while the
          deployment is broken, because a RollingUpdate will not take the old
          Pods down until the new one reports Ready — and it never will.
          {"\n\n"}
          That is worth dwelling on: "the deploy failed" and "the site is down"
          are different statements, and Kubernetes worked hard to keep them
          different. Someone watching only the website would see nothing.
        </Notes>
      </Slide>

      {/* 13: Investigate 1 */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 1 · investigate</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          The Pod that never started
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          Bottom of the tree first: is the Pod running? Ask the app what
          happened — then ask the cluster instead.
        </Text>
        <InvestigationPanel
          terminalHeight="455px"
          leftWidth="50%"
          steps={[
            {
              question: "What does the cluster say?",
              command: "kubectl -n session-5 get pods -l app=api-spacy-finance",
              expect: "Two Running, one ErrImagePull → ImagePullBackOff",
            },
            {
              question: "Grab the broken one",
              command:
                "BAD=$(kubectl -n session-5 get pods -l app=api-spacy-finance --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}'); echo $BAD",
              expect: "Sets $BAD — it never left Pending",
            },
            {
              question: "Ask the application what happened",
              command: "kubectl -n session-5 logs $BAD",
              expect: "Nothing. There is no process — it never started",
            },
            {
              question: "Ask the cluster instead",
              command: "kubectl -n session-5 describe pod $BAD | tail -12",
              expect: "Events: Failed to pull ... NotFound. There it is",
            },
            {
              question: "Put it back",
              command: "kubectl -n session-5 rollout undo deploy/api-spacy-finance",
              expect: "Previous ReplicaSet restored",
            },
          ]}
        />
        <Notes>
          Step 3 is the whole slide. kubectl logs returns a BadRequest saying
          the container is waiting to start: logs come from a process writing
          to stdout, and there is no process. Reaching for logs here is the
          single most common wasted minute in Kubernetes debugging.
          {"\n\n"}
          Step 4 works because Events are not application output at all — they
          are the control plane narrating its own attempts, recorded against
          the object. Different producer, different lifetime, different place
          to look. That is the distinction the taxonomy slide set up.
          {"\n\n"}
          Reference: kubernetes.io/docs/tasks/debug/debug-application/debug-pods/
        </Notes>
      </Slide>

      {/* 14: Break 2 - Service layer */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 2 of 3 · the Service layer</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          One extra letter in a selector
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          A Service finds its Pods by matching labels. Change the selector so
          it matches nothing — no Pod is touched, no object is deleted.
        </Text>
        <InvestigationPanel
          terminalHeight="400px"
          leftWidth="50%"
          steps={[
            {
              question: "Break it",
              command:
                "kubectl -n session-5 patch svc api-spacy-finance -p '{\"spec\":{\"selector\":{\"app\":\"api-spacy-financee\"}}}'",
              expect: "app=api-spacy-financee — note the double e",
            },
            {
              question: "Now try the site",
              command: "curl -s https://finance.example.com/health | head -4",
              expect: "502 Bad Gateway. The page still loads; the API is gone",
            },
          ]}
        />
        <Notes>
          Open the browser too: the frontend loads perfectly — it is static
          files served by nginx — but every question fails. Half-broken is
          much more realistic than a blank page, and much more confusing to
          the person on call.
          {"\n\n"}
          Nothing was deleted and no Pod restarted. The only change is one
          letter in a label selector.
        </Notes>
      </Slide>

      {/* 15: Investigate 2 */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 2 · investigate</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Every Pod is healthy. It is still broken.
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          The tool that solved bug 1 now tells you nothing. That is the lesson
          — move up one layer.
        </Text>
        <InvestigationPanel
          terminalHeight="455px"
          leftWidth="50%"
          steps={[
            {
              question: "Start where we started last time",
              command: "kubectl -n session-5 get pods -l app=api-spacy-finance",
              expect: "1/1 Running, 0 restarts. Perfectly healthy. Still broken",
            },
            {
              question: "Who does the Service actually reach?",
              command:
                "kubectl -n session-5 describe svc api-spacy-finance | grep -E 'Selector|Endpoints'",
              expect: "Endpoints is EMPTY. Selector has the typo",
            },
            {
              question: "What does the frontend see?",
              command:
                "kubectl -n session-5 logs deploy/finance-chat-frontend --tail=20 | grep -i error",
              expect: "connect() failed (111: Connection refused) to upstream",
            },
            {
              question: "Put it back",
              command:
                "kubectl -n session-5 patch svc api-spacy-finance -p '{\"spec\":{\"selector\":{\"app\":\"api-spacy-finance\"}}}'",
              expect: "Endpoints repopulate within seconds",
            },
          ]}
        />
        <Notes>
          A Service is a label selector and nothing more. When it matches no
          Pods its Endpoints list is empty, traffic goes nowhere, and — this
          is the important part — no Event is emitted and no Pod is marked
          unhealthy. Kubernetes considers an empty Service a perfectly valid
          state, because it is: it is what a Deployment scaled to zero looks
          like.
          {"\n\n"}
          So this failure is silent by design. The only two places it shows up
          are the Endpoints list and the logs of whoever tried to connect.
          {"\n\n"}
          Note in step 3 the upstream is a ClusterIP that resolved fine — DNS
          was never the problem. The address exists, nothing is behind it.
          {"\n\n"}
          Subtler sibling worth mentioning out loud: get the selector right but
          the targetPort wrong, and Endpoints populate while connections still
          fail.
        </Notes>
      </Slide>

      {/* 16: Break 3 - the database */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 3 of 3 · the database</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Take the database away
        </Heading>
        <Text fontSize="0.9rem" color={COLORS.dim} textAlign="left" margin="0 0 0.7rem 0">
          No typo this time, no broken object. Just scale MongoDB to zero and
          ask the app a question, exactly as a user would.
        </Text>
        <InvestigationPanel
          terminalHeight="400px"
          leftWidth="50%"
          steps={[
            {
              question: "Break it",
              command: "kubectl -n session-5 scale deploy/mongo --replicas=0",
              expect: "The Pod goes away. The volume stays",
            },
            {
              question: "Ask a question, like a user",
              command:
                "curl -s -X POST https://finance.example.com/ask -H 'Content-Type: application/json' -d '{\"question\":\"what is inflation?\"}'",
              expect: "A correct answer, HTTP 200. Nothing looks wrong",
            },
          ]}
        />
        <Notes>
          Ask it in the browser as well, two or three times — it answers
          normally every time. app/nlp.py falls back to a built-in glossary
          when Mongo is unreachable, which is good engineering and terrible
          for whoever has to notice the outage.
          {"\n\n"}
          Those questions also generate the log lines the next slide needs, so
          do not skip this step.
        </Notes>
      </Slide>

      {/* 17: Investigate 3 */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Bug 3 · investigate</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Kubernetes says everything is fine
        </Heading>
        <Text fontSize="0.88rem" color={COLORS.dim} textAlign="left" margin="0 0 0.45rem 0">
          No layer of the cluster reports a problem. Not the Pods, not the
          Service, not the probes.
        </Text>
        <InvestigationPanel
          terminalHeight="495px"
          leftWidth="50%"
          steps={[
            {
              question: "Anything red?",
              command: "kubectl -n session-5 get pods",
              expect: "All 1/1 Running, 0 restarts. mongo is simply absent",
            },
            {
              question: "Is the backend still Ready?",
              command:
                "kubectl -n session-5 describe svc api-spacy-finance | grep -E 'Endpoints'",
              expect: "Both backends still registered. Probes are green",
            },
            {
              question: "What does the health endpoint claim?",
              command: "curl -s https://finance.example.com/health",
              expect: 'HTTP 200 — with "database":"unreachable" inside it',
            },
            {
              question: "Is anything being saved?",
              command: "curl -s https://finance.example.com/queries",
              expect: "[] — same as a brand new app with no traffic",
            },
            {
              question: "Ask the application itself",
              command:
                "kubectl -n session-5 logs -l app=api-spacy-finance --tail=30 --prefix | grep -i mongo",
              expect: "could not log query to MongoDB: Connection refused",
            },
            {
              question: "Put it back",
              command: "kubectl -n session-5 scale deploy/mongo --replicas=1",
              expect: 'Then re-run /health: "database":"ok"',
            },
          ]}
        />
        <Notes>
          Step 3 is the trap. The readiness probe targets /health, and /health
          returns 200 even when it has just discovered the database is
          unreachable — the status is reported in the body, where kubelet
          never looks. So the Pod stays Ready and traffic keeps arriving.
          Probes check what you told them to check, not what you meant.
          {"\n\n"}
          Step 4 is worse: an empty list is a completely normal response. A
          dashboard counting saved queries would show zero, and zero is not an
          error. This is business data, not a metric and not a log — the
          distinction from the taxonomy slide, now costing us the outage.
          {"\n\n"}
          Step 5 is the only place the truth is written down, and note the
          --prefix flag: with two replicas the failing line may be on either
          Pod, so we aggregate by label rather than guessing.
          {"\n\n"}
          Close the section here: three bugs, three layers, and the evidence
          moved every time — Events, then Endpoints, then the application's
          own logs. Bug 3 is the one that would page nobody.
        </Notes>
      </Slide>

      {/* 18: Networking - what is actually involved */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Troubleshooting networking</Kicker>
        <Heading fontSize="1.85rem" color={COLORS.text} textAlign="left" margin="0 0 0.1em 0">
          What "Pod A calls Pod B" actually involves
        </Heading>
        <Text fontSize="0.86rem" color={COLORS.dim} textAlign="left" margin="0 0 0.4rem 0">
          Bug 2 was one of these four pieces. Step through the rest.
        </Text>
        <ServiceNetworkDiagram />
        <Notes>
          The diagram steps: click the numbered chips, or hit play to let it
          advance on its own every ~4.5s. It opens on the overview with
          nothing dimmed — show the whole shape first, then take it apart.
          Each step lights only the parts involved, runs the packet along
          that leg, and puts the line to say underneath.
          {"\n\n"}
          Walk it in the order a packet experiences it, which is also the
          order you debug it.
          {"\n\n"}
          CoreDNS turns "api-spacy-finance" into a ClusterIP. It runs in the
          control plane, and it is a Deployment like any other — it can be
          down, it can be throttled, it can have a stale config. If the name
          does not resolve, nothing below matters.
          {"\n\n"}
          The Service is a virtual IP and nothing else. There is no process
          listening on it, no container, no logs. That is exactly why bug 2
          was silent: an object with no backends is still a perfectly valid
          object.
          {"\n\n"}
          kube-proxy is the piece nobody mentions. It watches Services and
          Endpoints and programs the node's packet-filter rules so the
          virtual IP means something. Note the arrow points UP and is
          dashed: kube-proxy is not a hop the packet takes, it is what set
          the rules up beforehand. If kube-proxy is unhealthy on one node,
          you get the confusing case where the same Service works from some
          Pods and not others.
          {"\n\n"}
          The CNI plugin — on EKS, the VPC CNI — gave each Pod its network
          namespace and its IP. The dash-dot circles are those namespaces:
          real isolation that exists on the node, not an object you can
          kubectl at.
          {"\n\n"}
          Say the diagnostic order out loud, because it is the takeaway:
          does the name resolve, does the ClusterIP have Endpoints, are the
          rules programmed, can the Pods reach each other at all. We already
          did step two, live, and it was the whole of bug 2.
          {"\n\n"}
          References: kubernetes.io/docs/concepts/services-networking/service/
          and kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
        </Notes>
      </Slide>

      {/* 19: DNS - does the name resolve */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Networking · piece 1</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Does the name even resolve?
        </Heading>
        <Text fontSize="0.88rem" color={COLORS.dim} textAlign="left" margin="0 0 0.45rem 0">
          No <K>dig</K>, no <K>nslookup</K> in the container — most production
          images have neither. So we bring our own.
        </Text>
        <InvestigationPanel
          terminalHeight="495px"
          leftWidth="52%"
          steps={[
            {
              question: "What does the Pod think DNS is?",
              command:
                "kubectl -n session-5 exec deploy/api-spacy-finance -- cat /etc/resolv.conf",
              expect: "nameserver 172.20.0.10 — remember that address",
            },
            {
              question: "Whose address is that?",
              command: "kubectl -n kube-system get svc kube-dns",
              expect: "The same IP. DNS is itself just a Service",
            },
            {
              question: "Pick a Pod to debug",
              command:
                "POD=$(kubectl -n session-5 get pods -l app=api-spacy-finance -o jsonpath='{.items[0].metadata.name}'); echo $POD",
              expect: "Sets $POD",
            },
            {
              question: "Bring a toolbox into its network namespace",
              command:
                "kubectl -n session-5 debug -it $POD --image=busybox:1.36 --target=api -- sh",
              expect: "An ephemeral container, sharing the Pod's netns",
            },
            {
              question: "Now ask, from inside",
              command: "nslookup mongo",
              expect: "Server is 172.20.0.10. Watch it walk the search list",
            },
            {
              question: "Leave, and see who was answering",
              command: "exit",
              expect: "Then: kubectl -n kube-system get deploy coredns → 2/2",
            },
          ]}
        />
        <Notes>
          Step 1 and 2 are a pair: the nameserver in resolv.conf is the
          ClusterIP of the kube-dns Service. DNS inside a cluster is reached
          exactly the way anything else is — which means every failure mode
          from the previous section applies to it too.
          {"\n\n"}
          Step 4 is the modern answer to "there are no tools in this
          container": kubectl debug attaches an ephemeral container. With
          --target it joins the target container's network namespace, so it
          sees the same interfaces, the same resolv.conf, the same routes.
          On the diagram, we are inside Pod A's dash-dot circle.
          {"\n\n"}
          busybox because it is 4MB and starts instantly. If you want the
          full kit — dig, tcpdump, ss, iptables — swap the image for
          nicolaka/netshoot; it works identically but the first pull costs
          about twenty seconds.
          {"\n\n"}
          Step 5 output is the lesson. It prints the successful answer
          (mongo.session-5.svc.cluster.local) alongside several NXDOMAIN
          lines for the other search domains. That is the resolver walking
          the search list from resolv.conf in order. It is also why
          ndots:5 has a reputation: a name with fewer than 5 dots gets tried
          against every search domain first, so an external hostname can
          cost four failed lookups before the real one.
          {"\n\n"}
          Worth saying: ephemeral containers cannot be removed from a Pod.
          They stay in the spec until the Pod is deleted. Harmless, but do
          not debug the same Pod twenty times and wonder why the spec is
          full of debugger-xxxxx.
          {"\n\n"}
          Reference: kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
        </Notes>
      </Slide>

      {/* 20: CNI and kube-proxy - where the addresses come from */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Networking · pieces 3 and 4</Kicker>
        <Heading fontSize="1.9rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Three address spaces, one cluster
        </Heading>
        <Text fontSize="0.88rem" color={COLORS.dim} textAlign="left" margin="0 0 0.6rem 0">
          Pods, nodes and Services do not live in the same place — and on
          EKS, two of them do.
        </Text>
        <InvestigationPanel
          terminalHeight="455px"
          leftWidth="52%"
          steps={[
            {
              question: "What IPs do our Pods have?",
              command: "kubectl -n session-5 get pods -o wide",
              expect: "10.40.8.x — and note they share one node",
            },
            {
              question: "And the node itself?",
              command: "kubectl get nodes -o wide",
              expect: "10.40.8.14. The same subnet. That is not normal",
            },
            {
              question: "Who hands those addresses out?",
              command: "kubectl -n kube-system get ds aws-node",
              expect: "The VPC CNI. One agent per node, so a DaemonSet",
            },
            {
              question: "And who programs the Service rules?",
              command: "kubectl -n kube-system get ds kube-proxy",
              expect: "Also a DaemonSet — rules are per node",
            },
            {
              question: "Now look at the Services",
              command: "kubectl -n session-5 get svc",
              expect: "172.20.x.x — a completely different range",
            },
          ]}
        />
        <Notes>
          Steps 1 and 2 are the EKS-specific part and worth slowing down
          for. On most clusters Pod IPs come from an overlay network that
          exists only inside the cluster. Here the Pods have real VPC
          addresses from the same subnet as the node — the VPC CNI assigns
          secondary IPs from the ENIs attached to the instance. That is why
          a security group or a NACL can break Pod traffic on EKS: the
          packets are ordinary VPC packets.
          {"\n\n"}
          It also explains a limit people hit: the number of Pods per node
          is bounded by how many IPs the instance type's ENIs can carry, not
          by CPU or memory.
          {"\n\n"}
          Step 5 is the contrast that makes the whole section land. The
          Service ClusterIPs are 172.20.x.x — an address range that exists
          nowhere in the VPC. No interface has one, no ENI knows about them,
          you cannot route to them from outside. They are only meaningful as
          entries in the packet-filter rules kube-proxy wrote on each node.
          {"\n\n"}
          Point back at the diagram: that is what "a virtual IP, not a
          process" means, and it is why bug 2 produced connection refused
          rather than no route to host. The address was fine. The rule
          behind it had no backends to choose from.
          {"\n\n"}
          Reference: kubernetes.io/docs/concepts/services-networking/cluster-ip-allocation/
        </Notes>
      </Slide>

      {/* 21: Thanks + references.
          The references live on the closing slide rather than a separate
          one because this is the slide that stays up during Q&A - which is
          exactly when people photograph it. */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Module 5 · Observability, Logging, Monitoring &amp; Troubleshooting</Kicker>
        <Heading fontSize="2.6rem" color={COLORS.text} textAlign="left" margin="0 0 0.15em 0">
          Questions?
        </Heading>
        <Text fontSize="0.95rem" color={COLORS.dim} textAlign="left" margin="0 0 1.4rem 0">
          Every command in this deck, and every error we hit building it:{" "}
          <K>examples/kubernetes/session-5/course.md</K>
        </Text>
        <References />
        <Notes>
          Leave this up for the whole Q&amp;A. Titles are the pages' real
          titles, so anyone photographing the slide can search the exact
          string later.
          {"\n\n"}
          If someone asks where to start: Resource metrics pipeline explains
          the half of the talk that surprised people most, and Logging in
          Kubernetes is the one that corrects the most misconceptions.
        </Notes>
      </Slide>
    </Deck>
  );
}
