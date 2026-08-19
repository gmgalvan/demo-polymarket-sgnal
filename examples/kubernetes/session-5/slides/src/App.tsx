import { useState } from "react";
import { Deck, Slide, Heading, Text, FlexBox, FullScreen, Notes } from "spectacle";
import { COLORS, deckTheme } from "./theme";
import { Kicker } from "./components/Kicker";
import { Card } from "./components/Card";
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
          height: "58vh",
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
            height: "58vh",
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
            <CopyableCommand command="curl https://finance.gmgalvan.com/health" />
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
            terminalHeight="26vh"
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
            terminalHeight="36vh"
            leftWidth="50%"
            steps={[
              {
                question: "Name the node",
                command: "NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')",
                expect: "Sets $NODE for the next two",
              },
              {
                question: "Its metrics endpoint",
                command: 'RES="/api/v1/nodes/$NODE/proxy/metrics/resource"',
                expect: "Sets $RES",
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
            terminalHeight="36vh"
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

      {/* 12: Our two bugs on the map */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker tone="good">Both of today's bugs</Kicker>
        <Heading fontSize="2rem" color={COLORS.text} textAlign="left" margin="0 0 0.2em 0">
          Two textbook cases
        </Heading>
        <Text fontSize="0.95rem" color={COLORS.dim} textAlign="left" margin="0 0 1rem 0">
          Neither was exotic. Both were already named on this map — same
          stage, same branch, and <K>kubectl describe pod</K> was the command
          for both.
        </Text>
        <TroubleshootFlow highlight={["pending", "crashloop"]} />
        <FlexBox style={{ gap: "1.4rem" }} margin="1.1rem 0 0 0" alignItems="stretch">
          <Card title="Incident #1 → Pending">
            The <K>unbound PVC</K> cause, exactly. No EBS CSI driver, so the
            claim never bound and the Pod never scheduled.
          </Card>
          <Card title="Incident #2 → CrashLoopBackOff">
            The <K>failing liveness probe</K> cause, exactly. The app was fine;
            the probe was pointed at a Mongo-dependent endpoint.
          </Card>
        </FlexBox>
      </Slide>

      {/* 13: Putting it back */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <Kicker>Before we finish</Kicker>
        <Heading fontSize="2rem" color={COLORS.text} textAlign="left" margin="0 0 0.25em 0">
          Put the cluster back
        </Heading>
        <Text fontSize="1rem" color={COLORS.dim} textAlign="left" margin="0 0 1rem 0">
          We installed two things during this session. Removing them is part of
          the work, not an afterthought — and it proves the "before" state was
          real.
        </Text>
        <InvestigationPanel
          terminalHeight="34vh"
          steps={[
            {
              question: "Remove Prometheus, Grafana and Alertmanager",
              command: "helm uninstall monitoring -n monitoring",
              expect: "Everything the chart created, gone",
            },
            {
              question: "And the namespace it lived in",
              command: "kubectl delete namespace monitoring",
              expect: "helm leaves this behind — it did not create it",
            },
            {
              question: "Remove Metrics Server",
              command:
                "kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml",
              expect: "Same manifest, delete instead of apply",
            },
            {
              question: "Confirm we're back where we started",
              command: "kubectl top nodes",
              expect: "error: Metrics API not available — as it was",
            },
          ]}
        />
        <Text fontSize="0.95rem" color={COLORS.dim} margin="1rem 0 0 0" textAlign="left">
          The whole environment — cluster, ALB, volumes, DNS — tears down in
          reverse order. That sequence is written up in <K>course.md</K>.
        </Text>
        <Notes>
          Worth saying plainly: the reason this demo could show `kubectl top`
          failing is that nobody had installed Metrics Server. If we walk away
          leaving it installed, the next person to run this deck gets a
          different story. Cleaning up keeps the lesson reproducible — the same
          applies to the Prometheus stack and the /metrics slide.
          {"\n\n"}
          Note the asymmetry in the first two steps: helm removes what the
          chart created, but not the namespace, because --create-namespace made
          it outside the release. That is a small, real lesson about Helm
          ownership, worth ten seconds if the room is engaged.
          {"\n\n"}
          Same story, one level up: ten monitoring.coreos.com CRDs survive the
          uninstall by design, so that removing a release never deletes the
          custom objects someone else may still be using. Check with
          kubectl get crd | grep monitoring.coreos.com — harmless to leave, and
          if you want them gone you delete them explicitly.
          {"\n\n"}
          If a port-forward is still running in another terminal, it dies on
          its own once the Service disappears.
          {"\n\n"}
          The full teardown order (Kubernetes objects first, so the ALB and the
          EBS volume are released before Terraform destroys the cluster under
          them) is in course.md.
        </Notes>
      </Slide>

      {/* 14: Thanks */}
      <Slide backgroundColor={COLORS.bg} textColor={COLORS.text}>
        <FlexBox height="100%" flexDirection="column" justifyContent="center" alignItems="flex-start">
          <Kicker>Module 5</Kicker>
          <Heading fontSize="3.6rem" color={COLORS.text} textAlign="left">
            Questions?
          </Heading>
          <Text fontSize="1.2rem" color={COLORS.dim} textAlign="left">
            Full incident log: <K>examples/kubernetes/session-5/course.md</K>
          </Text>
        </FlexBox>
      </Slide>
    </Deck>
  );
}
