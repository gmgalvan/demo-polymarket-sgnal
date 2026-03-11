"""Tests for watchdog loop and payload parsing (no network)."""
import pytest

from agents.watchdog import Watchdog, WatchdogConfig, extract_polymarket_odds
from agents.watchdog.watchdog import (
    _build_polymarket_queries,
    build_polymarket_subscribe_from_search_result,
    parse_clob_token_ids,
)


@pytest.mark.asyncio
async def test_mock_watchdog_emits_expected_states():
    config = WatchdogConfig(
        mode="mock",
        mock_interval_seconds=0.0,
        mock_states=[
            {
                "asset": "BTC",
                "timeframe": "15min",
                "ohlcv": {
                    "open": 100.0,
                    "high": 102.0,
                    "low": 99.0,
                    "close": 101.0,
                    "volume": 10.0,
                },
                "polymarket_odds": 1.8,
                "volatility": 0.01,
                "trigger_reason": "candle_close",
                "bankroll": 500.0,
                "timestamp": "2026-03-10T00:00:00+00:00",
            }
        ],
    )
    watchdog = Watchdog(config=config)

    events = []
    async for event in watchdog.iter_events(max_events=2):
        events.append(event)

    assert len(events) == 2
    for event in events:
        state = event.invocation_state
        assert state["asset"] == "BTC"
        assert state["timeframe"] == "15min"
        assert state["trigger_reason"] == "candle_close"
        assert state["polymarket_odds"] == 1.8


def test_extract_polymarket_odds_from_supported_shapes():
    assert extract_polymarket_odds({"odds": 1.67}) == 1.67
    assert extract_polymarket_odds({"price": 0.5}) == 2.0
    assert extract_polymarket_odds({"event": {"best_bid": 0.4}}) == 2.5


def test_extract_polymarket_odds_prefers_selected_asset_id():
    payload = {
        "event_type": "price_change",
        "price_changes": [
            {"asset_id": "yes-token", "best_bid": "0.53", "best_ask": "0.54"},
            {"asset_id": "no-token", "best_bid": "0.46", "best_ask": "0.47"},
        ],
    }
    assert extract_polymarket_odds(payload, preferred_asset_id="yes-token") == 1.8692


def test_binance_payload_generates_close_and_spike_events():
    config = WatchdogConfig(
        mode="websocket",
        asset="BTC",
        timeframe="15min",
        bankroll=1000.0,
        volatility_spike_threshold=0.01,
    )
    watchdog = Watchdog(config=config)

    # 3% move within open candle -> volatility spike
    spike_payload = {
        "k": {
            "t": 1700000000000,
            "T": 1700000899999,
            "o": "100",
            "h": "104",
            "l": "99",
            "c": "103",
            "v": "1500",
            "x": False,
        }
    }
    event, spike_candle_ts = watchdog._event_from_binance_payload(
        payload=spike_payload,
        odds=1.9,
        last_spike_candle_open_ts=None,
    )
    assert event is not None
    assert spike_candle_ts == 1700000000000
    assert event.invocation_state["trigger_reason"] == "volatility_spike"

    # Closed candle -> candle_close trigger and spike reset
    close_payload = {
        "k": {
            "t": 1700000000000,
            "T": 1700000899999,
            "o": "100",
            "h": "105",
            "l": "98",
            "c": "101",
            "v": "1700",
            "x": True,
        }
    }
    event, spike_candle_ts = watchdog._event_from_binance_payload(
        payload=close_payload,
        odds=1.9,
        last_spike_candle_open_ts=spike_candle_ts,
    )
    assert event is not None
    assert spike_candle_ts is None
    assert event.invocation_state["trigger_reason"] == "candle_close"


def test_parse_clob_token_ids_from_json_string():
    raw = '["111","222"]'
    assert parse_clob_token_ids(raw) == ["111", "222"]


def test_build_polymarket_subscribe_from_search_result_prefers_active_nearest_market():
    payload = {
        "events": [
            {
                "title": "Bitcoin above ___ on March 11?",
                "markets": [
                    {
                        "question": "Will the price of Bitcoin be above $70,000 on March 11?",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T16:00:00Z",
                        "clobTokenIds": '["aaa","bbb"]',
                        "conditionId": "cond-above",
                    },
                    {
                        "question": "Bitcoin Up or Down - March 11, 9AM ET",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T14:00:00Z",
                        "clobTokenIds": ["up-token", "down-token"],
                        "conditionId": "cond-updown",
                    },
                ],
            }
        ]
    }

    subscribe, market = build_polymarket_subscribe_from_search_result(payload)
    assert subscribe is not None
    assert market is not None
    assert subscribe["assets_ids"] == ["up-token", "down-token"]
    assert market["conditionId"] == "cond-updown"


def test_build_polymarket_queries_dedupes_and_keeps_priority():
    queries = _build_polymarket_queries("bitcoin")
    assert queries[0] == "bitcoin"
    assert "bitcoin up or down" in queries
    assert queries.count("bitcoin") == 1
