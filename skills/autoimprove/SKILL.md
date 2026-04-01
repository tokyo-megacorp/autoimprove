---
name: autoimprove
description: |
  Main entry point for the autonomous improvement loop. Use when the harness calls `Skill(autoimprove)`, when the user runs `/autoimprove`, or when the user asks to start the full research → experiment → judge → converge flow.

  This is an alias for the `run` skill. It exists so callers can invoke the top-level `autoimprove` skill name directly without failing with "Unknown skill: autoimprove".
argument-hint: "[--experiments N] [--theme THEME] [--resume] [--phase propose]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

Treat this invocation as equivalent to the `run` skill.

Before doing any work, read `skills/run/SKILL.md`, then follow its instructions exactly while preserving any user-supplied arguments from this `autoimprove` invocation.

Key requirements:

1. Do not do any work before loading `skills/run/SKILL.md`.
2. Preserve the same argument semantics as `run`.
3. Execute the full orchestrator flow from the `run` skill after loading it.
