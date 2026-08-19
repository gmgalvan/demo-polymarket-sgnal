import { defaultTheme } from "spectacle";

// Raw colors used directly as props (Slide.backgroundColor/textColor,
// inline spans in <Term>, etc.) rather than through Spectacle's
// primary/secondary/... theme.colors keys - keeps every color use
// explicit instead of depending on which component reads which key.
export const COLORS = {
  bg: "#0b0e14",
  panel: "#121620",
  border: "#232838",
  text: "#dde3ee",
  dim: "#8891a7",
  accent: "#4f8cff",
  accentSoft: "rgba(79, 140, 255, 0.12)",
  good: "#35d488",
  bad: "#ff5d6c",
  warn: "#f5b942",
} as const;

export const FONT_SANS =
  '"Inter", -apple-system, "Segoe UI", Roboto, sans-serif';
export const FONT_MONO =
  '"SF Mono", "Cascadia Code", Consolas, "Liberation Mono", Menlo, monospace';

export const deckTheme = {
  ...defaultTheme,
  fonts: {
    header: FONT_SANS,
    text: FONT_SANS,
    monospace: FONT_MONO,
  },
  fontSizes: {
    h1: "3rem",
    h2: "2.2rem",
    h3: "1.4rem",
    text: "1.15rem",
    monospace: "0.95rem",
  },
};
