# Presenting guide

Slide-by-slide notes: what to say, what to run live, and where the
receipts are in `../course.md`. 12 slides across two sections.

## 1. Title

Frame it: this is a real system, deployed to a real EKS cluster, and
everything you're about to see is either running right now or was
genuinely observed while building it. Nothing is mocked.

## 2. ▸ Monitoring & Logging

Section break. One line: "first, what the system is and how we watch it
while it's healthy."

## 3. The architecture

The one slide people photograph. Walk it left to right, then land on
the nesting: AWS ⊃ cluster ⊃ namespace — and the **EBS volume is drawn
outside the cluster boundary on purpose**. The volume outlives the Pod,
the node, and the cluster.

One `m7g.large` Graviton node runs all of it. No GPU in the picture.

## 4. Live demo

A real terminal (`server/pty-server.ts`) on your actual shell and
kubectl context. Click a command, right-click the terminal to paste,
Enter to run.

**Before you go on stage:** run `npm run dev:live` (not just
`npm run dev`) and confirm the header says "connected".

## 5. The taxonomy — the interactive one

The centrepiece of this section. The table is also a launcher: **click a
question** and the terminal expands with that question's real command
typed at the prompt, *unrun*. Read it aloud, then press Enter.

Suggested run order:

1. *What did the application say?* → `kubectl logs`. The app's own voice.
2. *What did Kubernetes do to it?* → `describe` → Events. A different
   witness. This is the distinction most people never make.
3. *What are users actually asking?* → `/queries`. Business telemetry,
   not logs — say that explicitly.
4. *How much CPU and memory?* → `kubectl top`. **It will fail.** Let it.
   That's the next slide.

Tracing is greyed out and unclickable because this demo genuinely has no
tracing. Don't pretend otherwise.

Reference (in speaker notes): Kubernetes — Observability.

## 6. `kubectl top` and Metrics Server

The failure from the previous slide, explained. `error: Metrics API not
available` is real — Metrics Server was never installed. Same shape as a
StorageClass with no CSI driver behind it: **the interface ships with
Kubernetes, the implementation doesn't.**

Say plainly: Metrics Server is *not* Prometheus. Current CPU/memory via
`metrics.k8s.io`, no history.

Reference: Resource Metrics Pipeline.

## 7. The resource metrics pipeline — the payoff slide

The previous slide showed `kubectl top` failing. This one finds out
exactly *which* link is broken, live. Three clickable questions:

1. **Is the standard Metrics API registered?** → only an EKS extension
   comes back. No `metrics.k8s.io`.
2. **Ask it anyway** → `NotFound`. Nothing implements it.
3. **So does the data exist at all?** → ask the kubelet directly, and
   real working-set memory for *our own* api / frontend / mongo
   containers scrolls past.

Land step 3 hard: **the numbers were there the whole time.** cAdvisor
inside the kubelet already collects them; the kubelet already publishes
them at `/metrics/resource`. What's missing is the component that
scrapes every kubelet and serves the aggregate through `metrics.k8s.io`
— Metrics Server, an add-on.

While step 3's output is on screen, name what you're looking at: CPU is
a rate over a cumulative counter averaged across a window (~30s), memory
is the *working set* — roughly what can't be freed under pressure. Two
resources only, deliberately: this pipeline exists to feed `kubectl
top`, HPA and VPA, not to be a monitoring system.

Reference: Resource Metrics Pipeline.

## 8. `/metrics` and Prometheus-style collection

The trap to say out loud: components exposing Prometheus-compatible
metrics does **not** mean Prometheus is installed. Nothing scrapes those
endpoints until you deploy something that does.

References: System Metrics, Metrics Reference.

## 9. ▸ Troubleshooting

Section break. "Now: when it breaks, where do you look first?"

## 10. The decision tree

Bottom-up: Pod, then Service, then Ingress. From a browser a broken Pod
and a broken Ingress look identical — that's why people waste time
starting at the top.

Reference: learnkube.com/troubleshooting-deployments

## 11. Two real incidents on the map

Both bugs hit while deploying this app, and both were already named on
the map: "unbound PVC" is a listed cause of `Pending`; "failing liveness
probe" is a listed cause of `CrashLoopBackOff`. Both in stage 1, both
found with `kubectl describe pod`.

The honest framing: *we didn't find anything clever — we found two
things this map already predicted. That's the argument for the map.*

Full write-up of both: `../course.md`.

## 12. Q&A

Point at `course.md` for full commands, real error messages, and the
teardown order.
