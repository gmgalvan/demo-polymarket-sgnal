import type { ReactNode } from "react";
import { Box, Heading, Text } from "spectacle";
import { COLORS } from "../theme";

const TONE_BORDER = {
  neutral: COLORS.border,
  good: "rgba(53, 212, 136, 0.35)",
  bad: "rgba(255, 93, 108, 0.35)",
} as const;

export function Card({
  title,
  tone = "neutral",
  children,
}: {
  title: string;
  tone?: keyof typeof TONE_BORDER;
  children: ReactNode;
}) {
  return (
    <Box
      backgroundColor={COLORS.panel}
      border={`1px solid ${TONE_BORDER[tone]}`}
      borderRadius="12px"
      padding="1.3rem 1.5rem"
      flex="1"
    >
      <Heading fontSize="1.1rem" color={COLORS.text} margin="0 0 0.6em 0">
        {title}
      </Heading>
      <Text fontSize="1rem" color={COLORS.dim} margin="0" lineHeight="1.5">
        {children}
      </Text>
    </Box>
  );
}
