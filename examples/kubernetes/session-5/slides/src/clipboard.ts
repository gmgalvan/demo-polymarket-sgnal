/** Last command copied via <CopyableCommand>, kept in module scope so
 * <LiveTerminal>'s right-click-to-paste can fall back to it.
 *
 * Why a fallback at all: right-click paste ideally reads the real system
 * clipboard, but `navigator.clipboard.readText()` needs an explicit
 * browser permission prompt, and a denied/dismissed prompt mid-talk
 * would silently break the demo. Remembering what was just clicked
 * makes the copy -> right-click flow work regardless of that prompt.
 */
let lastCopied = "";

export function setLastCopied(text: string) {
  lastCopied = text;
}

export function getLastCopied() {
  return lastCopied;
}

/** Real clipboard first, last-clicked command second. */
export async function readClipboardText(): Promise<string> {
  try {
    const text = await navigator.clipboard.readText();
    if (text) return text;
  } catch {
    // Permission denied / unavailable - fall through.
  }
  return getLastCopied();
}
