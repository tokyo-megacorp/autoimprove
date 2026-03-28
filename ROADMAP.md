# Version Roadmap — autoimprove

## Unreleased

### Added
- Signal validation guards before write — reject malformed YAML signals (#8, PR #9)
- xgh metrification — signal collection + autoimprove pipeline (#8, PR #8)
- AR coverage gate CI workflow (PR #10)
- Dependabot + CodeQL scanning (PR #11)

### Fixed
- Python heredoc → env-var passing in autoimprove-trigger.sh (#15, PR #16)

---

## v0.1.0 — (not yet released)

Pre-release. Core trigger pipeline functional. Signal validation, metrics, and CI gates in place.

**Release gate:** adversarial review + Co-CEO greenlight required before first npm/PyPI publish.
