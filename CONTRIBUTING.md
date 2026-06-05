# Contributing to gebug-audit

Thanks for considering a contribution. This document explains how to
propose changes, what kinds of changes fit the project, and the standards
the code and docs are held to.

## Ground rules

- **English only.** All committed prose, comments, and docstrings must
  be in English. Translate before submitting.
- **No em dashes (`-`)** anywhere in the repo. Use a regular hyphen
  (`-`) or rewrite. The skills enforce this on their generated audit
  output; the source files match the same rule for consistency.
- **EVM-only.** Do not add Solana, Move, CosmWasm, or other non-EVM
  content to bundled checklists or attack-vector docs. If you want
  non-EVM coverage, build it as a sibling repo.
- **No `cast send` / `forge create` / `forge script --broadcast`.**
  Any change that loosens the no-broadcast safety policy will be
  rejected.
- **Cite `file:line`.** When an attack-vector doc, pipeline reference,
  or finding template makes a claim about contract behavior, cite the
  source. No citation, no claim.

## What kinds of contributions fit

### Wanted

- **New attack-vector docs.** Examples: `perp.md` (Perpetual /
  GMX-class), `stablecoin.md` (FRAX / DAI / crvUSD-class),
  `intent-protocol.md` (UniswapX / CowSwap), `account-abstraction.md`
  (ERC-4337 / EIP-7702), `vault-yield.md` (Yearn V3 / ERC4626 wrappers
  beyond the LST patterns already in `lst-lrt.md`).
- **Coverage gaps in existing attack-vector docs.** A new lending fork
  pattern, an EigenLayer change post-Pectra, a fresh Uniswap v4 hook
  pitfall.
- **Improvements to the validity gate or severity calibration.** Real
  audits that revealed a flaw in the current rejection-only-with-proof
  rule.
- **New focused modes** for `/gebug-work` that match common workflows
  (e.g., a `diff-audit` mode that focuses on changed files only).
- **Bug reports from real audits** where the pipeline missed something.
  A reproducible miss is the most valuable feedback this project can
  receive.
- **Pipeline simplifications.** If a phase is overweight or duplicated,
  cut it.

### Not wanted

- Refactors with no behavior change just to "clean things up".
- Style / naming PRs against the skills themselves (the skill is what
  it is; if a name is genuinely misleading, file an issue first).
- Adding new top-level files (more `*.md` at the root) without a
  concrete reader in mind.
- Wrappers, abstractions, or "frameworks" that introduce indirection
  without removing more complexity than they add.
- Documentation that says what the code already says.

## Repository layout

```
gebug-audit/
├── README.md             project overview
├── CLAUDE.md             instructions for Claude Code in this repo
├── CONTRIBUTING.md       this file
├── LICENSE               MIT
├── install.sh            symlink installer
├── uninstall.sh
├── assets/
│   └── logo.png
└── skills/
    ├── gebug-brainstorm/
    │   ├── SKILL.md
    │   ├── README.md
    │   └── references/
    │       └── brainstorm-pipeline.md
    └── gebug-work/
        ├── SKILL.md
        ├── README.md
        ├── agents/
        │   ├── vuln-hunter.md
        │   └── exploit-writer.md
        └── references/
            ├── work-pipeline.md
            └── attack-vectors/
                ├── amm.md
                ├── bridge.md
                ├── governance.md
                ├── lending.md
                ├── lst-lrt.md
                ├── oracle-integration.md
                └── restaking.md
```

`SKILL.md` is loaded into Claude Code's context whenever the skill is
triggered. Keep it focused: trigger criteria, safety policy, doctrine,
phase summary, output layout, pointer to the pipeline reference.

`references/*-pipeline.md` is the single source of truth for execution
detail (bash commands, file templates, phase ordering). Never duplicate
execution detail between `SKILL.md` and the pipeline reference.

## Adding a new attack-vector doc

1. Create `skills/gebug-work/references/attack-vectors/<topic>.md`
   following the existing structure:
   - Opening paragraph: when this doc applies, which target types.
   - "Reachability check" section: 4 - 5 questions every candidate must
     answer.
   - Numbered items (`A1`, `A2`, etc.) per attack class, each with a
     mechanism description and one or more `**Probe**:` lines.
   - Closing "Common bugs (observed historically)" table where you can
     point at real postmortems.
2. Add the topic to the mapping in two places:
   - `skills/gebug-brainstorm/references/brainstorm-pipeline.md`
     PHASE 6 (the target-type -> docs table).
   - `skills/gebug-work/agents/vuln-hunter.md` "Default mapping"
     section.
3. Add a row to the "Attack-vector coverage" table in the top-level
   `README.md`.

