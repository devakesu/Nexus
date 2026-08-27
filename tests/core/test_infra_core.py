"""Test Suite for Test Infra Core.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import asyncio
import copy
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.infra.tasks import (
    _MAX_BACKGROUND_TASKS,
    _background_tasks,
    run_with_retries,
    safe_create_task,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


async def test_core_infra_tasks_deep():
    from app.core.infra.tasks import _MAX_BACKGROUND_TASKS, safe_create_task

    async def dummy():
        return 1

    # Normal execution
    t = safe_create_task(dummy())
    assert t is not None
    await t

    # At capacity
    mock_set = {MagicMock() for _ in range(_MAX_BACKGROUND_TASKS)}
    with patch("app.core.infra.tasks._background_tasks", mock_set):
        t_dropped = safe_create_task(dummy())
        assert t_dropped is None


async def test_core_infra_tasks_deep_p20():
    from app.core.infra.tasks import (
        _MAX_BACKGROUND_TASKS,
        _schedule_cross_thread,
        run_with_retries,
        safe_create_task,
    )

    async def dummy_coro():
        return 42

    async def failing_coro():
        raise ValueError("Task error")

    # safe_create_task when running loop exists
    t = safe_create_task(dummy_coro())
    assert t is not None
    await t

    # safe_create_task done_callback exception handling
    f_task = safe_create_task(failing_coro())
    assert f_task is not None
    with pytest.raises(ValueError):
        await f_task

    # safe_create_task when background task set capacity reached
    with patch(
        "app.core.infra.tasks._background_tasks",
        {MagicMock() for _ in range(_MAX_BACKGROUND_TASKS)},
    ):
        c = dummy_coro()
        dropped = safe_create_task(c)
        assert dropped is None

    # safe_create_task without running loop -> _schedule_cross_thread
    with (
        patch("asyncio.get_running_loop", side_effect=RuntimeError("no running loop")),
        patch("app.core.infra.tasks._schedule_cross_thread") as mock_sched,
    ):
        c = dummy_coro()
        ret = safe_create_task(c)
        assert ret is None
        mock_sched.assert_called_once()
        c.close()

    # _schedule_cross_thread error handling
    with patch("anyio.from_thread.run", side_effect=Exception("Cross thread error")):
        _schedule_cross_thread(dummy_coro())

    # run_with_retries: non-coroutine factory, sync coroutine return, max retries failure
    def _double(x: int) -> int:
        return x * 2

    assert await run_with_retries(_double, 5) == 10

    def sync_returning_coro(val: int):
        async def _inner() -> int:
            return val + 1

        return _inner()

    assert await run_with_retries(sync_returning_coro, 5) == 6

    # Retries exhausted
    call_count = 0

    async def always_fails():
        nonlocal call_count
        call_count += 1
        raise RuntimeError("always fails")

    with pytest.raises(RuntimeError, match="always fails"):
        await run_with_retries(always_fails, max_retries=2, initial_delay=0.01)
    assert call_count == 2


async def test_core_tasks_and_retries() -> None:
    # safe_create_task in running loop
    async def dummy_coro() -> int:
        await asyncio.sleep(0.01)
        return 42

    task = safe_create_task(dummy_coro())
    assert task is not None
    await task

    # Task capacity full
    _background_tasks.clear()
    dummy_tasks = {MagicMock() for _ in range(_MAX_BACKGROUND_TASKS)}
    _background_tasks.update(dummy_tasks)

    dropped = safe_create_task(dummy_coro())
    assert dropped is None
    _background_tasks.clear()

    # run_with_retries success
    call_count = 0

    async def flaky_async() -> str:
        nonlocal call_count
        call_count += 1
        if call_count < 2:
            raise ValueError("transient error")
        return "success"

    res = await run_with_retries(flaky_async, max_retries=3, initial_delay=0.01)
    assert res == "success"

    # run_with_retries exhaustion
    async def always_fails() -> None:
        raise RuntimeError("fatal failure")

    with pytest.raises(RuntimeError):
        await run_with_retries(always_fails, max_retries=2, initial_delay=0.01)
