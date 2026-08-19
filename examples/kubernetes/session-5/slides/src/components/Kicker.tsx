import type { ReactNode } from "react";
import { Text } from "spectacle";
import { COLORS, FONT_MONO } from "../theme";

const TONES = {
  neutral: COLORS.accent,
  good: COLORS.good,
  bad: COLORS.bad,
  warn: COLORS.warn,
} as const;

export function Kicker({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: keyof typeof TONES;
}) {
  return (
    <Text
      fontFamily={FONT_MONO}
      fontSize="0.85rem"
      letterSpacing="0.12em"
      textTransform="uppercase"
      color={TONES[tone]}
      margin="0 0 0.6em 0"
    >
      {children}
    </Text>
  );
}
