import { useEffect, useRef, useState } from "react";
import { Terminal as XTerm } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";
import { COLORS, FONT_MONO } from "../theme";
import { readClipboardText } from "../clipboard";

const WS_URL = import.meta.env.VITE_PTY_WS_URL ?? "ws://localhost:3131";

/** Full 16-colour ANSI palette, tuned to the deck's own colours instead
 * of xterm.js's defaults (whose red/green are muddy on this background
 * and read as brown/olive from the back of a room). Anything that emits
 * colour - the shell prompt, `ls`, `git`, `grep --color`, kubecolor -
 * picks these up. Note that plain `kubectl` emits no ANSI at all, so its
 * output stays monochrome regardless; see README. */
const TERMINAL_THEME = {
  background: "#05070c",
  foreground: COLORS.text,
  cursor: COLORS.accent,
  cursorAccent: "#05070c",
  selectionBackground: "rgba(79, 140, 255, 0.3)",

  black: "#1b1f2b",
  red: "#ff6b78",
  green: "#3ddb8f",
  yellow: "#f5c24c",
  blue: "#5f97ff",
  magenta: "#c98bff",
  cyan: "#3fd0d6",
  white: "#c6cddd",

  brightBlack: "#5c6478",
  brightRed: "#ff8f99",
  brightGreen: "#6ff0ae",
  brightYellow: "#ffd77a",
  brightBlue: "#8fb6ff",
  brightMagenta: "#dcaeff",
  brightCyan: "#7ae7eb",
  brightWhite: "#f2f5fb",
};

/** `unavailable` (never connected: server isn't running) is deliberately
 * distinct from `closed` (was connected, the shell exited). A failed
 * connection fires onerror *and then* onclose, so collapsing the two
 * would report "shell closed" for the most common case - the server not
 * being started - which points at exactly the wrong problem. */
type Status = "connecting" | "connected" | "closed" | "unavailable";

/** Ask the terminal to type a command at the prompt, without running it.
 *
 * `nonce` exists so clicking the same row twice still fires: comparing
 * the command string alone would look unchanged and do nothing the
 * second time. */
export type TerminalRequest = { command: string; nonce: number };

/** A real shell, streamed from server/pty-server.ts over a WebSocket.
 * Requires `npm run term` (or `npm run dev:live`) running alongside the
 * Vite dev server - see ../../README.md. Fresh shell process per mount,
 * so navigating away from this slide and back starts a new session. */
