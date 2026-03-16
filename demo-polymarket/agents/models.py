"""
Pydantic models shared across all graph components.
"""
from typing import Literal
from pydantic import BaseModel, Field


class StrategistDecision(BaseModel):
    """Structured output from the Strategist."""
    decision: Literal["GO", "NO_GO"]
    probability: float = Field(ge=0.0, le=1.0, description="Estimated probability that price moves in the stated direction")
    direction: Literal["UP", "DOWN"]
    confidence: float = Field(ge=0.0, le=1.0, description="Analyst confidence in the decision")
    reasoning: str = Field(description="Brief explanation of the decision")


class Signal(BaseModel):
    """Trading signal emitted by the Broadcaster."""
    asset: str
    timeframe: str
    signal: Literal["BUY", "SELL", "HOLD"]
    confidence: float
    ev_pct: float = Field(description="Expected Value as a percentage")
    kelly_fraction: float
    suggested_size_usd: float
    polymarket_odds: float
    probability_estimate: float
    reasoning: str
    timestamp: str


class CandleData(BaseModel):
    """OHLCV candle data."""
    open: float
    high: float
    low: float
    close: float
    volume: float


class InvocationState(BaseModel):
    """
    Shared state passed by the Watchdog to the graph.
    Invisible to the LLM — accessible via tool_context.invocation_state.
    """
    ohlcv: CandleData
    polymarket_odds: float = Field(description="Current Polymarket odds (e.g. 1.65)")
    timestamp: str
    volatility: float
    trigger_reason: Literal["candle_close", "volatility_spike"]
    bankroll: float = 1000.0
    asset: str = "BTC"
    timeframe: str = "15min"
