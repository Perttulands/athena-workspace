#!/usr/bin/env bash
# shellcheck shell=bash
#
# Canonical path resolver for Athena workspace scripts.
# Override via env when needed:
#   ATHENA_WORKSPACE=/custom/path OPENCLAW_HOME=/custom/.openclaw

if [[ -v ATHENA_WORKSPACE ]]; then
    ATHENA_WORKSPACE="${ATHENA_WORKSPACE:?ATHENA_WORKSPACE cannot be empty}"
else
    ATHENA_WORKSPACE="${WORKSPACE:-$HOME/athena}"
fi

if [[ -v OPENCLAW_HOME ]]; then
    OPENCLAW_HOME="${OPENCLAW_HOME:?OPENCLAW_HOME cannot be empty}"
else
    OPENCLAW_HOME="$HOME/.openclaw"
fi

export ATHENA_WORKSPACE OPENCLAW_HOME
