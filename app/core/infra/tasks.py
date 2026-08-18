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

_MAX_BACKGROUND_TASKS: int = 1000
_background_tasks: set[asyncio.Task[Any]] = set()


def _schedule_cross_thread(coro: Coroutine[Any, Any, Any]) -> None:
    """Schedules a coroutine from a synchronous thread onto the running AnyIO event loop."""
    import anyio.from_thread

    async def _schedule() -> None:
        safe_create_task(coro)

    try:
        anyio.from_thread.run(_schedule)
    except Exception as err:
        logger.error("Failed to schedule background task cross-thread: %s", err, exc_info=err)
        sentry_sdk.capture_exception(err)
        with suppress(Exception):
            coro.close()


def safe_create_task(
    coro: Coroutine[Any, Any, Any],
) -> asyncio.Task[Any] | None:
    """Spawns an asyncio task with exception handling and Sentry error reporting.

    Supports execution from synchronous worker threads by scheduling onto the main
    event loop thread via AnyIO if no running loop is present in current thread.

    Args:
        coro: The coroutine object to run in the background.

    Returns:
        asyncio.Task[Any] | None: The spawned asyncio.Task object, or None if scheduled cross-thread or dropped.
    """
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        _schedule_cross_thread(coro)
        return None

    if len(_background_tasks) >= _MAX_BACKGROUND_TASKS:
        coro_name = getattr(coro, "__qualname__", str(coro))
        logger.error(
            "Background task set at capacity (%d); dropping task %s",
            _MAX_BACKGROUND_TASKS,
            coro_name,
        )
        sentry_sdk.capture_message(
            f"Background task set capacity ({_MAX_BACKGROUND_TASKS}) exceeded; task dropped: {coro_name}",
            level="error",
            tags={"coroutine": coro_name, "location": "safe_create_task"},
        )
        with suppress(Exception):
            coro.close()
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


async def run_with_retries(
    factory: Any,
    *args: Any,
    max_retries: int = 3,
    backoff_factor: float = 1.5,
    initial_delay: float = 0.5,
    **kwargs: Any,
) -> Any:
    """Executes an async callable factory with exponential backoff retries on failure."""
    delay = initial_delay
    last_exc: Exception | None = None
    for attempt in range(1, max_retries + 1):
        try:
            if asyncio.iscoroutinefunction(factory):
                return await factory(*args, **kwargs)
            res = factory(*args, **kwargs)
            if asyncio.iscoroutine(res):
                return await res
            return res
        except Exception as err:
            last_exc = err
            logger.warning(
                "Task execution attempt %d/%d failed: %s; retrying in %.2fs",
                attempt,
                max_retries,
                err,
                delay,
            )
            if attempt == max_retries:
                logger.error(
                    "Task execution failed after %d retries: %s",
                    max_retries,
                    err,
                    exc_info=err,
                )
                sentry_sdk.capture_exception(err)
                raise
            await asyncio.sleep(delay)
            delay *= backoff_factor
    if last_exc:
        raise last_exc
    return None


