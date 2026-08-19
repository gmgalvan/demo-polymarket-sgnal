import { FlexBox, Heading, Text } from "spectacle";
import { COLORS, FONT_MONO } from "../theme";

/** Contents of a section-break slide.
 *
 * Deliberately not a <Slide> itself: Spectacle's Deck injects props into
 * its direct children to build the slide list, so wrapping Slide in a
 * custom component makes the deck miscount. Use it inside a Slide:
 *
 *   <Slide ...><SectionDivider n="01" title="Troubleshooting" /></Slide>
 */
export function SectionDivider({
  n,
  title,
  subtitle,
}: {
  n?: string;
  title: string;
  subtitle?: string;
}) {
  return (
    <FlexBox
      height="100%"
      flexDirection="column"
      justifyContent="center"
      alignItems="flex-start"
    >
      {n && (
        <Text
          fontFamily={FONT_MONO}
          fontSize="1rem"
          color={COLORS.accent}
          letterSpacing="0.2em"
          margin="0 0 0.6em 0"
        >
          {n}
        </Text>
      )}
      <Heading
        fontSize="4rem"
        color={COLORS.text}
        textAlign="left"
        margin="0"
        letterSpacing="-0.02em"
      >
        {title}
      </Heading>
      {subtitle && (
        <Text
          fontSize="1.25rem"
          color={COLORS.dim}
          textAlign="left"
          maxWidth="42rem"
          margin="0.8em 0 0 0"
        >
          {subtitle}
        </Text>
      )}
      <div
        style={{
          width: "5rem",
          height: "3px",
          background: COLORS.accent,
          marginTop: "2rem",
          borderRadius: "2px",
        }}
      />
    </FlexBox>
  );
}
