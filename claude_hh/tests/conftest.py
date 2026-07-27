"""Hermetic sandbox: keep the cross-agent memory store inside tmp dirs.

`_memory_dir` falls back to the global store when no project-local
`.agent-memory` exists; without this fixture, tests would write into the
developer's real `~/.agent-memory`.
"""

import pytest

from claude_hh import delivery


@pytest.fixture(autouse=True)
def _sandbox_global_memory(tmp_path, monkeypatch):
    monkeypatch.setattr(
        delivery, "GLOBAL_MEMORY_DIR", tmp_path / "global-agent-memory"
    )
