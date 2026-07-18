import asyncio
from collections.abc import Coroutine
from contextlib import suppress
from typing import Any

import sentry_sdk


def safe_create_task(
    coro: Coroutine[Any, Any, Any],
) -> asyncio.Task[Any] | None:
    """
    Spawns an asyncio task with exception handling to report unhandled
    errors to Sentry instead of swallowing them.
    Supports being called from synchronous contexts (worker threads) when
    there is no running event loop in the current thread.
    """
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        import anyio.from_thread

        async def _schedule():
            safe_create_task(coro)

        with suppress(Exception):
            anyio.from_thread.run(_schedule)
        return None

    task = asyncio.create_task(coro)

    def done_callback(t: asyncio.Task[Any]) -> None:
        try:
            exc = t.exception()
            if exc:
                sentry_sdk.capture_exception(exc)
        except asyncio.CancelledError:
            pass
        except Exception as e:  # noqa: BLE001
            sentry_sdk.capture_exception(e)

    task.add_done_callback(done_callback)
    return task
