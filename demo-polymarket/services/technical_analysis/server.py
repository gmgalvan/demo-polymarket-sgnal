"""
Technical Analysis MCP Server.

Implements RSI, MACD, Bollinger Bands and VWAP using pure numpy.
No external TA library dependency — correct, fast, and portable.

Run locally:
    python services/technical_analysis/server.py
"""
import numpy as np
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Technical Analysis MCP Server", host="0.0.0.0", port=8002)


# ── Math helpers ──────────────────────────────────────────────────────────────

def _ema(values: np.ndarray, period: int) -> np.ndarray:
    """Exponential Moving Average using Wilder's multiplier."""
    k = 2.0 / (period + 1)
    result = np.empty_like(values, dtype=float)
    result[0] = values[0]
    for i in range(1, len(values)):
        result[i] = values[i] * k + result[i - 1] * (1 - k)
    return result


def _rsi_value(prices: np.ndarray, period: int = 14) -> float:
    """RSI using Wilder's smoothed moving average."""
    if len(prices) < period + 1:
        raise ValueError(f"Need at least {period + 1} prices, got {len(prices)}")
    deltas = np.diff(prices)
    gains = np.where(deltas > 0, deltas, 0.0)
    losses = np.where(deltas < 0, -deltas, 0.0)

    avg_gain = np.mean(gains[:period])
    avg_loss = np.mean(losses[:period])
    for i in range(period, len(gains)):
        avg_gain = (avg_gain * (period - 1) + gains[i]) / period
        avg_loss = (avg_loss * (period - 1) + losses[i]) / period

    rs = avg_gain / avg_loss if avg_loss > 0 else float("inf")
    return round(100.0 - (100.0 / (1.0 + rs)), 2)


# ── MCP Tools ─────────────────────────────────────────────────────────────────

@mcp.tool(description="Calculate RSI (Relative Strength Index) for a price series")
def calculate_rsi(prices: list[float], period: int = 14) -> dict:
    """
    Returns RSI value and overbought/oversold interpretation.

    Args:
        prices: Closing price series (oldest to newest), minimum period+1 values
        period: Lookback period (default 14)
    """
    arr = np.array(prices, dtype=float)
    try:
        rsi = _rsi_value(arr, period)
    except ValueError as e:
        return {"error": str(e)}

    if rsi >= 70:
        signal = "overbought"
    elif rsi <= 30:
        signal = "oversold"
    else:
        signal = "neutral"

    return {
        "rsi": rsi,
        "signal": signal,
        "period": period,
        "interpretation": (
            f"RSI {rsi:.1f} — {signal}. "
            + ("Potential reversal DOWN." if signal == "overbought" else
               "Potential reversal UP." if signal == "oversold" else
               "No extreme reading.")
        ),
    }


@mcp.tool(description="Calculate MACD for a price series")
def calculate_macd(
    prices: list[float],
    fast: int = 12,
    slow: int = 26,
    signal_period: int = 9,
) -> dict:
    """
    Returns MACD line, signal line, histogram, and crossover direction.

    Args:
        prices: Closing price series (oldest to newest), minimum slow+signal_period values
        fast: Fast EMA period (default 12)
        slow: Slow EMA period (default 26)
        signal_period: Signal line EMA period (default 9)
    """
    needed = slow + signal_period
    if len(prices) < needed:
        return {"error": f"Need at least {needed} prices, got {len(prices)}"}

    arr = np.array(prices, dtype=float)
    ema_fast = _ema(arr, fast)
    ema_slow = _ema(arr, slow)
    macd_line = ema_fast - ema_slow
    signal_line = _ema(macd_line, signal_period)
    histogram = macd_line - signal_line

    m = round(float(macd_line[-1]), 6)
    s = round(float(signal_line[-1]), 6)
    h = round(float(histogram[-1]), 6)

    crossover = "none"
    if len(histogram) >= 2:
        prev_h = histogram[-2]
        if prev_h < 0 and h > 0:
            crossover = "bullish"
        elif prev_h > 0 and h < 0:
            crossover = "bearish"
    elif h > 0:
        crossover = "bullish"
    elif h < 0:
        crossover = "bearish"

    return {
        "macd_line": m,
        "signal_line": s,
        "histogram": h,
        "crossover": crossover,
        "interpretation": (
            f"MACD {m:+.6f}, Signal {s:+.6f}, Hist {h:+.6f}. "
            + ("Bullish crossover — momentum turning UP." if crossover == "bullish" else
               "Bearish crossover — momentum turning DOWN." if crossover == "bearish" else
               f"No crossover. {'Bullish momentum.' if h > 0 else 'Bearish momentum.'}")
        ),
    }


@mcp.tool(description="Calculate Bollinger Bands for a price series")
def calculate_bollinger_bands(
    prices: list[float],
    period: int = 20,
    std_dev: float = 2.0,
) -> dict:
    """
    Returns upper/middle/lower bands, percent_b position, and band width.

    Args:
        prices: Closing price series (oldest to newest), minimum period values
        period: Rolling window (default 20)
        std_dev: Standard deviation multiplier (default 2.0)
    """
    if len(prices) < period:
        return {"error": f"Need at least {period} prices, got {len(prices)}"}

    arr = np.array(prices[-period:], dtype=float)
    middle = float(np.mean(arr))
    std = float(np.std(arr, ddof=1))
    upper = middle + std_dev * std
    lower = middle - std_dev * std
    close = prices[-1]

    band_width = (upper - lower) / middle if middle != 0 else 0
    percent_b = (close - lower) / (upper - lower) if (upper - lower) != 0 else 0.5

    if percent_b > 0.8:
        position = "near_upper_band"
    elif percent_b < 0.2:
        position = "near_lower_band"
    else:
        position = "middle"

    return {
        "upper": round(upper, 2),
        "middle": round(middle, 2),
        "lower": round(lower, 2),
        "percent_b": round(percent_b, 4),
        "band_width": round(band_width, 4),
        "position": position,
        "interpretation": (
            f"Price at {percent_b:.0%} of band ({position}). "
            + ("Near upper band — possible resistance/overbought." if position == "near_upper_band" else
               "Near lower band — possible support/oversold." if position == "near_lower_band" else
               "Price in the middle of the bands.")
        ),
    }


@mcp.tool(description="Calculate VWAP (Volume Weighted Average Price)")
def calculate_vwap(prices: list[float], volumes: list[float]) -> dict:
    """
    Returns VWAP and whether current price is above or below it.

    Args:
        prices: Closing price series (oldest to newest)
        volumes: Corresponding volume series (same length as prices)
    """
    if len(prices) != len(volumes):
        return {"error": "prices and volumes must have the same length"}
    if not prices:
        return {"error": "Empty price series"}

    p = np.array(prices, dtype=float)
    v = np.array(volumes, dtype=float)
    total_volume = float(np.sum(v))
    if total_volume == 0:
        return {"error": "Total volume is zero"}

    vwap = float(np.sum(p * v) / total_volume)
    close = prices[-1]
    bias = "above_vwap" if close > vwap else "below_vwap" if close < vwap else "at_vwap"

    return {
        "vwap": round(vwap, 2),
        "current_price": close,
        "bias": bias,
        "interpretation": (
            f"VWAP {vwap:,.2f}. Current price {close:,.2f} is {bias.replace('_', ' ')}. "
            + ("Bullish bias — buyers in control." if bias == "above_vwap" else
               "Bearish bias — sellers in control." if bias == "below_vwap" else
               "Price at fair value.")
        ),
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
