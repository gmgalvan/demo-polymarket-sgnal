import type { ReactNode } from "react";
import { Box } from "spectacle";
import { COLORS, FONT_MONO } from "../theme";

/** A terminal-output block. Pass colored <Span tone="..."> children to
 * highlight specific words (status values, error text) the way a real
 * terminal would - CodePane's syntax highlighting is for actual code,
 * this is for command output. */
export function Term({ children }: { children: ReactNode }) {
  return (
    <Box
      backgroundColor="#05070c"
      border={`1px solid ${COLORS.border}`}
      borderRadius="10px"
      padding="0.9rem 1.3rem"
      margin="1rem 0 0 0"
      fontFamily={FONT_MONO}
      fontSize="0.92rem"
      lineHeight="1.6"
      style={{ whiteSpace: "pre-wrap" }}
    >
      {children}
    </Box>
  );
}

const TONES = {
  prompt: COLORS.accent,
  ok: COLORS.good,
  err: COLORS.bad,
  warn: COLORS.warn,
  dim: COLORS.dim,
  text: COLORS.text,
} as const;

export function Span({
  tone = "text",
  children,
}: {
  tone?: keyof typeof TONES;
  children: ReactNode;
}) {
  return <span style={{ color: TONES[tone] }}>{children}</span>;
}
