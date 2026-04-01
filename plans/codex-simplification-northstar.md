# Simplification Plan — autoimprove vs autoresearch northstar

> Source: Codex rescue analysis, 2026-04-01
> Reference: github.com/karpathy/autoresearch

## North Star (autoresearch)

- One file the agent edits (`train.py`), one humans control (`program.md`), one frozen forever (`prepare.py`)
- One loop: edit → commit → run → read single scalar (`val_bpb`) → keep or revert
- Fixed 5-minute budget per experiment so comparisons stay fair
- One baseline: run current code first
- Results go to one untracked `results.tsv`
- No new deps, no evaluation changes, no touching the fixed file
- Simplicity is explicit policy — equal-or-better with less code is a win

## Complexity Delta (what autoimprove added beyond northstar)

| Category | What autoimprove added |
|---|---|
| Architecture | Blind two-agent system, trust ratchet, dual baselines, stagnation logic, coverage gates, state checkpoints |
| Config | `autoimprove.yaml` com budgets, gates, weighted multi-metric benchmarks, theme selection, tiering, phase config, safety knobs |
| Phases | Grind + Propose + Research com automatic transitions |
| Tooling | Multiple skills/agents/commands, experiment context files, reports, proposals |

## Simplification Proposals

| O que | Por que é seguro | Risco |
|---|---|---|
| Ship só Grind, cortar Propose + Research do v1 | autoresearch prova que o core loop funciona sozinho | perde handoff path para mudanças maiores |
| Substituir big YAML por minimal control file (scope, test cmd, benchmark cmd, budget, forbidden paths) | maioria dos knobs é policy tuning, não loop invariants | menos customização por projeto |
| Drop trust ratchet tiers | verifiabilidade é o constraint real, não scope | diff grande pode merecer revisão manual |
| Scoring colapsado: gates pass + no metric regress + primary improves | mais próximo do autoresearch | benchmarks ruidosos podem precisar de reruns |
| Um agente, não dois — imutabilidade via worktree discard em vez de "agente cego" | correção vem do discard + eval imutável, não de segredo | mais pressão de Goodhart |
| Cortar `/calibrate` e comandos não-core até `/autoimprove run` existir | meta-tooling antes do loop principal é upside-down | tuning mais lento |

## Keep List

- Git worktrees (mais seguro que `git reset` para repos arbitrários)
- Benchmark/test imutáveis via `forbidden_paths` + testes additive-only (análogo ao `prepare.py` congelado)
- Hard gates rápidos antes dos benchmarks completos
- Experiment log mais rico que `results.tsv` — reduzido ao essencial
