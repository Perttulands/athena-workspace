from pathlib import Path


CENTURION = Path("scripts/centurion.sh")
PROMOTE = Path("scripts/centurion-promote.sh")
SHARED_GATE = Path("scripts/lib/centurion-test-gate.sh")


def test_scripts_source_shared_test_gate_library() -> None:
    assert SHARED_GATE.exists(), "shared test gate library should exist"

    shared_source = 'source "$SCRIPT_DIR/lib/centurion-test-gate.sh"'
    centurion_text = CENTURION.read_text(encoding="utf-8")
    promote_text = PROMOTE.read_text(encoding="utf-8")

    assert shared_source in centurion_text
    assert shared_source in promote_text


def test_test_gate_function_is_not_duplicated_inline() -> None:
    centurion_text = CENTURION.read_text(encoding="utf-8")
    promote_text = PROMOTE.read_text(encoding="utf-8")

    assert "run_test_gate()" not in centurion_text
    assert "run_test_gate()" not in promote_text
