from pathlib import Path


CENTURION = Path("scripts/centurion.sh")
PROMOTE = Path("scripts/centurion-promote.sh")
SHARED_WAKE = Path("scripts/lib/centurion-wake.sh")


def test_scripts_source_shared_wake_library() -> None:
    assert SHARED_WAKE.exists(), "shared wake helper library should exist"

    shared_source = 'source "$SCRIPT_DIR/lib/centurion-wake.sh"'
    centurion_text = CENTURION.read_text(encoding="utf-8")
    promote_text = PROMOTE.read_text(encoding="utf-8")

    assert shared_source in centurion_text
    assert shared_source in promote_text


def test_wake_helper_is_not_duplicated_inline() -> None:
    centurion_text = CENTURION.read_text(encoding="utf-8")
    promote_text = PROMOTE.read_text(encoding="utf-8")

    assert "notify_wake_gateway()" not in centurion_text
    assert "notify_wake_gateway()" not in promote_text
