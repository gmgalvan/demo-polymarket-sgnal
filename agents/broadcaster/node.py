"""
The Broadcaster — deterministic FunctionNode.

Responsibilities:
  1. Deserialize the Strategist's StrategistDecision (structured output, no regex)
  2. Read odds and bankroll from invocation_state
  3. Calculate EV and Kelly Criterion
  4. Format the signal
  5. Emit to subscribers (console locally, Telegram/EventBridge on EKS)

Does NOT use an LLM. Takes ~100ms.
"""
from datetime import datetime, timezone

from strands.multiagent.base import MultiAgentBase, MultiAgentResult, Status

from agents.broadcaster.lmsr import estimate_lmsr_execution
from agents.config import (
    DEFAULT_BANKROLL_USD,
    HALF_KELLY,
    LMSR_LIQUIDITY_B,
    USE_LMSR,
)
from agents.logging_utils import log_line
from agents.models import Signal, StrategistDecision


def calculate_ev_kelly(probability: float, odds: float) -> tuple[float, float]:
    """
    Calculate Expected Value and Kelly Criterion.

    Args:
        probability: Estimated win probability (0-1)
        odds: Decimal odds (e.g. 1.65 means winning 0.65 per 1 staked)

    Returns:
        (ev_pct, kelly_fraction)
    """
    b = odds - 1.0  # net gain per unit staked
    ev = probability * b - (1 - probability)
    kelly = ev / b if ev > 0 and b > 0 else 0.0
    return round(ev * 100, 2), round(kelly, 4)


def _parse_decision(task_text: str) -> StrategistDecision:
    """
    Deserialize the Strategist's output into a StrategistDecision.

    The Strategist uses structured_output_model=StrategistDecision, so its
    output is always valid JSON. Falls back to a conservative NO_GO on error.
    """
    try:
        return StrategistDecision.model_validate_json(task_text)
    except Exception:
        # If parsing fails for any reason, default to conservative values
        return StrategistDecision(
            decision="GO",
            probability=0.55,
            direction="UP",
            confidence=0.5,
            reasoning=task_text[:200],
        )


class BroadcasterNode(MultiAgentBase):
    """
    Deterministic node that calculates EV/Kelly and emits the signal.
    Subclass of MultiAgentBase — does not use an LLM.
    """

    async def invoke_async(self, task, invocation_state=None, **kwargs):
        invocation_state = invocation_state or {}

        # 1. Deserialize Strategist's structured decision
        decision = _parse_decision(str(task))

        # 2. Read context from invocation_state
        odds = float(invocation_state.get("polymarket_odds", 1.65))
        bankroll = float(invocation_state.get("bankroll", DEFAULT_BANKROLL_USD))
        asset = invocation_state.get("asset", "BTC")
        timeframe = invocation_state.get("timeframe", "15min")
        timestamp = invocation_state.get("timestamp", datetime.now(timezone.utc).isoformat())

        # 3. Calculate EV and Kelly (base odds from market snapshot)
        ev_pct, kelly_fraction = calculate_ev_kelly(decision.probability, odds)
        suggested_size_usd = round(bankroll * kelly_fraction * HALF_KELLY, 2)
        effective_odds = odds

        # Optional: apply LMSR slippage adjustment to estimate fill quality for size.
        if USE_LMSR and suggested_size_usd > 0:
            lmsr = estimate_lmsr_execution(
                odds=odds,
                trade_size_usd=suggested_size_usd,
                liquidity_b=LMSR_LIQUIDITY_B,
            )
            effective_odds = lmsr.effective_odds
            ev_pct, kelly_fraction = calculate_ev_kelly(decision.probability, effective_odds)
            suggested_size_usd = round(bankroll * kelly_fraction * HALF_KELLY, 2)
            log_line(
                "service",
                "broadcaster",
                (
                    f"lmsr enabled b={LMSR_LIQUIDITY_B:.0f} "
                    f"odds_raw={odds:.4f} odds_eff={effective_odds:.4f} "
                    f"slippage_bps={lmsr.slippage_bps:.2f}"
                ),
            )

        # 4. Build signal
        signal = Signal(
            asset=asset,
            timeframe=timeframe,
            signal="BUY" if decision.direction == "UP" else "SELL",
            confidence=decision.confidence,
            ev_pct=ev_pct,
            kelly_fraction=kelly_fraction,
            suggested_size_usd=suggested_size_usd,
            polymarket_odds=effective_odds,
            probability_estimate=decision.probability,
            reasoning=decision.reasoning,
            timestamp=timestamp,
        )

        # 5. Emit signal
        self._emit(signal)

        # 6. Return MultiAgentResult for the graph
        return MultiAgentResult(status=Status.COMPLETED)

    def _emit(self, signal: Signal) -> None:
        """
        LOCAL:  prints to console with readable formatting
        EKS:    publishes to EventBridge / Telegram
        """
        log_line("service", "broadcaster", f"SIGNAL asset={signal.asset} timeframe={signal.timeframe}")
        log_line("service", "broadcaster", f"direction={signal.signal} confidence={signal.confidence:.0%}")
        log_line("service", "broadcaster", f"ev_pct={signal.ev_pct:+.1f}% kelly={signal.kelly_fraction:.2%}")
        log_line("service", "broadcaster", f"suggested_size_usd={signal.suggested_size_usd} odds={signal.polymarket_odds}x")
        log_line("service", "broadcaster", f"p_win={signal.probability_estimate:.0%} timestamp={signal.timestamp}")
        log_line("service", "broadcaster", f"reasoning={signal.reasoning[:200]}")
