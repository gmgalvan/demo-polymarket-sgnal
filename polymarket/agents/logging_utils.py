"""Simple shared log formatting helpers."""

from __future__ import annotations


def log_line(service: str, component: str, message: str) -> None:
    """Print a log line with a consistent, grep-friendly prefix."""
    print(f"[{service}][{component}] {message}")

