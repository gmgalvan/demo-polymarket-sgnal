#!/usr/bin/env python3
"""Small async load generator for the TinyLlama Neuron example.

Uses only the Python standard library so it can run anywhere without
installing extra dependencies.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run concurrent requests against the vLLM OpenAI-compatible API."
    )
    parser.add_argument(
        "--url",
        default="http://127.0.0.1:8000/v1/chat/completions",
        help="Target chat completions endpoint.",
    )
    parser.add_argument(
        "--payload",
        default=str(Path(__file__).with_name("request.chat-test.json")),
        help="Path to the JSON request body.",
    )
    parser.add_argument(
        "--requests",
        type=int,
        default=10,
        help="Total number of requests to send.",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=5,
        help="Maximum number of in-flight requests.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=180.0,
        help="Per-request timeout in seconds.",
    )
    parser.add_argument(
        "--print-samples",
        type=int,
        default=0,
        help="Print the first N response snippets for demo/debugging.",
    )
    return parser.parse_args()


def load_payload(payload_path: str) -> bytes:
    raw = Path(payload_path).read_text(encoding="utf-8")
    json.loads(raw)
    return raw.encode("utf-8")


def do_request(url: str, payload: bytes, timeout: float) -> tuple[bool, float, int, str]:
    started = time.perf_counter()
    request = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            elapsed = time.perf_counter() - started
            return True, elapsed, response.status, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        elapsed = time.perf_counter() - started
        return False, elapsed, exc.code, body
    except Exception as exc:  # noqa: BLE001
        elapsed = time.perf_counter() - started
        return False, elapsed, 0, str(exc)


async def worker(
    name: str,
    queue: asyncio.Queue[int],
    semaphore: asyncio.Semaphore,
    url: str,
    payload: bytes,
    timeout: float,
    samples: list[str],
    print_samples: int,
) -> list[tuple[bool, float, int]]:
    results: list[tuple[bool, float, int]] = []

    while True:
        try:
            req_id = queue.get_nowait()
        except asyncio.QueueEmpty:
            return results

        async with semaphore:
            ok, elapsed, status, body = await asyncio.to_thread(
                do_request, url, payload, timeout
            )
            results.append((ok, elapsed, status))

            if len(samples) < print_samples:
                snippet = body.strip().replace("\n", " ")
                samples.append(
                    f"[{name} req={req_id} status={status} ok={ok} {elapsed:.2f}s] "
                    f"{snippet[:220]}"
                )

        queue.task_done()


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    index = (len(ordered) - 1) * pct
    lower = int(index)
    upper = min(lower + 1, len(ordered) - 1)
    if lower == upper:
        return ordered[lower]
    fraction = index - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


async def main() -> int:
    args = parse_args()
    payload = load_payload(args.payload)

    if args.requests < 1:
        print("--requests must be >= 1", file=sys.stderr)
        return 2
    if args.concurrency < 1:
        print("--concurrency must be >= 1", file=sys.stderr)
        return 2

    queue: asyncio.Queue[int] = asyncio.Queue()
    for req_id in range(1, args.requests + 1):
        queue.put_nowait(req_id)

    semaphore = asyncio.Semaphore(args.concurrency)
    samples: list[str] = []
    started = time.perf_counter()

    tasks = [
        asyncio.create_task(
            worker(
                f"w{i + 1}",
                queue,
                semaphore,
                args.url,
                payload,
                args.timeout,
                samples,
                args.print_samples,
            )
        )
        for i in range(min(args.concurrency, args.requests))
    ]

    grouped_results = await asyncio.gather(*tasks)
    elapsed_total = time.perf_counter() - started

    results = [item for group in grouped_results for item in group]
    successes = [r for r in results if r[0]]
    failures = [r for r in results if not r[0]]
    latencies = [r[1] for r in results]

    print(f"target_url={args.url}")
    print(f"total_requests={len(results)} concurrency={args.concurrency}")
    print(f"ok={len(successes)} failed={len(failures)}")
    print(f"wall_time_sec={elapsed_total:.2f}")
    if elapsed_total > 0:
        print(f"effective_rps={len(results) / elapsed_total:.2f}")

    if latencies:
        print(f"latency_min_sec={min(latencies):.2f}")
        print(f"latency_avg_sec={statistics.fmean(latencies):.2f}")
        print(f"latency_p50_sec={percentile(latencies, 0.50):.2f}")
        print(f"latency_p90_sec={percentile(latencies, 0.90):.2f}")
        print(f"latency_p99_sec={percentile(latencies, 0.99):.2f}")
        print(f"latency_max_sec={max(latencies):.2f}")

    if samples:
        print("\nresponse_samples:")
        for sample in samples:
            print(sample)

    if failures:
        print("\nfailures:")
        for ok, elapsed, status in failures[:10]:
            print(f"ok={ok} status={status} latency_sec={elapsed:.2f}")
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
