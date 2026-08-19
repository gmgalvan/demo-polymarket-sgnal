# slides

A slide deck for **Module 5: Observability, Logging, Monitoring &
Troubleshooting** — React + TypeScript + Vite, using
[Spectacle](https://commerce.nearform.com/open-source/spectacle/) for
the presentation primitives (`Deck`/`Slide`/`CodePane`/...).

The content isn't hypothetical: every command and every log line in
the deck is copied straight out of what actually happened deploying
`session-5` to EKS (see `../course.md` for the full, unabridged
version).

## Run it

```bash
cd examples/kubernetes/session-5/slides
npm install
npm run dev
```

Open the URL Vite prints (usually `http://localhost:5173`).

## Live demo slide (real terminal)

Slide 4, "Live demo", embeds a **real terminal** connected to your
actual shell — same `kubectl` context, same AWS credentials, same
`$SHELL` you already have. It runs whatever you type, for real,
against the real cluster (see `../course.md` for what's actually
running there).

It needs a second process, `server/pty-server.ts`, running alongside
Vite. Either:

```bash
npm run dev:live    # runs both together (Vite + the terminal server)
```

or in two terminals:

```bash
npm run dev     # terminal 1
npm run term    # terminal 2
```

### Running a command during the talk

1. **Click** one of the commands on the left — it copies (and the
   button flashes `✓ copied`).
2. **Right-click** anywhere in the terminal — it pastes at the prompt,
   un-executed.
3. **Enter** — runs it for real.

Use **`⤢ expand`** in the terminal header for anything with long
output (`kubectl describe`, `logs`) — it fills the screen, and the
shell is told the new width, so the output actually reflows instead of
staying wrapped at the narrow size. **Esc** or `⤡ collapse` goes back.
The shell session survives expanding and collapsing.

### Colour

`kubectl` emits no ANSI colour of its own, so its output is monochrome
by default. If [`kubecolor`](https://github.com/kubecolor/kubecolor) is
installed (`brew install kubecolor`), `server/shell-init.sh` aliases
`kubectl` to it for the deck's shell only — the slides still show plain
`kubectl` commands, they just render with green `Running`, red `Error`,
and so on.

That init file is passed as bash's `--rcfile`, and sources your own
`~/.bashrc` first, so your prompt and aliases are unchanged. Non-bash
shells skip it (the server logs a note) and simply get no colour alias.

Pasting prefers the real system clipboard, and falls back to whichever
command you clicked last if the browser blocks clipboard reads (Chrome
prompts for that permission the first time; either answer works, the
flow above is unaffected). You can also just type directly — it's a
normal shell.

**Security note:** `server/pty-server.ts` binds to `127.0.0.1` only —
it's an unauthenticated real shell over that WebSocket, reachable only
from a browser tab on the same machine. Never change that to `0.0.0.0`
or forward the port, especially not on conference wifi.

### Troubleshooting

The terminal's header tells you which of these you're in, and shows a
**retry** button so you can recover without reloading the page:

- **`no server — run npm run term`** — nothing is listening on the
  WebSocket port. Start `npm run term`, then hit retry.
- **`shell exited`** — the connection worked, but the shell ended
  (you typed `exit`, or the server was stopped). Hit retry for a fresh
  shell.
- **`port 3131 is already in use`** — a previous `pty-server` is still
  alive. Either just use it (the deck will connect to it fine), or
  `pkill -f "server/pty-server"`. To run on another port:
  `PTY_PORT=3132 npm run term` plus `VITE_PTY_WS_URL=ws://localhost:3132`
  for Vite.
- Navigating away from a terminal slide and back opens a **fresh** shell session
  (the old one is killed on unmount) — `cd` back if you need to.

## Controls

Spectacle's `Deck` handles navigation natively:

| Key | Action |
|---|---|
| `→` / `Space` | Next slide |
| `←` | Previous slide |
| Click the fullscreen icon (bottom-right) | Toggle fullscreen |

The current slide is reflected in the URL hash — refreshing mid-talk
doesn't lose your place.

## Build

```bash
npm run build     # tsc -b && vite build -> dist/
npm run preview   # serve the production build locally
```

## Deck outline

Two sections, 15 slides.

1. Title
2. **▸ Monitoring & Logging**
3. Architecture diagram — animated: a dot travels the real request path
4. Live demo — real terminal, real cluster
5. Where a log line actually goes — and where it stops
6. Where would CPU and memory come from? — the kubelet is already
   producing; the aggregated API answers `NotFound`
7. **Install the missing piece** — one manifest, then the exact same
   question that just failed
8. Now the comfortable view — `kubectl top`, and measured vs declared
9. The taxonomy — six questions, six answers, all clickable
10. `/metrics` and Prometheus-style collection
11. **▸ Troubleshooting**
12. The Pod → Service → Ingress decision tree
13. Two real incidents pinned to that map
14. Put the cluster back — remove Metrics Server
15. Q&A

See `PRESENTING.md` for a slide-by-slide speaking guide.

## Structure

```
server/
├── pty-server.ts            # WebSocket <-> real shell, localhost only
└── shell-init.sh             # bash --rcfile: sources ~/.bashrc + kubecolor alias

src/
├── theme.ts                # colors, fonts, Spectacle deck theme
├── App.tsx                   # the 15 <Slide> elements
├── main.tsx
└── components/
    ├── Kicker.tsx             # small colored label (e.g. "Incident #1")
    ├── Term.tsx                # terminal-output block + colored <Span>
    ├── Card.tsx                 # two-column comparison card
    ├── SectionDivider.tsx        # section-break slide contents
    ├── CopyableCommand.tsx       # click-to-copy shell command
    ├── LiveTerminal.tsx           # xterm.js, connects to server/pty-server.ts
    ├── ArchitectureDiagram.tsx     # SVG: AWS → EKS → namespace, and the EBS volume
    ├── TroubleshootFlow.tsx         # the Pod→Service→Ingress decision tree
    ├── ObservabilityTaxonomy.tsx     # logs / Events / metrics / traces / business data
    ├── InvestigationPanel.tsx         # numbered questions + wired-up terminal
    └── Pipeline.tsx                   # labelled stage chains for the metrics pipelines
```

Official Kubernetes documentation links live in Spectacle `<Notes>` on
the slides they support (press the presenter-mode key to see them), not
on a bibliography slide.

`TroubleshootFlow` is data-driven and takes a `highlight` prop, so the
plain map (slide 10) and the annotated one (slide 11) are the same
component and can't drift apart. Its structure follows
[learnkube.com/troubleshooting-deployments](https://learnkube.com/troubleshooting-deployments).
