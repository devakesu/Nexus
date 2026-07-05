import asyncio
from collections.abc import Coroutine
from typing import Any

import sentry_sdk


def safe_create_task(coro: Coroutine[Any, Any, Any]) -> asyncio.Task[Any]:
    """
    Spawns an asyncio task with exception handling to report unhandled
    errors to Sentry instead of swallowing them.
    """
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
