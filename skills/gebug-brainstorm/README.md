# gebug-brainstorm

Phase 1 of the **gebug** two-phase Web3 audit workflow for
[Claude Code](https://claude.com/claude-code).

`/gebug-brainstorm` scopes the target through a structured interview,
acquires the source code, runs light reconnaissance, and writes four
artefacts the user can review before triggering the deep audit:

- `DEFINITION.md` - summary, scope, architecture, attack-vector docs
  to load.
- `CANDIDATES.md` - initial vulnerability candidates (post light
  recon) labeled `HYPOTHESIS_*` until `/gebug-work` falsifies or
  confirms them.
- `SAFETY_PREFLIGHT.md` - in-scope contracts, allowed and forbidden
  actions, output dir.
- `BOUNTY_MATRIX.md` - severity matrix copied verbatim from the
  bounty page.

After `/gebug-brainstorm` finishes, the user runs `/gebug-work` to
execute the full audit.

EVM-only. Solidity / Vyper on Ethereum, BSC, Polygon, Arbitrum, Base,
Optimism, Avalanche, or any EVM-compatible chain.

## What it does

- Conducts a structured interview via `AskUserQuestion` (bounty
  platform, target type, chain, source location, in-scope contracts,
  severity matrix, prior audits, out-of-scope items).
- Writes a safety preflight and requires user confirmation before any
  active recon.
- Acquires source from GitHub, Etherscan-style verified source, a
  local path, or inline paste.
- Runs Slither human-summary for context.
- Maps the observed target type to the attack-vector docs
  `/gebug-work` will load.
- Generates initial vuln candidates from three angles:
  - Contract type → known attack classes.
  - Bounty Critical impact lines → reverse-engineer failure modes.
  - Slither high-impact human summary.
- Runs a final anti-hallucination check (every `file:line` cite, every
  named contract / function, no em dashes).
- Hands off to `/gebug-work`.

## What it does NOT do

- No findings.
- No full static analysis pass (that is `/gebug-work` Phase 1).
- No fuzzing.
- No PoC.
- No vuln-hunter agent spawning (that is `/gebug-work` Phase 4).
- No final report.

## Supported targets

- Languages: Solidity, Vyper.
- Chains: Ethereum, BSC, Polygon, Arbitrum, Base, Optimism, Avalanche,
  and any other EVM-compatible chain.
- Repos using Foundry, Hardhat, or any EVM toolchain.

## Safety policy

- Only scopes assets explicitly named by the user or named in a bug
  bounty page the user provided.
- A safety preflight is written before any active recon, listing
  in-scope contracts, chains, allowed and forbidden actions.
- Recon is read-only. Never executes live-chain transactions. Never
  runs `cast send`, `forge create`, `forge script --broadcast`, or
  any command using a real private key.
- Treats target repositories as untrusted. Reviews `foundry.toml`,
  package scripts, Makefiles, FFI settings, remappings, deployment
  scripts, and shell scripts before executing them.
- Never auto-runs `/gebug-work`. The user runs it.
- Never auto-submits findings.

## Installation

This skill ships as part of the [gebug-audit](
https://github.com/TarasBrilian/gebug-audit) monorepo, together with
its partner skill `gebug-work`.

```bash
git clone git@github.com:TarasBrilian/gebug-audit.git
cd gebug-audit
./install.sh
```

`install.sh` symlinks `skills/gebug-brainstorm/` and
`skills/gebug-work/` into `~/.claude/skills/`, so `git pull` updates
propagate automatically.

Restart Claude Code (or start a new session) so the skill index picks
up the new skills.

See the [top-level README](../../README.md) for manual and
project-scoped install options.

### Required tooling

For recon:

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`)
- [Slither](https://github.com/crytic/slither)
- `git`

For the deep audit (`/gebug-work`):

- `anvil`, optional [Aderyn](https://github.com/Cyfrin/aderyn),
  [Echidna](https://github.com/crytic/echidna),
  [Halmos](https://github.com/a16z/halmos),
  [Medusa](https://github.com/crytic/medusa).

### Environment

- `PENTEST_HOME` (optional): root pentest workspace for clones and
  scratch. If unset, `pwd` is used.

## Usage

Inside Claude Code, type:

```
/gebug-brainstorm
```

then describe what you want to audit. Examples:

```
/gebug-brainstorm audit this protocol: https://cantina.xyz/competitions/<id>
```

```
/gebug-brainstorm scope the contracts at github.com/<org>/<repo>
```

```
/gebug-brainstorm I want to hunt vulnerabilities in 0xAbCd... on Ethereum
```

The skill will then ask 1 - 3 batches of structured questions, fetch
the source, do light recon, and produce the four files below before
telling you to run `/gebug-work`.

## Output

The brainstorm writes into the TARGET REPO's `docs/` directory:

```
<target-repo>/docs/gebug-audit/definition/
├── DEFINITION.md
├── CANDIDATES.md
├── SAFETY_PREFLIGHT.md
└── BOUNTY_MATRIX.md
```

`$PENTEST_HOME` may be used as scratch space during the run, but the
four files above must end up in the target repo before declaring the
brainstorm complete.

## How the pipeline works

Loads `references/brainstorm-pipeline.md` and walks every phase:

- **PHASE -1**: Tool pre-flight.
- **PHASE 0**: Skip already brainstormed (compare commit + scope hash).
- **PHASE 1**: Structured interview via `AskUserQuestion`.
- **PHASE 2**: Safety preflight + user confirmation.
- **PHASE 3**: Acquire source.
- **PHASE 4**: Light recon (proxy, roles, integrations, on-chain
  state).
- **PHASE 5**: Quick Slither pass.
- **PHASE 6**: Map target type to attack-vector docs for `/gebug-work`.
- **PHASE 7**: Generate initial candidates.
- **PHASE 8**: Write the four artefacts.
- **PHASE 9**: Final anti-hallucination check.
- **PHASE 10**: Handoff message.

Every hypothesis cites the exact `file:line` it depends on. Anything
not backed by a passing PoC or symbol-by-symbol math is labeled
`HYPOTHESIS_<name>` with the cheapest experiment that would falsify
it. The PoC and the falsification are `/gebug-work`'s job.

## Files

- `SKILL.md` - skill manifest and operating doctrine loaded by Claude
  Code.
- `references/brainstorm-pipeline.md` - phase-by-phase execution.
- `README.md` - this file.

## License

MIT