export function LiveTerminal({
  height = "100%",
  request,
}: {
  height?: string;
  request?: TerminalRequest;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  // Held in a ref so the request effect below can write to the same
  // socket the mount effect opened, without re-running that effect and
  // killing the shell.
  const socketRef = useRef<WebSocket | null>(null);
  const [status, setStatus] = useState<Status>("connecting");
  // Bumping this re-runs the effect: a fresh socket and a fresh shell,
  // so a mid-talk recovery doesn't need a full page reload.
  const [attempt, setAttempt] = useState(0);
  // Expanding only restyles the existing wrapper - it must NOT remount
  // the container div, or xterm would be re-created and the running
  // shell session lost. The ResizeObserver below then re-fits and tells
  // the pty the new size, so long output (kubectl describe) reflows to
  // the wider terminal instead of staying wrapped at the old width.
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    const node = containerRef.current;
    if (!node) return;

    setStatus("connecting");
    let hasOpened = false;

    const term = new XTerm({
      fontFamily: FONT_MONO,
      fontSize: 14,
      lineHeight: 1.3,
      cursorBlink: true,
      convertEol: true,
      theme: TERMINAL_THEME,
    });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(node);

    const socket = new WebSocket(WS_URL);
    socketRef.current = socket;

    // Re-fits and tells the pty (server-side) the real terminal size,
    // so the shell's own line-wrapping (what `kubectl`/bash think the
    // width is) matches what xterm.js actually renders. Anything short
    // of that and output wraps at the wrong column even though there's
    // visibly more room.
    function syncSize() {
      fit.fit();
      if (socket.readyState === WebSocket.OPEN) {
        socket.send(JSON.stringify({ resize: [term.cols, term.rows] }));
      }
    }

    // Fit once synchronously (best effort) and again on the next frame,
    // once the Slide's own layout/transition has actually settled - a
    // fit() taken mid-transition can compute too few columns.
    syncSize();
    requestAnimationFrame(syncSize);

    socket.onopen = () => {
      hasOpened = true;
      setStatus("connected");
      syncSize();
    };
    socket.onmessage = (event) => term.write(event.data as string);
    // onclose fires for both a real shell exit and a connection that
    // never opened, so hasOpened is what tells them apart.
    socket.onclose = () => setStatus(hasOpened ? "closed" : "unavailable");
    socket.onerror = () => {
      if (!hasOpened) setStatus("unavailable");
    };

    const dataSub = term.onData((data) => {
      if (socket.readyState === WebSocket.OPEN) socket.send(data);
    });

    // Right-click pastes, so the flow is: click a command to copy ->
    // right-click here -> Enter. preventDefault kills the browser's own
    // context menu, which would otherwise cover the terminal.
    async function handleContextMenu(event: MouseEvent) {
      event.preventDefault();
      const text = await readClipboardText();
      if (text && socket.readyState === WebSocket.OPEN) socket.send(text);
    }
    node.addEventListener("contextmenu", handleContextMenu);

    const resizeObserver = new ResizeObserver(syncSize);
    resizeObserver.observe(node);

    return () => {
      node.removeEventListener("contextmenu", handleContextMenu);
      resizeObserver.disconnect();
      dataSub.dispose();
      socket.close();
      socketRef.current = null;
      term.dispose();
    };
  }, [attempt]);

  // A parent asked for a command: type it at the prompt WITHOUT a
  // trailing newline. Deliberately not executed - the presenter reads it
  // out, then presses Enter when ready, and can edit it first (add a -f,
  // change a label) if the room asks.
  //
  // Deliberately does NOT expand. It used to, from when the terminal was
  // a thin strip under the content; now that it sits full-height beside
  // it, auto-expanding covers the very question that was just clicked.
  // Expanding stays a decision the presenter makes, via the header
  // button or its keyboard shortcut.
  useEffect(() => {
    if (!request) return;
    const socket = socketRef.current;
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    // Ctrl+U first, so clicking a second row replaces whatever is
    // already sitting on the prompt instead of appending to it.
    socket.send("\x15" + request.command);
  }, [request]);

  // Escape collapses, matching every other fullscreen overlay. Capture
  // phase so it wins before xterm turns Escape into \x1b for the shell -
  // only while expanded, so a normal-size terminal still passes Escape
  // through to whatever is running in it.
  useEffect(() => {
    if (!expanded) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.stopPropagation();
        event.preventDefault();
        setExpanded(false);
      }
    }
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [expanded]);

  return (
    <div
      style={{
        ...(expanded
          ? {
              position: "fixed",
              inset: "3vh 3vw",
              zIndex: 100,
              boxShadow: "0 24px 80px rgba(0, 0, 0, 0.65)",
            }
          : { height, width: "100%" }),
        display: "flex",
        flexDirection: "column",
        border: `1px solid ${expanded ? COLORS.accent : COLORS.border}`,
        borderRadius: "10px",
        overflow: "hidden",
        background: "#05070c",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          gap: "0.5rem",
          padding: "0.45rem 0.9rem",
          borderBottom: `1px solid ${COLORS.border}`,
          fontFamily: FONT_MONO,
          fontSize: "0.75rem",
          color: COLORS.dim,
        }}
      >
        <span style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
          <StatusDot status={status} />
          {status === "connecting" && "connecting…"}
          {status === "connected" && "connected"}
          {status === "closed" && "shell exited"}
          {status === "unavailable" && "no server — run `npm run term`"}
        </span>
        <span style={{ display: "flex", alignItems: "center", gap: "0.7rem" }}>
          {status === "connected" && (
            <span style={{ opacity: 0.75 }}>right-click to paste</span>
          )}
          {status !== "connected" && status !== "connecting" && (
            <HeaderButton onClick={() => setAttempt((n) => n + 1)}>
              retry
            </HeaderButton>
          )}
          <HeaderButton onClick={() => setExpanded((v) => !v)} accent={expanded}>
            {expanded ? "⤡ collapse  (esc)" : "⤢ expand"}
          </HeaderButton>
        </span>
      </div>
      <div
        ref={containerRef}
        style={{ flex: 1, minHeight: 0, padding: "0.5rem 0.7rem" }}
      />
    </div>
  );
}

function HeaderButton({
  onClick,
  accent = false,
  children,
}: {
  onClick: () => void;
  accent?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      style={{
        fontFamily: FONT_MONO,
        fontSize: "0.72rem",
        color: accent ? COLORS.bg : COLORS.accent,
        background: accent ? COLORS.accent : "transparent",
        border: `1px solid ${accent ? COLORS.accent : COLORS.border}`,
        borderRadius: "5px",
        padding: "0.15rem 0.6rem",
        cursor: "pointer",
        whiteSpace: "nowrap",
      }}
    >
      {children}
    </button>
  );
}

function StatusDot({ status }: { status: Status }) {
  const color =
    status === "connected"
      ? COLORS.good
      : status === "unavailable"
        ? COLORS.bad
        : COLORS.warn;
  return (
    <span
      style={{
        display: "inline-block",
        width: "8px",
        height: "8px",
        borderRadius: "50%",
        background: color,
      }}
    />
  );
}
