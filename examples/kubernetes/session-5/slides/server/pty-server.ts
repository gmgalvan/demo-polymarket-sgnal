// Spawns a real shell (your actual $SHELL, your actual kubeconfig, your
// actual AWS credentials) and streams it over a WebSocket to the
// <LiveTerminal> component in the deck. Runs on the PRESENTER's own
// machine, alongside `npm run dev` - not deployed anywhere, not part
// of the built site.
//
// Security: binds to 127.0.0.1 ONLY. This is an unauthenticated shell
// over that socket - never change HOST to 0.0.0.0 or expose this port
// on conference wifi. It's meant to be reachable only from the browser
// tab running on the same laptop.
import { fileURLToPath } from "node:url";
import path from "node:path";
import { WebSocketServer, type WebSocket } from "ws";
import pty from "node-pty";

const HOST = "127.0.0.1";
const PORT = Number(process.env.PTY_PORT ?? 3131);

const SHELL = process.env.SHELL ?? "bash";
const INIT_FILE = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "shell-init.sh",
);

/** bash's --rcfile gets us the kubecolor alias without touching the
 * user's real dotfiles. Other shells have no equivalent single-file
 * flag that also preserves their own startup files, so they just get a
 * plain shell - everything still works, kubectl output is just
 * monochrome. */
const shellArgs = /(^|\/)bash$/.test(SHELL) ? ["--rcfile", INIT_FILE, "-i"] : [];

const wss = new WebSocketServer({ host: HOST, port: PORT });

// A stray server from a previous run is the likeliest failure here, and
// the default unhandled-'error' stack trace is the last thing anyone
// wants to read two minutes before a talk. Say what to do instead.
wss.on("error", (error: NodeJS.ErrnoException) => {
  if (error.code === "EADDRINUSE") {
    console.error(
      `[pty-server] port ${PORT} is already in use.\n` +
        `[pty-server] Another pty-server is probably still running - either use it as-is,\n` +
        `[pty-server] or stop it with:  pkill -f "server/pty-server"\n` +
        `[pty-server] Or pick a different port:  PTY_PORT=3132 npm run term\n` +
        `[pty-server] (then set VITE_PTY_WS_URL=ws://localhost:3132 for the deck)`,
    );
  } else {
    console.error(`[pty-server] ${error.message}`);
  }
  process.exit(1);
});

// On 'listening', not at module top level: binding is async, so logging
// eagerly would claim success even when the bind is about to fail.
wss.on("listening", () => {
  console.log(`[pty-server] listening on ws://${HOST}:${PORT} (localhost only)`);
  console.log(`[pty-server] spawning ${SHELL} per connection`);
  if (shellArgs.length === 0) {
    console.log(
      `[pty-server] note: not bash, so shell-init.sh (kubecolor alias) is skipped`,
    );
  }
});

type ResizeMessage = { resize: [number, number] };

function isResizeMessage(value: unknown): value is ResizeMessage {
  return (
    typeof value === "object" &&
    value !== null &&
    Array.isArray((value as ResizeMessage).resize) &&
    (value as ResizeMessage).resize.length === 2
  );
}

/** The shell's environment, minus anything that would corrupt piped
 * output.
 *
 * `concurrently` (what `npm run dev:live` uses) exports FORCE_COLOR=3 to
 * make its children emit colour. That leaks all the way down into
 * kubecolor, which then colours output even when stdout is a PIPE -
 * prepending an escape sequence to the payload and breaking anything
 * that parses it:
 *
 *   kubectl get --raw /apis/... | jq
 *   -> parse error: Invalid numeric literal at line 1, column 2
 *
 * Stripping it here rather than in shell-init.sh so it also applies to
 * non-bash shells, which never read that file. Interactive colour is
 * unaffected: tools still detect the pty on their own.
 */
function shellEnv(): Record<string, string> {
  const env = { ...process.env } as Record<string, string>;
  delete env.FORCE_COLOR;
  return env;
}

wss.on("connection", (socket: WebSocket) => {
  const term = pty.spawn(SHELL, shellArgs, {
    name: "xterm-256color",
    cols: 100,
    rows: 30,
    cwd: process.env.HOME,
    env: shellEnv(),
  });

  console.log(`[pty-server] shell spawned, pid=${term.pid}`);

  term.onData((data) => {
    if (socket.readyState === socket.OPEN) socket.send(data);
  });

  term.onExit(({ exitCode }) => {
    console.log(`[pty-server] shell exited, code=${exitCode}`);
    if (socket.readyState === socket.OPEN) socket.close();
  });

  socket.on("message", (raw) => {
    const text = raw.toString();
    try {
      const parsed: unknown = JSON.parse(text);
      if (isResizeMessage(parsed)) {
        term.resize(parsed.resize[0], parsed.resize[1]);
        return;
      }
    } catch {
      // Not JSON - a normal keystroke/paste, fall through and write it raw.
    }
    term.write(text);
  });

  socket.on("close", () => {
    term.kill();
  });
});
