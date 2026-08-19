import { useState } from "react";
import { Pipeline, type Stage } from "./Pipeline";
import { InvestigationPanel, type Step } from "./InvestigationPanel";

/** A Pipeline that redraws itself partway through the investigation
 * below it.
 *
 * The point being made on the /metrics slide is that the last two stages
 * of the chain do not exist until you install something. Saying that is
 * fine; watching the diagram fill in the moment the install command runs
 * is better - the amber "a collector · you install this" box becomes a
 * green box with the name of the thing that is now actually running.
 *
 * The reveal is driven by which step the presenter clicked, not by a
 * timer and not by polling the cluster: the deck must behave identically
 * whether or not the install actually succeeds, or a failed demo would
 * also break the explanation of why it failed.
 *
 * It is deliberately reversible - clicking back to an earlier step
 * restores the "before" diagram - so the slide can be rehearsed, and so
 * a second run of the talk starts from the honest state.
 */
export function CollectorPipeline({
  before,
  after,
  steps,
  revealAtStep,
  terminalHeight = "360px",
  leftWidth = "52%",
}: {
  /** Stages shown before the install step is reached. */
  before: Stage[];
  /** Stages shown from the install step onwards. Same length as `before`. */
  after: Stage[];
  steps: Step[];
  /** Zero-based index of the step that installs the collector. */
  revealAtStep: number;
  terminalHeight?: string;
  leftWidth?: string;
}) {
  const [installed, setInstalled] = useState(false);

  return (
    <>
      <Pipeline stages={installed ? after : before} />
      <div style={{ marginTop: "0.7rem" }}>
        <InvestigationPanel
          steps={steps}
          terminalHeight={terminalHeight}
          leftWidth={leftWidth}
          onStepChange={(i) => setInstalled(i >= revealAtStep)}
        />
      </div>
    </>
  );
}
