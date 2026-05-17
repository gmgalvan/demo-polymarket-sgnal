"""
LMSR helpers for optional execution-slippage adjustment.

This module models a binary LMSR market to estimate how a position size
would move the average fill price and effective odds.
"""
from __future__ import annotations

from dataclasses import dataclass
from math import exp, log


EPS = 1e-9


@dataclass
class LMSRExecutionEstimate:
    """Estimated execution metrics for a binary LMSR market."""

    effective_odds: float
    average_entry_price: float
    marginal_price_after: float
    shares: float
    slippage_bps: float


def lmsr_yes_price(q_yes: float, q_no: float, b: float) -> float:
    """Marginal YES price in a binary LMSR market."""
    if b <= 0:
        raise ValueError("liquidity parameter b must be > 0")
    x = (q_yes - q_no) / b
    # Numerically stable logistic.
    if x >= 0:
        z = exp(-x)
        return 1.0 / (1.0 + z)
    z = exp(x)
    return z / (1.0 + z)


def lmsr_cost(q_yes: float, q_no: float, b: float) -> float:
    """LMSR cost function C(q) = b * ln(exp(q_yes/b) + exp(q_no/b))."""
    if b <= 0:
        raise ValueError("liquidity parameter b must be > 0")
    a = q_yes / b
    c = q_no / b
    m = a if a >= c else c
    return b * (m + log(exp(a - m) + exp(c - m)))


def estimate_lmsr_execution(
    odds: float,
    trade_size_usd: float,
    liquidity_b: float,
) -> LMSRExecutionEstimate:
    """
    Estimate effective odds for buying YES in a binary LMSR market.

    Assumptions:
    - odds are decimal odds for the side being bought.
    - trade_size_usd is the budget spent on that side.
    - payout is normalized to 1.0 per share.
    """
    if odds <= 1.0 or trade_size_usd <= 0 or liquidity_b <= 0:
        return LMSRExecutionEstimate(
            effective_odds=max(odds, 1.0001),
            average_entry_price=min(max(1.0 / max(odds, 1.0001), EPS), 1.0 - EPS),
            marginal_price_after=min(max(1.0 / max(odds, 1.0001), EPS), 1.0 - EPS),
            shares=0.0,
            slippage_bps=0.0,
        )

    p0 = min(max(1.0 / odds, EPS), 1.0 - EPS)
    # Recover q_yes - q_no from current probability.
    qdiff0 = liquidity_b * log(p0 / (1.0 - p0))
    q_yes0 = qdiff0
    q_no0 = 0.0
    base_cost = lmsr_cost(q_yes0, q_no0, liquidity_b)

    def spend_for(delta_yes: float) -> float:
        return lmsr_cost(q_yes0 + delta_yes, q_no0, liquidity_b) - base_cost

    # Find upper bound for binary search.
    hi = max(trade_size_usd / max(p0, EPS), 1.0)
    while spend_for(hi) < trade_size_usd:
        hi *= 2.0
        if hi > 1e12:
            break

    lo = 0.0
    for _ in range(80):
        mid = (lo + hi) / 2.0
        if spend_for(mid) < trade_size_usd:
            lo = mid
        else:
            hi = mid

    shares = max((lo + hi) / 2.0, EPS)
    avg_price = min(max(trade_size_usd / shares, EPS), 1.0 - EPS)
    p_after = lmsr_yes_price(q_yes0 + shares, q_no0, liquidity_b)
    effective_odds = 1.0 / avg_price
    slippage_bps = max((avg_price / p0 - 1.0) * 10000.0, 0.0)

    return LMSRExecutionEstimate(
        effective_odds=round(effective_odds, 6),
        average_entry_price=round(avg_price, 8),
        marginal_price_after=round(p_after, 8),
        shares=round(shares, 8),
        slippage_bps=round(slippage_bps, 2),
    )
