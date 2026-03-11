"""
Async watchdog that feeds invocation_state into the Strands graph.

Modes:
- mock: emits static states at a fixed interval (for local development/tests)
- websocket: consumes Binance kline stream + Polymarket odds stream
"""
from __future__ import annotations

import asyncio
import copy
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, AsyncIterator, Mapping

import httpx

from agents.config import DEFAULT_BANKROLL_USD
from agents.models import InvocationState, StrategistDecision

DEFAULT_TASK_PROMPT = (
    "Analyze the current BTC 15min candle and determine if there is a positive EV opportunity. "
    "Use get_market_snapshot and get_historical_context before deciding."
)


@dataclass
class TriggerEvent:
    """Payload emitted by the watchdog and sent to the graph."""

    task: str
    invocation_state: dict[str, Any]


@dataclass
class WatchdogConfig:
    """Runtime config for the watchdog loop."""

    mode: str = "mock"  # "mock" | "websocket"
    asset: str = "BTC"
    timeframe: str = "15min"
    bankroll: float = DEFAULT_BANKROLL_USD
    task_prompt: str = DEFAULT_TASK_PROMPT

    # Mock mode
    mock_interval_seconds: float = 5.0
    mock_states: list[dict[str, Any]] = field(default_factory=list)

    # WebSocket mode
    binance_symbol: str = "btcusdt"
    binance_interval: str = "15m"
    binance_ws_url: str = ""
    polymarket_ws_url: str = ""
    polymarket_ws_subscribe: Any = None
    polymarket_auto_subscribe: bool = True
    polymarket_search_url: str = "https://gamma-api.polymarket.com/public-search"
    polymarket_search_query: str = "bitcoin"
    polymarket_default_odds: float = 2.0
    volatility_spike_threshold: float = 0.005
    reconnect_delay_seconds: float = 2.0

    @classmethod
    def from_env(cls) -> "WatchdogConfig":
        """Load watchdog config from environment variables."""
        mode = os.getenv("WATCHDOG_MODE", "mock").strip().lower()
        asset = os.getenv("WATCHDOG_ASSET", "BTC").strip().upper()
        timeframe = os.getenv("WATCHDOG_TIMEFRAME", "15min").strip().lower()
        bankroll = float(os.getenv("WATCHDOG_BANKROLL", str(DEFAULT_BANKROLL_USD)))

        binance_symbol = os.getenv("BINANCE_SYMBOL", f"{asset.lower()}usdt").strip().lower()
        binance_interval = os.getenv("BINANCE_INTERVAL", _timeframe_to_binance_interval(timeframe))
        default_binance_url = f"wss://stream.binance.com:9443/ws/{binance_symbol}@kline_{binance_interval}"
        binance_ws_url = os.getenv("BINANCE_WS_URL", default_binance_url).strip()

        subscribe_raw = os.getenv("POLYMARKET_WS_SUBSCRIBE", "").strip()
        polymarket_ws_subscribe = _json_load_maybe(subscribe_raw) if subscribe_raw else None

        return cls(
            mode=mode,
            asset=asset,
            timeframe=timeframe,
            bankroll=bankroll,
            task_prompt=os.getenv("WATCHDOG_TASK_PROMPT", DEFAULT_TASK_PROMPT).strip() or DEFAULT_TASK_PROMPT,
            mock_interval_seconds=float(os.getenv("WATCHDOG_MOCK_INTERVAL_SECONDS", "5")),
            mock_states=default_mock_states(asset=asset, timeframe=timeframe, bankroll=bankroll),
            binance_symbol=binance_symbol,
            binance_interval=binance_interval,
            binance_ws_url=binance_ws_url,
            polymarket_ws_url=os.getenv("POLYMARKET_WS_URL", "").strip(),
            polymarket_ws_subscribe=polymarket_ws_subscribe,
            polymarket_auto_subscribe=_env_bool("POLYMARKET_AUTO_SUBSCRIBE", True),
            polymarket_search_url=os.getenv("POLYMARKET_SEARCH_URL", "https://gamma-api.polymarket.com/public-search").strip(),
            polymarket_search_query=os.getenv("POLYMARKET_SEARCH_QUERY", "bitcoin").strip(),
            polymarket_default_odds=float(os.getenv("POLYMARKET_DEFAULT_ODDS", "2.0")),
            volatility_spike_threshold=float(os.getenv("VOLATILITY_SPIKE_THRESHOLD", "0.005")),
            reconnect_delay_seconds=float(os.getenv("WATCHDOG_RECONNECT_DELAY_SECONDS", "2")),
        )


