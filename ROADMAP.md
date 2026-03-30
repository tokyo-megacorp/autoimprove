# Version Roadmap — autoimprove

## Unreleased

_(nothing yet)_

---

## v0.1.0 — 2026-03-30

Inaugural release. Core trigger pipeline functional. Signal validation, metrics, CI gates, and full grind loop in place.

### Added
- Full grind loop — orchestrator + experimenter in isolated git worktrees
- 18 skills, 10 agents, 8 commands
- autoimprove.yaml config schema with themes, focus_paths, gates, budget
- Theme engine Phases 1–3: harvest → focus_paths → dynamic weight adjustment (#37)
- Self-metrics benchmark: skill_depth, agent_sections, test_count
- ~290 test assertions (test/evaluate/test-evaluate.sh)
- Signal validation guards before write — reject malformed YAML signals (#8, PR #9)
- xgh metrification — signal collection + autoimprove pipeline (#8, PR #8)
- AR coverage gate CI workflow (PR #10)
- Dependabot + CodeQL scanning (PR #11)
- diagnose skill for config validation and benchmark debugging
- diff skill for inspecting experiment code changes
- rollback skill for reverting kept experiments
- decisions skill with --since, --verdict, --search filters

### Fixed
- Python heredoc → env-var passing in autoimprove-trigger.sh (#15, PR #16)
- evaluate.sh calling convention — cd to worktree first (#41)
- AR background execution reliability pattern (#152)
- Tool parameter validation guard in adversary + judge agents (#147)
