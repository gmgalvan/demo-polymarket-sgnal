"""
Unit tests for the Broadcaster node.
No LLM or network required — pure math.
"""
import pytest
from agents.broadcaster.node import calculate_ev_kelly, _parse_decision, BroadcasterNode
from tests.fixtures.sample_candle import BULLISH_STATE

VALID_DECISION_JSON = '{"decision": "GO", "probability": 0.65, "direction": "UP", "confidence": 0.80, "reasoning": "RSI oversold, bullish crossover."}'


class TestEVKelly:
    def test_positive_ev(self):
        """Probability 0.65, odds 1.68 → positive EV."""
        ev_pct, kelly = calculate_ev_kelly(probability=0.65, odds=1.68)
        assert ev_pct > 0
        assert kelly > 0

    def test_negative_ev(self):
        """Probability 0.40, odds 1.50 → negative EV → kelly = 0."""
        ev_pct, kelly = calculate_ev_kelly(probability=0.40, odds=1.50)
        assert ev_pct < 0
        assert kelly == 0.0

    def test_breakeven(self):
        """Probability exactly equal to implied odds → EV ≈ 0."""
        odds = 2.00
        implied_prob = 1 / odds  # 0.50
        ev_pct, kelly = calculate_ev_kelly(probability=implied_prob, odds=odds)
        assert abs(ev_pct) < 0.1
        assert kelly == 0.0

    def test_kelly_capped(self):
        """Kelly never exceeds 1.0 with reasonable probabilities."""
        _, kelly = calculate_ev_kelly(probability=0.99, odds=2.0)
        assert kelly <= 1.0

    def test_known_values(self):
        """Manually calculated values to verify the implementation."""
        # prob=0.60, odds=1.65 → b=0.65, ev=0.60*0.65 - 0.40 = 0.39 - 0.40 = -0.01
        ev_pct, kelly = calculate_ev_kelly(probability=0.60, odds=1.65)
        assert abs(ev_pct - (-1.0)) < 0.1
        assert kelly == 0.0

        # prob=0.65, odds=1.65 → b=0.65, ev=0.65*0.65 - 0.35 = 0.4225 - 0.35 = 0.0725
        ev_pct, kelly = calculate_ev_kelly(probability=0.65, odds=1.65)
        assert abs(ev_pct - 7.25) < 0.1
        assert kelly > 0


class TestParseDecision:
    def test_valid_json(self):
        """Valid StrategistDecision JSON is deserialized correctly."""
        decision = _parse_decision(VALID_DECISION_JSON)
        assert decision.decision == "GO"
        assert decision.probability == 0.65
        assert decision.direction == "UP"
        assert decision.confidence == 0.80

    def test_no_go_json(self):
        """NO_GO decision is deserialized correctly."""
        text = '{"decision": "NO_GO", "probability": 0.45, "direction": "DOWN", "confidence": 0.60, "reasoning": "No edge."}'
        decision = _parse_decision(text)
        assert decision.decision == "NO_GO"
        assert decision.probability == 0.45

    def test_invalid_json_fallback(self):
        """Falls back gracefully when JSON is invalid."""
        decision = _parse_decision("this is not json at all")
        assert decision.decision == "GO"  # fallback is conservative GO
        assert 0.0 <= decision.probability <= 1.0


@pytest.mark.asyncio
async def test_broadcaster_node_runs():
    """BroadcasterNode runs end-to-end with a valid structured decision."""
    node = BroadcasterNode()
    result = await node.invoke_async(VALID_DECISION_JSON, invocation_state=BULLISH_STATE)
    assert result is not None


@pytest.mark.asyncio
async def test_broadcaster_produces_signal_fields(capsys):
    """Broadcaster emits signal with all required fields to stdout."""
    node = BroadcasterNode()
    result = await node.invoke_async(VALID_DECISION_JSON, invocation_state=BULLISH_STATE)
    output = capsys.readouterr().out
    assert "BUY" in output or "SELL" in output
    assert "EV" in output
    assert "Kelly" in output
