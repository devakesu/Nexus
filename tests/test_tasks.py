"""Unit tests for background task execution, capacity limiting, and error reporting."""

import asyncio
from unittest.mock import MagicMock, patch

import pytest

from app.api.dependencies import (
    _MAX_BACKGROUND_TASKS as DEP_MAX_TASKS,
)
from app.api.dependencies import (
    _background_tasks as dep_background_tasks,
)
from app.api.dependencies import (
    get_authenticated_user_id,
)
from app.core.infra.tasks import (
    _MAX_BACKGROUND_TASKS,
    _background_tasks,
    run_with_retries,
    safe_create_task,
)


@pytest.mark.anyio
async def test_safe_create_task_normal_execution() -> None:
    """Verifies that safe_create_task spawns and tracks a task under capacity."""
    _background_tasks.clear()
    executed = False

    async def sample_coro():
        nonlocal executed
        executed = True

    task = safe_create_task(sample_coro())
    assert task is not None
    await task
    assert executed is True
    # Task should be removed from set on completion
    await asyncio.sleep(0.01)
    assert len(_background_tasks) == 0


@pytest.mark.anyio
@patch("app.core.infra.tasks.sentry_sdk.capture_message")
async def test_safe_create_task_drops_and_alerts_at_capacity(mock_capture: MagicMock) -> None:
    """Verifies that safe_create_task drops tasks and alerts Sentry when capacity is reached."""
    _background_tasks.clear()
    dummy_tasks = [asyncio.create_task(asyncio.sleep(10)) for _ in range(_MAX_BACKGROUND_TASKS)]
    for dt in dummy_tasks:
        _background_tasks.add(dt)

    async def dropped_coro():
        pass

    try:
        coro = dropped_coro()
        result = safe_create_task(coro)
        assert result is None
        mock_capture.assert_called_once()
        call_args, call_kwargs = mock_capture.call_args
        assert "capacity" in call_args[0]
        assert call_kwargs.get("level") == "error"
    finally:
        for dt in dummy_tasks:
            dt.cancel()
        _background_tasks.clear()


@pytest.mark.anyio
async def test_presence_task_drop_logs_warning_at_capacity(caplog: pytest.LogCaptureFixture) -> None:
    """Verifies that presence background task drops at capacity log warning."""
    dep_background_tasks.clear()
    dummy_tasks = [asyncio.create_task(asyncio.sleep(10)) for _ in range(DEP_MAX_TASKS)]
    for dt in dummy_tasks:
        dep_background_tasks.add(dt)

    payload = {"sub": "user-cap-alert"}
    try:
        user_id = await get_authenticated_user_id(payload)
        assert user_id == "user-cap-alert"
        assert "Background presence task queue at capacity" in caplog.text
    finally:
        for dt in dummy_tasks:
            dt.cancel()
        dep_background_tasks.clear()


@pytest.mark.anyio
async def test_run_with_retries_success_after_failure() -> None:
    """Verifies that run_with_retries retries on transient errors and returns result."""
    attempts = 0

    async def flaky_operation(val: int):
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise ConnectionError("Transient network failure")
        return val * 2

    res = await run_with_retries(
        flaky_operation,
        21,
        max_retries=3,
        initial_delay=0.01,
        backoff_factor=1.0,
    )
    assert res == 42
    assert attempts == 3


@pytest.mark.anyio
@patch("app.core.infra.tasks.sentry_sdk.capture_exception")
async def test_run_with_retries_exceeds_max_retries(mock_capture_exception: MagicMock) -> None:
    """Verifies that exceeding max retries captures exception to Sentry and raises."""
    async def always_failing():
        raise RuntimeError("Permanent failure")

    with pytest.raises(RuntimeError, match="Permanent failure"):
        await run_with_retries(
            always_failing,
            max_retries=2,
            initial_delay=0.01,
            backoff_factor=1.0,
        )

    mock_capture_exception.assert_called_once()
