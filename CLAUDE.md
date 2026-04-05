# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Primary Reference

All repository context, conventions, and architecture documentation lives in [AGENTS.md](AGENTS.md).
Read that file first. It contains an index to deep-dive docs under `docs/` — load those on demand
when working on the relevant subsystem.

## Claude-Specific Instructions

- When modifying shell scripts, validate with `shellcheck --severity=warning` before considering the task complete.
- When modifying Dockerfiles, validate with `hadolint` before considering the task complete.
- When modifying GitHub Actions workflows, verify SHA-pinned action references include a trailing version comment (e.g., `# v6.0.2`).
