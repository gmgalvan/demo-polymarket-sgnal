"""
Strands Graph assembly.

Flow:
  Watchdog → graph.invoke() → [Strategist] → (conditional edge) → [Broadcaster]

The conditional edge (has_positive_ev) checks whether the Strategist returned "GO".
If not, the graph completes without emitting a signal.
"""
from strands.multiagent import GraphBuilder
from strands.multiagent.graph import GraphState

from agents.config import GRAPH_EXECUTION_TIMEOUT, GRAPH_MAX_NODE_EXECUTIONS
from agents.models import StrategistDecision
from agents.strategist.agent import build_strategist
from agents.broadcaster.node import BroadcasterNode


def has_positive_ev(state: GraphState) -> bool:
    """
    Conditional edge: only proceed to the Broadcaster if the Strategist said GO.

    Uses structured_output (StrategistDecision) for a type-safe check.
    No LLM involved — takes microseconds.
    """
    node_result = state.results.get("strategist")
    if not node_result:
        return False

    agent_result = node_result.result

    # Primary: use the typed structured output
    decision: StrategistDecision | None = getattr(agent_result, "structured_output", None)
    if decision is not None:
        return decision.decision == "GO"

    # Fallback: text check if structured_output is unavailable
    return '"decision": "go"' in str(agent_result).lower()


def build_graph():
    """
    Build and return the Strategist → Broadcaster graph.

    Usage:
        graph = build_graph()
        result = graph.invoke("Analyze BTC 15min candle", invocation_state={...})
    """
    strategist = build_strategist()
    broadcaster = BroadcasterNode()

    builder = GraphBuilder()

    builder.add_node(strategist, "strategist")
    builder.add_node(broadcaster, "broadcaster")

    # Only proceed to Broadcaster if +EV
    builder.add_edge("strategist", "broadcaster", condition=has_positive_ev)

    builder.set_entry_point("strategist")
    builder.set_execution_timeout(GRAPH_EXECUTION_TIMEOUT)
    builder.set_max_node_executions(GRAPH_MAX_NODE_EXECUTIONS)

    return builder.build()
