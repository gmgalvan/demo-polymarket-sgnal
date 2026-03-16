"""Datos mock para tests — sin necesidad de red ni APIs externas."""
from datetime import datetime, timezone

BULLISH_STATE = {
    "asset": "BTC",
    "timeframe": "15min",
    "ohlcv": {"open": 83200.0, "high": 83450.0, "low": 82800.0, "close": 82950.0, "volume": 1240.5},
    "polymarket_odds": 1.68,
    "volatility": 0.0023,
    "trigger_reason": "candle_close",
    "bankroll": 1000.0,
    "timestamp": "2026-03-10T15:00:00+00:00",
}

BEARISH_STATE = {
    "asset": "BTC",
    "timeframe": "15min",
    "ohlcv": {"open": 85100.0, "high": 85800.0, "low": 84900.0, "close": 85600.0, "volume": 2100.0},
    "polymarket_odds": 2.10,
    "volatility": 0.0041,
    "trigger_reason": "volatility_spike",
    "bankroll": 1000.0,
    "timestamp": "2026-03-10T15:15:00+00:00",
}

NO_GO_STATE = {
    "asset": "BTC",
    "timeframe": "15min",
    "ohlcv": {"open": 84000.0, "high": 84150.0, "low": 83850.0, "close": 84020.0, "volume": 420.0},
    "polymarket_odds": 2.00,
    "volatility": 0.0008,
    "trigger_reason": "candle_close",
    "bankroll": 1000.0,
    "timestamp": "2026-03-10T15:30:00+00:00",
}
