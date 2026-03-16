"""
Integration tests for the full graph.
Requires ANTHROPIC_API_KEY in .env
Run with: pytest tests/test_graph.py -v -s
"""
import pytest
from agents.graph import build_graph, has_positive_ev
from agents.models import StrategistDecision
from tests.fixtures.sample_candle import BULLISH_STATE


class TestConditionalEdge:
    """Tests for the conditional edge — no LLM required."""

    def _make_state_typed(self, decision: StrategistDecision):
        """Helper: mock GraphState with a typed StrategistDecision (primary path)."""
        class FakeAgentResult:
            def __init__(self, d):
                self.structured_output = d

        class FakeNodeResult:
            def __init__(self, d):
                self.result = FakeAgentResult(d)

        class FakeState:
            def __init__(self, d):
                self.results = {"strategist": FakeNodeResult(d)}

        return FakeState(decision)

    def _make_state_text(self, text: str):
        """Helper: mock GraphState with raw text (fallback path)."""
        class FakeAgentResult:
            def __init__(self, t):
                self.structured_output = None
                self._text = t
            def __str__(self):
                return self._text

        class FakeNodeResult:
            def __init__(self, t):
                self.result = FakeAgentResult(t)

        class FakeState:
            def __init__(self, t):
                self.results = {"strategist": FakeNodeResult(t)}

        return FakeState(text)

    def test_go_passes_typed(self):
        """Primary path: typed StrategistDecision with GO."""
        decision = StrategistDecision(decision="GO", probability=0.65, direction="UP", confidence=0.8, reasoning="test")
        assert has_positive_ev(self._make_state_typed(decision)) is True

    def test_no_go_blocked_typed(self):
        """Primary path: typed StrategistDecision with NO_GO."""
        decision = StrategistDecision(decision="NO_GO", probability=0.45, direction="DOWN", confidence=0.6, reasoning="test")
        assert has_positive_ev(self._make_state_typed(decision)) is False

    def test_go_passes_fallback(self):
        """Fallback path: text contains 'decision: go'."""
        assert has_positive_ev(self._make_state_text('{"decision": "GO", "probability": 0.65}')) is True

    def test_no_go_blocked_fallback(self):
        """Fallback path: text contains 'no_go'."""
        assert has_positive_ev(self._make_state_text('{"decision": "NO_GO"}')) is False

    def test_empty_state_blocked(self):
        class EmptyState:
            results = {}
        assert has_positive_ev(EmptyState()) is False


@pytest.mark.asyncio
@pytest.mark.integration
async def test_graph_runs_bullish():
    """
    E2E test: trigger the graph with a bullish scenario.
    Requires ANTHROPIC_API_KEY.
    """
    graph = build_graph()
    result = graph.invoke(
        "Analyze the current BTC 15min candle and determine if there is a positive EV opportunity.",
        invocation_state=BULLISH_STATE,
    )
    assert result is not None
    assert result.status is not None
    assert result.completed_nodes >= 1
    print(f"\nGraph status: {result.status}")
    print(f"Nodes executed: {result.completed_nodes}/{result.total_nodes}")
    print(f"Execution time: {result.execution_time}ms")