class Watchdog:
    """Produces TriggerEvent payloads for graph execution."""

    def __init__(self, config: WatchdogConfig | None = None):
        self.config = config or WatchdogConfig.from_env()
        self._last_auto_market_key: str = ""

    async def iter_events(self, max_events: int | None = None) -> AsyncIterator[TriggerEvent]:
        """Yield trigger events forever (or up to max_events)."""
        emitted = 0
        if self.config.mode == "mock":
            async for event in self._iter_mock_events():
                yield event
                emitted += 1
                if max_events is not None and emitted >= max_events:
                    return
            return

        async for event in self._iter_websocket_events(max_events=max_events):
            yield event

    async def _iter_mock_events(self) -> AsyncIterator[TriggerEvent]:
        """Emit canned states at fixed intervals."""
        if not self.config.mock_states:
            self.config.mock_states = default_mock_states(
                asset=self.config.asset,
                timeframe=self.config.timeframe,
                bankroll=self.config.bankroll,
            )

        idx = 0
        while True:
            await asyncio.sleep(max(0.0, self.config.mock_interval_seconds))
            raw_state = copy.deepcopy(self.config.mock_states[idx % len(self.config.mock_states)])
            raw_state["timestamp"] = _utc_now_iso()
            state = self._normalize_state(raw_state)
            yield TriggerEvent(task=self.config.task_prompt, invocation_state=state)
            idx += 1

    async def _iter_websocket_events(self, max_events: int | None = None) -> AsyncIterator[TriggerEvent]:
        """Emit events from live Binance + Polymarket websocket streams."""
        if not self.config.binance_ws_url:
            raise ValueError("BINANCE_WS_URL is required in websocket mode.")

        queue: asyncio.Queue[TriggerEvent] = asyncio.Queue()
        stop_event = asyncio.Event()
        shared: dict[str, Any] = {"polymarket_odds": self.config.polymarket_default_odds}

        listeners = [
            asyncio.create_task(self._run_binance_listener(queue, stop_event, shared)),
        ]
        if self.config.polymarket_ws_url:
            listeners.append(asyncio.create_task(self._run_polymarket_listener(stop_event, shared)))
        else:
            print(
                "[Watchdog] POLYMARKET_WS_URL is not set. "
                f"Using default odds={self.config.polymarket_default_odds}."
            )

        emitted = 0
        try:
            while True:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=1.0)
                except TimeoutError:
                    for task in listeners:
                        if task.done():
                            error = task.exception()
                            if error is not None:
                                raise RuntimeError(f"Watchdog listener failed: {error}") from error
                    continue

                emitted += 1
                yield event
                if max_events is not None and emitted >= max_events:
                    return
        finally:
            stop_event.set()
            for task in listeners:
                task.cancel()
            await asyncio.gather(*listeners, return_exceptions=True)

    async def _run_binance_listener(
        self,
        queue: asyncio.Queue[TriggerEvent],
        stop_event: asyncio.Event,
        shared: dict[str, Any],
    ) -> None:
        """Listen to Binance kline stream and enqueue candle/volatility triggers."""
        try:
            import websockets
        except ImportError as exc:
            raise RuntimeError(
                "websockets package is required for WATCHDOG_MODE=websocket. "
                "Install with: pip install websockets"
            ) from exc

        last_spike_candle_open_ts: int | None = None

        while not stop_event.is_set():
            try:
                ws = await asyncio.wait_for(
                    websockets.connect(
                        self.config.binance_ws_url,
                        ping_interval=20,
                        close_timeout=5,
                    ),
                    timeout=10,
                )
                print(f"[Watchdog] Connected Binance WS: {self.config.binance_ws_url}")
                try:
                    async for raw_message in ws:
                        if stop_event.is_set():
                            return

                        payload = _json_load_maybe(raw_message)
                        if not isinstance(payload, Mapping):
                            continue

                        event, last_spike_candle_open_ts = self._event_from_binance_payload(
                            payload,
                            odds=float(shared["polymarket_odds"]),
                            last_spike_candle_open_ts=last_spike_candle_open_ts,
                        )
                        if event is not None:
                            await queue.put(event)
                finally:
                    await ws.close()
            except asyncio.CancelledError:
                return
            except Exception as exc:
                print(f"[Watchdog] Binance WS error: {exc}. Reconnecting...")
                await asyncio.sleep(self.config.reconnect_delay_seconds)

    async def _run_polymarket_listener(
        self,
        stop_event: asyncio.Event,
        shared: dict[str, Any],
    ) -> None:
        """Listen to Polymarket websocket stream and keep latest odds in shared state."""
        try:
            import websockets
        except ImportError as exc:
            raise RuntimeError(
                "websockets package is required for WATCHDOG_MODE=websocket. "
                "Install with: pip install websockets"
            ) from exc

        while not stop_event.is_set():
            try:
                subscribe_payload, selected_market = await self._resolve_polymarket_subscribe_payload()
                ws = await asyncio.wait_for(
                    websockets.connect(
                        self.config.polymarket_ws_url,
                        ping_interval=20,
                        close_timeout=5,
                    ),
                    timeout=10,
                )
                print(f"[Watchdog] Connected Polymarket WS: {self.config.polymarket_ws_url}")
                try:
                    if subscribe_payload is not None:
                        await ws.send(json.dumps(subscribe_payload))
                        asset_ids = subscribe_payload.get("assets_ids")
                        if isinstance(asset_ids, list) and asset_ids:
                            shared["polymarket_primary_asset_id"] = str(asset_ids[0])
                        if selected_market:
                            print(
                                "[Watchdog] Subscribed market: "
                                f"{selected_market.get('question', 'unknown')} "
                                f"(end={selected_market.get('endDate', 'N/A')})"
                            )

                    async for raw_message in ws:
                        if stop_event.is_set():
                            return
                        payload = _json_load_maybe(raw_message)
                        preferred_asset_id = shared.get("polymarket_primary_asset_id")
                        odds = extract_polymarket_odds(payload, preferred_asset_id=preferred_asset_id)
                        if odds is not None:
                            shared["polymarket_odds"] = odds
                finally:
                    await ws.close()
            except asyncio.CancelledError:
                return
            except Exception as exc:
                print(f"[Watchdog] Polymarket WS error: {exc}. Reconnecting...")
                await asyncio.sleep(self.config.reconnect_delay_seconds)

    async def _resolve_polymarket_subscribe_payload(
        self,
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        """
        Resolve subscribe payload for Polymarket WS.

        Priority:
        1) Auto-discovery from Gamma public-search (if enabled)
        2) Manual POLYMARKET_WS_SUBSCRIBE from env
        """
        manual_payload = (
            self.config.polymarket_ws_subscribe
            if isinstance(self.config.polymarket_ws_subscribe, Mapping)
            else None
        )

        if self.config.polymarket_auto_subscribe:
            try:
                auto_payload, selected_market = await self._fetch_auto_polymarket_subscribe()
                if auto_payload is not None:
                    market_key = (
                        str(selected_market.get("conditionId") or selected_market.get("id") or "")
                        if selected_market
                        else ""
                    )
                    if market_key and market_key != self._last_auto_market_key:
                        self._last_auto_market_key = market_key
                        print(
                            "[Watchdog] Auto-selected Polymarket market: "
                            f"{selected_market.get('question', 'unknown')} "
                            f"(end={selected_market.get('endDate', 'N/A')})"
                        )
                    return auto_payload, selected_market
                print(
                    "[Watchdog] Auto-subscribe found no active candidate market. "
                    "Falling back to manual subscribe/default odds."
                )
            except Exception as exc:
                print(f"[Watchdog] Auto-subscribe discovery failed: {exc}")

        return manual_payload, None

    async def _fetch_auto_polymarket_subscribe(
        self,
    ) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
        """Fetch active BTC market candidates and build subscribe payload."""
        if not self.config.polymarket_search_url:
            return None, None

        queries = _build_polymarket_queries(self.config.polymarket_search_query)
        merged_events: list[dict[str, Any]] = []
        seen_event_ids: set[str] = set()

        async with httpx.AsyncClient(timeout=15.0) as client:
            for query in queries:
                response = await client.get(
                    self.config.polymarket_search_url,
                    params={"q": query},
                )
                response.raise_for_status()
                data = response.json()
                events = data.get("events", []) if isinstance(data, Mapping) else []
                if not isinstance(events, list):
                    continue
                for event in events:
                    if not isinstance(event, Mapping):
                        continue
                    event_id = str(event.get("id", ""))
                    if event_id and event_id in seen_event_ids:
                        continue
                    if event_id:
                        seen_event_ids.add(event_id)
                    merged_events.append(dict(event))

        data = {"events": merged_events}
        return build_polymarket_subscribe_from_search_result(data)

    def _event_from_binance_payload(
        self,
        payload: Mapping[str, Any],
        odds: float,
        last_spike_candle_open_ts: int | None,
    ) -> tuple[TriggerEvent | None, int | None]:
        """
        Build a TriggerEvent from Binance kline payload.

        Trigger types:
        - candle_close: kline close flag is true
        - volatility_spike: abs(close-open)/open exceeds threshold once per candle
        """
        kline = payload.get("k")
        if not isinstance(kline, Mapping):
            return None, last_spike_candle_open_ts

        open_price = _safe_float(kline.get("o"))
        close_price = _safe_float(kline.get("c"))
        if open_price <= 0 or close_price <= 0:
            return None, last_spike_candle_open_ts

        candle_open_ts = _safe_int(kline.get("t"))
        volatility = abs(close_price - open_price) / open_price
        is_closed = bool(kline.get("x"))

        trigger_reason: str | None = None
        if is_closed:
            trigger_reason = "candle_close"
            last_spike_candle_open_ts = None
        elif (
            volatility >= self.config.volatility_spike_threshold
            and candle_open_ts > 0
            and candle_open_ts != last_spike_candle_open_ts
        ):
            trigger_reason = "volatility_spike"
            last_spike_candle_open_ts = candle_open_ts

        if trigger_reason is None:
            return None, last_spike_candle_open_ts

        raw_state = {
            "asset": self.config.asset,
            "timeframe": self.config.timeframe,
            "ohlcv": {
                "open": open_price,
                "high": _safe_float(kline.get("h")),
                "low": _safe_float(kline.get("l")),
                "close": close_price,
                "volume": _safe_float(kline.get("v")),
            },
            "polymarket_odds": odds,
            "volatility": volatility,
            "trigger_reason": trigger_reason,
            "bankroll": self.config.bankroll,
            "timestamp": _timestamp_ms_to_iso(_safe_int(kline.get("T"))),
        }

        state = self._normalize_state(raw_state)
        return TriggerEvent(task=self.config.task_prompt, invocation_state=state), last_spike_candle_open_ts

    def _normalize_state(self, raw_state: Mapping[str, Any]) -> dict[str, Any]:
        """Validate and normalize invocation state through the shared Pydantic model."""
        normalized = dict(raw_state)
        if not normalized.get("timestamp"):
            normalized["timestamp"] = _utc_now_iso()
        validated = InvocationState.model_validate(normalized)
        return validated.model_dump()


async def run_watchdog_graph_loop(
    graph: Any,
    watchdog: Watchdog,
    max_events: int | None = None,
) -> int:
    """Connect watchdog events to graph executions in a continuous loop."""
    processed = 0

    async for event in watchdog.iter_events(max_events=max_events):
        state = event.invocation_state
        print(
            f"[Watchdog] Trigger={state['trigger_reason']} "
            f"Asset={state['asset']} TF={state['timeframe']} Odds={state['polymarket_odds']}"
        )
        result = await graph.invoke_async(event.task, invocation_state=state)
        processed += 1

        status = getattr(result, "status", "unknown")
        completed = getattr(result, "completed_nodes", "?")
        total = getattr(result, "total_nodes", "?")
        elapsed = getattr(result, "execution_time", "?")
        print(f"[Graph] status={status} nodes={completed}/{total} elapsed={elapsed}ms")

        # Print root cause when any node fails (GraphResult stores per-node exceptions).
        result_map = getattr(result, "results", {}) or {}
        decision = _log_strategist_decision(result_map)

        # Auto-ingest GO signals into the vector store for future RAG retrieval.
        # This builds a self-improving memory: past signals that fired become context
        # for the Strategist's future decisions.
        if decision is not None and decision.decision == "GO":
            asyncio.create_task(
                _auto_ingest_signal(decision=decision, state=state)
            )

        for node_name, node_result in result_map.items():
            node_status = getattr(node_result, "status", None)
            node_payload = getattr(node_result, "result", None)
            if str(node_status).upper().endswith("FAILED") or isinstance(node_payload, Exception):
                print(f"[Graph] failed_node={node_name} error={node_payload}")

    return processed


async def _auto_ingest_signal(decision: "StrategistDecision", state: dict[str, Any]) -> None:
    """Background task: ingest a GO signal into the vector store after each cycle.

    This runs as a fire-and-forget task so it never blocks the main loop.
    The Context Analyst summarizes the signal context and upserts it to ChromaDB.
    """
    try:
        from agents.config import USE_RAG
        if not USE_RAG:
            return

        from agents.context_analyst.agent import ingest_context

        asset = state.get("asset", "BTC")
        ohlcv = state.get("ohlcv", {})
        odds = state.get("polymarket_odds", "?")
        timestamp = state.get("timestamp", "")

        raw_text = (
            f"GO signal fired for {asset} on {timestamp}. "
            f"OHLCV: open={ohlcv.get('open')}, high={ohlcv.get('high')}, "
            f"low={ohlcv.get('low')}, close={ohlcv.get('close')}, "
            f"volume={ohlcv.get('volume')}. "
            f"Polymarket odds: {odds}. "
            f"Strategist decision: {decision.decision}, "
            f"direction={decision.direction}, "
            f"probability={decision.probability:.2f}, "
            f"confidence={decision.confidence:.2f}. "
            f"Reasoning: {decision.reasoning}"
        )

        await ingest_context(raw_text=raw_text, asset=asset, source="signal_log")
        print(f"[Watchdog] Auto-ingested GO signal into vector store ({asset})")
    except Exception as exc:
        # Never crash the main loop because of a background ingest failure.
        print(f"[Watchdog] Auto-ingest failed (non-critical): {exc}")


def default_mock_states(asset: str = "BTC", timeframe: str = "15min", bankroll: float = DEFAULT_BANKROLL_USD) -> list[dict[str, Any]]:
    """Small deterministic state cycle for local loop testing."""
    return [
        {
            "asset": asset,
            "timeframe": timeframe,
            "ohlcv": {
                "open": 83200.0,
                "high": 83450.0,
                "low": 82800.0,
                "close": 82950.0,
                "volume": 1240.5,
            },
            "polymarket_odds": 1.68,
            "volatility": 0.0023,
            "trigger_reason": "candle_close",
            "bankroll": bankroll,
            "timestamp": _utc_now_iso(),
        },
        {
            "asset": asset,
            "timeframe": timeframe,
            "ohlcv": {
                "open": 85100.0,
                "high": 85800.0,
                "low": 84900.0,
                "close": 85600.0,
                "volume": 2100.0,
            },
            "polymarket_odds": 2.1,
            "volatility": 0.0041,
            "trigger_reason": "volatility_spike",
            "bankroll": bankroll,
            "timestamp": _utc_now_iso(),
        },
    ]


def _log_strategist_decision(result_map: Mapping[str, Any]) -> "StrategistDecision | None":
    """Log structured Strategist decision (GO/NO_GO) when available. Returns the decision."""
    strategist_node = result_map.get("strategist")
    if strategist_node is None:
        return None

    payload = getattr(strategist_node, "result", None)
    decision = _parse_strategist_decision(payload)
    if decision is None:
        print("[Strategist] decision=UNKNOWN")
        return None

    print(
        "[Strategist] "
        f"decision={decision.decision} "
        f"direction={decision.direction} "
        f"probability={decision.probability:.2f} "
        f"confidence={decision.confidence:.2f}"
    )
    return decision


def _parse_strategist_decision(payload: Any) -> StrategistDecision | None:
    """Best-effort parser for StrategistDecision from node payload."""
    if payload is None:
        return None

    structured = getattr(payload, "structured_output", None)
    if isinstance(structured, StrategistDecision):
        return structured

    if structured is not None:
        # Some SDK versions return dict-like structured output.
        try:
            return StrategistDecision.model_validate(structured)
        except Exception:
            pass

    text = str(payload)
    try:
        return StrategistDecision.model_validate_json(text)
    except Exception:
        pass

    lower_text = text.lower()
    if '"decision": "no_go"' in lower_text or '"decision":"no_go"' in lower_text:
        return StrategistDecision(
            decision="NO_GO",
            probability=0.5,
            direction="UP",
            confidence=0.5,
            reasoning="decision parsed from text fallback",
        )
    if '"decision": "go"' in lower_text or '"decision":"go"' in lower_text:
        return StrategistDecision(
            decision="GO",
            probability=0.5,
            direction="UP",
            confidence=0.5,
            reasoning="decision parsed from text fallback",
        )
    return None


def extract_polymarket_odds(payload: Any, preferred_asset_id: str | None = None) -> float | None:
    """
    Best-effort odds parser for Polymarket websocket payloads.

    Supports common shapes:
    - {"odds": 1.65}
    - {"price": 0.61}                  # probability
    - {"event": {"best_bid": 0.57}}  # probability
    """
    if payload is None:
        return None

    if isinstance(payload, Mapping):
        if "odds" in payload:
            odds = _number_to_odds(payload.get("odds"))
            if odds is not None:
                return odds
        if "decimal_odds" in payload:
            odds = _number_to_odds(payload.get("decimal_odds"))
            if odds is not None:
                return odds
        if "probability" in payload:
            odds = _number_to_odds(payload.get("probability"))
            if odds is not None:
                return odds
        if "yes_price" in payload:
            odds = _number_to_odds(payload.get("yes_price"))
            if odds is not None:
                return odds
        if "yes_probability" in payload:
            odds = _number_to_odds(payload.get("yes_probability"))
            if odds is not None:
                return odds

    probability = _extract_polymarket_probability(payload, preferred_asset_id=preferred_asset_id)
    if probability is None:
        return None
    return _number_to_odds(probability)


def _extract_polymarket_probability(payload: Any, preferred_asset_id: str | None = None) -> float | None:
    """Extract a probability in (0,1] from market-channel payload."""
    if isinstance(payload, (int, float, str)):
        number = _safe_float(payload)
        if 0 < number <= 1:
            return number
        return None

    if isinstance(payload, list):
        # Snapshot can arrive as a list of entries.
        preferred_probs: list[float] = []
        fallback_probs: list[float] = []
        for item in payload:
            p = _extract_polymarket_probability(item, preferred_asset_id=preferred_asset_id)
            if p is None:
                continue
            if preferred_asset_id and isinstance(item, Mapping) and str(item.get("asset_id")) == preferred_asset_id:
                preferred_probs.append(p)
            else:
                fallback_probs.append(p)
        if preferred_probs:
            return preferred_probs[0]
        if fallback_probs:
            return fallback_probs[0]
        return None

    if isinstance(payload, Mapping):
        # price_change event with multiple assets in the same message
        price_changes = payload.get("price_changes")
        if isinstance(price_changes, list):
            preferred_probs: list[float] = []
            fallback_probs: list[float] = []
            for change in price_changes:
                if not isinstance(change, Mapping):
                    continue
                p = _extract_probability_from_book_entry(change)
                if p is None:
                    continue
                if preferred_asset_id and str(change.get("asset_id")) == preferred_asset_id:
                    preferred_probs.append(p)
                else:
                    fallback_probs.append(p)
            if preferred_probs:
                return preferred_probs[0]
            if fallback_probs:
                return fallback_probs[0]

        # direct market snapshot entry
        if preferred_asset_id:
            asset_id = str(payload.get("asset_id", ""))
            if asset_id and asset_id != preferred_asset_id:
                return None
        p = _extract_probability_from_book_entry(payload)
        if p is not None:
            return p

        # Fallback recursive scan for nested payloads
        for value in payload.values():
            p = _extract_polymarket_probability(value, preferred_asset_id=preferred_asset_id)
            if p is not None:
                return p

    return None


def _extract_probability_from_book_entry(entry: Mapping[str, Any]) -> float | None:
    # Prefer best bid/ask mid when available.
    best_bid = _safe_float(entry.get("best_bid"))
    best_ask = _safe_float(entry.get("best_ask"))
    if best_bid > 0 and best_ask > 0:
        mid = (best_bid + best_ask) / 2
        if 0 < mid <= 1:
            return mid
    if best_bid > 0 and best_bid <= 1:
        return best_bid
    if best_ask > 0 and best_ask <= 1:
        return best_ask

    # Direct trade price fallback.
    trade_price = _safe_float(entry.get("price"))
    if 0 < trade_price <= 1:
        return trade_price

    # Orderbook snapshot fallback: max bid / min ask.
    bids = entry.get("bids")
    asks = entry.get("asks")
    if isinstance(bids, list) or isinstance(asks, list):
        bid_prices: list[float] = []
        ask_prices: list[float] = []
        if isinstance(bids, list):
            for bid in bids:
                if isinstance(bid, Mapping):
                    p = _safe_float(bid.get("price"))
                else:
                    p = _safe_float(bid)
                if 0 < p <= 1:
                    bid_prices.append(p)
        if isinstance(asks, list):
            for ask in asks:
                if isinstance(ask, Mapping):
                    p = _safe_float(ask.get("price"))
                else:
                    p = _safe_float(ask)
                if 0 < p <= 1:
                    ask_prices.append(p)

        best_bid = max(bid_prices) if bid_prices else 0.0
        best_ask = min(ask_prices) if ask_prices else 0.0
        if best_bid > 0 and best_ask > 0:
            mid = (best_bid + best_ask) / 2
            if 0 < mid <= 1:
                return mid
        if best_bid > 0:
            return best_bid
        if best_ask > 0:
            return best_ask
    return None


def build_polymarket_subscribe_from_search_result(
    payload: Mapping[str, Any],
    now_utc: datetime | None = None,
) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    """
    Build a market-channel subscribe payload from Gamma public-search response.

    Selection strategy:
    - active and not closed
    - valid 2 outcome token ids
    - endDate in the future
    - prefer "Up or Down" over "above/below" over everything else
    - then choose nearest endDate
    """
    now = now_utc or datetime.now(timezone.utc)
    events = payload.get("events")
    if not isinstance(events, list):
        return None, None

    candidates: list[tuple[int, float, dict[str, Any], list[str]]] = []
    for event in events:
        markets = event.get("markets") if isinstance(event, Mapping) else None
        if not isinstance(markets, list):
            continue

        for market in markets:
            if not isinstance(market, Mapping):
                continue
            if not bool(market.get("active")) or bool(market.get("closed")):
                continue

            token_ids = parse_clob_token_ids(market.get("clobTokenIds"))
            if len(token_ids) < 2:
                continue

            end_dt = _parse_iso_datetime(market.get("endDate"))
            if end_dt is not None and end_dt <= now:
                continue

            question = str(market.get("question", "")).lower()
            if "up or down" in question:
                priority = 0
            elif "above" in question or "below" in question:
                priority = 1
            else:
                priority = 2

            end_ts = end_dt.timestamp() if end_dt is not None else float("inf")
            candidates.append((priority, end_ts, dict(market), token_ids))

    if not candidates:
        return None, None

    candidates.sort(key=lambda x: (x[0], x[1]))
    _, _, selected_market, token_ids = candidates[0]
    subscribe_payload = {
        "assets_ids": token_ids[:2],
        "type": "market",
        "custom_feature_enabled": True,
    }
    return subscribe_payload, selected_market


def parse_clob_token_ids(raw: Any) -> list[str]:
    """Parse clobTokenIds from JSON string/list into a normalized list[str]."""
    parsed = raw
    if isinstance(raw, str):
        maybe_json = _json_load_maybe(raw)
        if isinstance(maybe_json, list):
            parsed = maybe_json
        else:
            parsed = [part.strip() for part in raw.split(",")]

    if not isinstance(parsed, list):
        return []

    token_ids: list[str] = []
    for item in parsed:
        token = str(item).strip()
        if token:
            token_ids.append(token)
    return token_ids


def _number_to_odds(value: Any) -> float | None:
    number = _safe_float(value)
    if number <= 0:
        return None

    # Probability payload (0, 1] -> decimal odds
    if number <= 1:
        return round(1.0 / number, 4)

    # Already decimal odds
    if number < 100:
        return round(number, 4)

    return None


def _json_load_maybe(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except Exception:
        return value


def _timeframe_to_binance_interval(timeframe: str) -> str:
    mapping = {
        "1min": "1m",
        "5min": "5m",
        "15min": "15m",
        "1h": "1h",
    }
    return mapping.get(timeframe, "15m")


def _timestamp_ms_to_iso(timestamp_ms: int) -> str:
    if timestamp_ms <= 0:
        return _utc_now_iso()
    dt = datetime.fromtimestamp(timestamp_ms / 1000, tz=timezone.utc)
    return dt.isoformat()


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_float(value: Any) -> float:
    try:
        return float(value)
    except Exception:
        return 0.0


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except Exception:
        return 0


def _parse_iso_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        text = str(value).strip()
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        dt = datetime.fromisoformat(text)
        return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)
    except Exception:
        return None


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _build_polymarket_queries(primary_query: str) -> list[str]:
    base = [
        primary_query.strip(),
        "bitcoin up or down",
        "bitcoin above",
        "bitcoin",
    ]
    deduped: list[str] = []
    seen: set[str] = set()
    for q in base:
        key = q.lower()
        if not q or key in seen:
            continue
        seen.add(key)
        deduped.append(q)
    return deduped
