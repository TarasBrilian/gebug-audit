# CLAUDE.md

This file is read by [Claude Code](https://claude.com/claude-code) when
working **inside the `gebug-audit` repository itself** (contributing
to the skills, not running them on a target).

If you are an end user installing `gebug-audit` and running it against
a smart contract, read [README.md](README.md) instead.

## What this repo is

A monorepo containing two Claude Code skills:

- `skills/gebug-brainstorm/` - scopes a Web3 audit, writes the
  definition files.
- `skills/gebug-work/` - executes the audit, produces findings + report.

Plus an `install.sh` that symlinks `skills/*` into `~/.claude/skills/`.

## Project conventions

When editing files in this repo:

- **English only.** No Indonesian (or other natural-language)
  comments, prose, or docstrings. Even where the author thinks in
  another language, the committed file must be English.
- **No em dashes (`-`)** in any generated audit output OR in any skill
  source file. Use a regular hyphen (`-`) or rewrite. The skills enforce
  this on their output via a `grep '-'` check at the end of each phase;
  the source files match the same rule for consistency.
- **Cite file:line** whenever a doc references contract source. If you
  cannot cite, do not assert.
- **No backwards-compatibility shims** if the change is internal to
  the skill repo. Skills do not have an external API to preserve.
- **Skills are EVM-only.** Do not add non-EVM (Solana, Move,
  CosmWasm) content to the bundled checklists or attack-vector docs.
  If the user needs non-EVM, they should use a different skill.

## Where things live

```
skills/<skill-name>/
├── SKILL.md                 trigger + safety + doctrine (loaded first by Claude Code)
├── README.md                end-user install + usage
├── agents/                  bundled subagent definitions (gebug-work only)
└── references/              loaded on demand from SKILL.md
    ├── *-pipeline.md        phase-by-phase execution authority
    └── attack-vectors/      EVM domain catalogs (gebug-work only)
```

### SKILL.md vs references

`SKILL.md` is loaded into Claude Code's context whenever the skill is
triggered. Keep it focused on:

- Skill trigger criteria.
- Safety policy and forbidden actions.
- Doctrine (adversarial stance, validity rules, sharp-edge rules).
- A high-level summary of phases.
- Output layout.
- A pointer to the pipeline reference.

`references/*-pipeline.md` is the **single source of truth** for
execution. It contains the bash commands, file templates, and phase
ordering. Loaded on demand.

**Never duplicate execution detail between SKILL.md and the pipeline
reference.** Past mistakes in similar skills came from having two
authoritative documents that drifted out of sync.

### attack-vectors/

Each doc follows the same pattern:

1. Opening paragraph: when this doc applies, which target types.
2. "Reachability check" section: 4 - 5 questions every candidate must
   answer.
3. Numbered items (`A1`, `A2`, etc.) per attack class, each with:
   - Mechanism description.
   - `**Probe**:` line(s) - concrete things to check.
   - References to similar bugs / postmortems where applicable.
4. Closing "Common bugs (observed historically)" table.

When adding a new doc, follow this structure exactly. Inconsistent
structure across vector docs makes the vuln-hunter agent's job harder.

## Editing SKILL.md frontmatter

Top of every SKILL.md:

```yaml
---
name: <skill-name>
description: >-
  When to use, what it takes, what it produces.
  Be specific about trigger phrases.
---
```

The `description` is what Claude Code uses to decide whether to invoke
the skill. Be descriptive about trigger phrases (`audit`, `pentest`,
`hunt vulnerabilities`, etc.) and the input/output contract.

## Adding a new attack-vector doc

1. Create `skills/gebug-work/references/attack-vectors/<topic>.md`
   following the existing structure.
2. Add a mapping line in two places:
   - `skills/gebug-brainstorm/references/brainstorm-pipeline.md`
     PHASE 6 (the target-type -> docs table).
   - `skills/gebug-work/agents/vuln-hunter.md` "Default mapping"
     section.
3. Add a row to the "Attack-vector coverage" table in the top-level
   `README.md`.

## Changing the output layout

If you change the layout under `<target-repo>/docs/gebug-audit/`,
update ALL of these in the same commit:

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

Yes, that is a lot. The layout is load-bearing. If you change one and
not the others, the skill will write files in inconsistent locations.

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

## Versioning

Skills are versioned implicitly via git commit. There is no
`version` field in SKILL.md. If you need a sharper version,
add a `# Changelog` section to the relevant `README.md`.

## Pre-commit checks

Run before pushing:

```bash
# 1. No em dashes
! grep -rl '-' skills/ README.md CLAUDE.md

# 2. SKILL.md frontmatter valid
for f in skills/*/SKILL.md; do
  head -1 "$f" | grep -q '^---$' || echo "BAD FRONTMATTER: $f"
done

# 3. Every attack-vector doc has a Reachability check section
for f in skills/gebug-work/references/attack-vectors/*.md; do
  grep -q '^## Reachability check' "$f" || echo "MISSING REACHABILITY CHECK: $f"
done
```

## Out of scope for this repo

- Building Web2 / API / mobile pentest skills (would not fit the EVM
  focus).
- Adding non-EVM smart-contract support (different toolchain, different
  doctrine; better as a sibling repo).
- Wrapping `cast send` / `forge create` / `forge script --broadcast` -
  the safety policy is explicit and non-negotiable.

## License

[MIT](LICENSE).
