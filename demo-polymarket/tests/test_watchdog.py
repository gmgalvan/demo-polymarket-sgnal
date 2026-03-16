"""Tests for watchdog loop and payload parsing (no network)."""
from types import SimpleNamespace

import pytest

from agents.watchdog import Watchdog, WatchdogConfig, extract_polymarket_odds
from agents.watchdog.watchdog import (
    TriggerEvent,
    _deterministic_no_go_reason,
    _build_polymarket_queries,
    _extract_polymarket_event_slug,
    _strip_polymarket_rotating_suffix,
    build_polymarket_subscribe_for_event_ref,
    build_polymarket_subscribe_from_markets_result,
    build_polymarket_subscribe_from_search_result,
    parse_clob_token_ids,
    run_watchdog_graph_loop,
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


def test_extract_polymarket_event_slug_from_url():
    url = "https://polymarket.com/event/btc-updown-5m-1773359400"
    assert _extract_polymarket_event_slug(url) == "btc-updown-5m-1773359400"
    assert _extract_polymarket_event_slug("btc-updown-5m-1773359400") == "btc-updown-5m-1773359400"


def test_strip_polymarket_rotating_suffix():
    assert _strip_polymarket_rotating_suffix("btc-updown-5m-1773359400") == "btc-updown-5m"
    assert _strip_polymarket_rotating_suffix("btc-updown-5m") == "btc-updown-5m"


def test_build_polymarket_subscribe_for_event_ref_matches_slug():
    payload = {
        "events": [
            {
                "slug": "btc-updown-5m-1773359400",
                "markets": [
                    {
                        "question": "Bitcoin Up or Down - 5m",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T14:00:00Z",
                        "clobTokenIds": ["yes-1", "no-1"],
                        "conditionId": "cond-updown-5m",
                    }
                ],
            },
            {
                "slug": "other-market",
                "markets": [
                    {
                        "question": "Other market",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T14:00:00Z",
                        "clobTokenIds": ["yes-2", "no-2"],
                        "conditionId": "cond-other",
                    }
                ],
            },
        ]
    }
    subscribe, market = build_polymarket_subscribe_for_event_ref(
        payload=payload,
        event_ref="https://polymarket.com/event/btc-updown-5m-1773359400",
    )
    assert subscribe is not None
    assert market is not None
    assert subscribe["assets_ids"] == ["yes-1", "no-1"]
    assert market["conditionId"] == "cond-updown-5m"


def test_build_polymarket_subscribe_for_event_ref_matches_rolling_slug():
    payload = {
        "events": [
            {
                "slug": "btc-updown-5m-1773360000",
                "markets": [
                    {
                        "question": "Bitcoin Up or Down - 5m",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T14:05:00Z",
                        "clobTokenIds": ["yes-roll", "no-roll"],
                        "conditionId": "cond-updown-5m-roll",
                    }
                ],
            }
        ]
    }
    subscribe, market = build_polymarket_subscribe_for_event_ref(
        payload=payload,
        event_ref="https://polymarket.com/event/btc-updown-5m-1773359400",
    )
    assert subscribe is not None
    assert market is not None
    assert subscribe["assets_ids"] == ["yes-roll", "no-roll"]
    assert market["conditionId"] == "cond-updown-5m-roll"


def test_build_polymarket_subscribe_for_event_ref_matches_semantic_hints():
    payload = {
        "events": [
            {
                "title": "Bitcoin Up or Down - 5m (rolling)",
                "markets": [
                    {
                        "question": "Bitcoin Up or Down - 5m",
                        "active": True,
                        "closed": False,
                        "endDate": "2099-03-11T14:10:00Z",
                        "clobTokenIds": ["yes-sem", "no-sem"],
                        "conditionId": "cond-updown-5m-semantic",
                    }
                ],
            }
        ]
    }
    subscribe, market = build_polymarket_subscribe_for_event_ref(
        payload=payload,
        event_ref="https://polymarket.com/event/btc-updown-5m-1773359400",
    )
    assert subscribe is not None
    assert market is not None
    assert subscribe["assets_ids"] == ["yes-sem", "no-sem"]
    assert market["conditionId"] == "cond-updown-5m-semantic"


def test_build_polymarket_subscribe_from_markets_result_matches_rolling_slug():
    markets = [
        {
            "slug": "btc-updown-5m-1773360000",
            "question": "Bitcoin Up or Down - 5m",
            "active": True,
            "closed": False,
            "endDate": "2099-03-11T14:15:00Z",
            "clobTokenIds": ["yes-market", "no-market"],
            "conditionId": "cond-updown-5m-market",
        }
    ]
    subscribe, market = build_polymarket_subscribe_from_markets_result(
        markets=markets,
        event_ref="https://polymarket.com/event/btc-updown-5m-1773359400",
    )
    assert subscribe is not None
    assert market is not None
    assert subscribe["assets_ids"] == ["yes-market", "no-market"]
    assert market["conditionId"] == "cond-updown-5m-market"


def test_coinbase_timeframe_forced_to_5min_by_default(monkeypatch):
    monkeypatch.setenv("MARKET_DATA_PROVIDER", "coinbase")
    monkeypatch.setenv("WATCHDOG_ASSET", "ADA")
    monkeypatch.setenv("WATCHDOG_TIMEFRAME", "15min")
    monkeypatch.delenv("WATCHDOG_COINBASE_5MIN_ASSETS", raising=False)
    cfg = WatchdogConfig.from_env()
    assert cfg.timeframe == "5min"
    assert cfg.coinbase_5min_assets == ()


def test_coinbase_timeframe_forced_only_for_listed_assets(monkeypatch):
    monkeypatch.setenv("MARKET_DATA_PROVIDER", "coinbase")
    monkeypatch.setenv("WATCHDOG_COINBASE_5MIN_ASSETS", "BTC, ETH, SOL")

    monkeypatch.setenv("WATCHDOG_ASSET", "ADA")
    monkeypatch.setenv("WATCHDOG_TIMEFRAME", "15min")
    cfg_ada = WatchdogConfig.from_env()
    assert cfg_ada.timeframe == "15min"
    assert cfg_ada.coinbase_5min_assets == ("BTC", "ETH", "SOL")

    monkeypatch.setenv("WATCHDOG_ASSET", "ETH")
    monkeypatch.setenv("WATCHDOG_TIMEFRAME", "15min")
    cfg_eth = WatchdogConfig.from_env()
    assert cfg_eth.timeframe == "5min"


def test_watchdog_loads_explicit_polymarket_event_ref(monkeypatch):
    monkeypatch.setenv("POLYMARKET_EVENT_URL", "https://polymarket.com/event/btc-updown-5m-1773359400")
    cfg = WatchdogConfig.from_env()
    assert cfg.polymarket_event_ref == "https://polymarket.com/event/btc-updown-5m-1773359400"


def test_deterministic_no_go_when_edge_is_mathematically_impossible():
    state = {
        "polymarket_odds": 1.0015,  # implied ~99.85%
    }
    reason = _deterministic_no_go_reason(state)
    assert reason is not None
    assert "impossible_edge" in reason


@pytest.mark.asyncio
async def test_run_loop_skips_graph_for_impossible_edge():
    class FakeWatchdog:
        async def iter_events(self, max_events=None):
            yield TriggerEvent(
                task="analyze",
                invocation_state={
                    "asset": "BTC",
                    "timeframe": "5min",
                    "trigger_reason": "candle_close",
                    "polymarket_odds": 1.0015,
                    "ohlcv": {"open": 1, "high": 1, "low": 1, "close": 1, "volume": 1},
                    "volatility": 0.0,
                    "bankroll": 1000.0,
                    "timestamp": "2026-03-12T00:00:00+00:00",
                },
            )

    class FakeGraph:
        called = False

        async def invoke_async(self, task, invocation_state=None):
            self.called = True
            raise AssertionError("Graph should not be invoked for impossible-edge events")

    graph = FakeGraph()
    processed = await run_watchdog_graph_loop(graph=graph, watchdog=FakeWatchdog(), max_events=1)
    assert processed == 1
    assert graph.called is False


@pytest.mark.asyncio
async def test_run_loop_treats_token_limit_as_no_go():
    class FakeWatchdog:
        async def iter_events(self, max_events=None):
            yield TriggerEvent(
                task="analyze",
                invocation_state={
                    "asset": "BTC",
                    "timeframe": "5min",
                    "trigger_reason": "candle_close",
                    "polymarket_odds": 1.8,
                    "ohlcv": {"open": 1, "high": 1, "low": 1, "close": 1, "volume": 1},
                    "volatility": 0.0,
                    "bankroll": 1000.0,
                    "timestamp": "2026-03-12T00:00:00+00:00",
                },
            )

    class MaxTokensReachedException(Exception):
        pass

    class FakeGraph:
        async def invoke_async(self, task, invocation_state=None):
            raise MaxTokensReachedException("token budget exceeded")

    processed = await run_watchdog_graph_loop(graph=FakeGraph(), watchdog=FakeWatchdog(), max_events=1)
    assert processed == 1


@pytest.mark.asyncio
async def test_run_loop_invokes_graph_when_edge_guard_disabled():
    class FakeWatchdog:
        config = SimpleNamespace(enforce_impossible_edge_guard=False)

        async def iter_events(self, max_events=None):
            yield TriggerEvent(
                task="analyze",
                invocation_state={
                    "asset": "BTC",
                    "timeframe": "5min",
                    "trigger_reason": "candle_close",
                    "polymarket_odds": 1.0015,
                    "ohlcv": {"open": 1, "high": 1, "low": 1, "close": 1, "volume": 1},
                    "volatility": 0.0,
                    "bankroll": 1000.0,
                    "timestamp": "2026-03-12T00:00:00+00:00",
                },
            )

    class FakeResult:
        status = "COMPLETED"
        completed_nodes = 1
        total_nodes = 1
        execution_time = 0
        results = {}

    class FakeGraph:
        called = False

        async def invoke_async(self, task, invocation_state=None):
            self.called = True
            return FakeResult()

    graph = FakeGraph()
    processed = await run_watchdog_graph_loop(graph=graph, watchdog=FakeWatchdog(), max_events=1)
    assert processed == 1
    assert graph.called is True
