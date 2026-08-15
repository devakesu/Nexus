"""Asynchronous task execution utilities with error reporting.

Provides safe background task creation with automatic exception capturing and Sentry logging
across both async event loop threads and sync worker threads.
"""

import asyncio
import logging
from collections.abc import Coroutine
from contextlib import suppress
from typing import Any

import sentry_sdk

logger = logging.getLogger(__name__)


_background_tasks: set[asyncio.Task[Any]] = set()


def safe_create_task(
    coro: Coroutine[Any, Any, Any],
) -> asyncio.Task[Any] | None:
    """Spawns an asyncio task with exception handling and Sentry error reporting.

    Supports execution from synchronous worker threads by scheduling onto the main
    event loop thread via AnyIO if no running loop is present in current thread.

    Args:
        coro: The coroutine object to run in the background.

    Returns:
        asyncio.Task[Any] | None: The spawned asyncio.Task object, or None if scheduled cross-thread.
    """
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        import anyio.from_thread

        async def _schedule() -> None:
            """Schedule the target coroutine onto the running event loop."""
            safe_create_task(coro)

        with suppress(Exception):
            anyio.from_thread.run(_schedule)
        return None

    task = asyncio.create_task(coro)
    _background_tasks.add(task)

    def done_callback(t: asyncio.Task[Any]) -> None:
        """Callback invoked upon task completion to capture and report unhandled exceptions to Sentry.

        Args:
            t: The completed asyncio.Task instance.
        """
        _background_tasks.discard(t)
        try:
            exc = t.exception()
            if exc:
                logger.error("Unhandled exception in background task: %s", exc, exc_info=exc)
                sentry_sdk.capture_exception(exc)
        except asyncio.CancelledError:
            pass
        except asyncio.InvalidStateError as e:
            logger.error("Invalid task state during completion callback: %s", e, exc_info=e)
            sentry_sdk.capture_exception(e)

    task.add_done_callback(done_callback)
    return task

