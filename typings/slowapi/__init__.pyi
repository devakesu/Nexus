from collections.abc import Callable
from typing import Any, TypeVar

F = TypeVar("F", bound=Callable[..., Any])

class Limiter:
    def __init__(self, key_func: Callable[..., str], enabled: bool = True) -> None: ...
    def limit(
        self,
        limit_value: str | Callable[..., str],
        key_func: Callable[..., str] | None = None,
        per_method: bool = False,
        methods: list[str] | None = None,
        error_message: str | None = None,
        exempt_when: Callable[..., bool] | None = None,
        cost: int | Callable[..., int] = 1,
        override_defaults: bool = True,
    ) -> Callable[[F], F]: ...
