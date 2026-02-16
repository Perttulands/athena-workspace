# Test Fixtures

This directory contains test prompts and expected outputs for the E2E dispatch tests.

## Files

- `simple-success.txt` - A simple prompt that should succeed (creates a test file)
- `simple-failure.txt` - A prompt that intentionally fails (exit code 42)
- `quick-echo.txt` - A quick prompt for fast completion testing
- `expected-output-*.txt` - Expected output patterns for validation

## Usage

These fixtures are used by `tests/test-e2e-dispatch.sh` to test various scenarios
of the non-blocking dispatch system.