Inconsistent structure across attack-vector docs makes the
`vuln-hunter` agent's job harder. Follow the existing pattern exactly.

## Adding a new bundled subagent

1. Write `skills/gebug-work/agents/<name>.md` with frontmatter:
   ```yaml
   ---
   name: <name>
   description: When this agent runs, what it produces.
   tools: Read, Grep, Glob, Bash, ...
   ---
   ```
2. Reference it from `skills/gebug-work/references/work-pipeline.md`
   in the phase that spawns it.
3. Document its inputs in the briefing section of its `.md` file.
4. Update the "Bundled agents" section of
   `skills/gebug-work/README.md`.

## Changing the output layout

The output layout under `<target-repo>/docs/gebug-audit/` is
load-bearing. If you change it, update ALL of these in the same PR:

- `skills/gebug-brainstorm/SKILL.md` (output layout section)
- `skills/gebug-brainstorm/references/brainstorm-pipeline.md`
  (PHASE 8 file paths)
- `skills/gebug-work/SKILL.md` (output layout section)
- `skills/gebug-work/references/work-pipeline.md` (Conventions
  + PHASE 7, 8, 9, 10 file paths)
- `skills/gebug-work/agents/vuln-hunter.md` (paths referenced in
  briefing)
- `skills/gebug-work/agents/exploit-writer.md` (PoC + reproduce.sh
  paths)
- `skills/gebug-brainstorm/README.md` (output section)
- `skills/gebug-work/README.md` (output section)
- Top-level `README.md` (output layout section)

A partial change to the layout will produce skills that write files in
inconsistent locations.

## Local development loop

```bash
git clone git@github.com:<your-fork>/gebug-audit.git
cd gebug-audit
./install.sh
# Restart Claude Code so the skills get reloaded.
```

`install.sh` symlinks `skills/*` into `~/.claude/skills/`, so any edit
you make in your clone is picked up by Claude Code on the next session.
There is no separate build step.

To test a change end-to-end:

1. Pick a small open-source EVM protocol or a deliberately vulnerable
   target (Damn Vulnerable DeFi).
2. Run `/gebug-brainstorm` from inside that project.
3. Run `/gebug-work`.
4. Compare the output to what you expected. File an issue or open a PR
   with the delta.

## Pre-commit checks

Before pushing, run:

```bash
# 1. No em dashes anywhere.
! grep -rl '-' skills/ README.md CLAUDE.md CONTRIBUTING.md

# 2. SKILL.md frontmatter valid.
for f in skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' || echo "BAD FRONTMATTER: $f"
done

# 3. Every attack-vector doc has a Reachability check section.
for f in skills/gebug-work/references/attack-vectors/*.md; do
  grep -q '^## Reachability check' "$f" || echo "MISSING REACHABILITY CHECK: $f"
done

# 4. No non-English prose slipped in. Edit the WORDLIST locally to match
#    whatever language the previous author was likely typing in.
WORDLIST='\b(yan'g'|tida'k'|denga'n'|untu'k')\b'
! grep -rEn "$WORDLIST" skills/ README.md CLAUDE.md
```

## Pull request etiquette

- One concern per PR. A new attack-vector doc + a pipeline change + a
  README rewrite belong in three PRs, not one.
- Title format: short imperative. `Add perp.md attack-vector doc` not
  `Added some stuff for perps`.
- Description: what the change is, why it is needed, what was tested.
  If you tested against a real protocol, name it.
- Include a "Backwards compatibility" line if you changed the output
  layout, the SKILL.md trigger criteria, or any pipeline phase numbering.

## Filing an issue

Two kinds of issues are most useful:

1. **Missed bug in a real audit.** Describe the protocol, what the bug
   was, why `/gebug-work` missed it, and what change would have caught
   it. Real-world misses are the highest-signal feedback.
2. **Pipeline failure.** A phase that crashed, a Slither command that
   does not work on a fresh install, a vuln-hunter agent that returned
   garbage. Include the command, the output, and the environment
   (Foundry version, Slither version, OS).

Feature requests are welcome but lower priority than missed bugs and
pipeline failures.

## Safety policy is non-negotiable

The skills will refuse to broadcast transactions, refuse to use real
private keys, and refuse to run `cast send` / `forge create` /
`forge script --broadcast`. PRs that loosen this policy will be
rejected on sight. If you have a legitimate use case for any of those
commands (e.g., a deployment helper that lives OUTSIDE the audit
pipeline), build it as a sibling tool, not as part of `/gebug-work`.

## Code of conduct

Be civil. Disagreement is fine. Personal attacks, harassment, or
discrimination are not. Maintainers reserve the right to remove
comments or block contributors that violate this.

## License

By contributing, you agree that your contributions will be licensed
under the same [MIT License](LICENSE) that covers the project.
