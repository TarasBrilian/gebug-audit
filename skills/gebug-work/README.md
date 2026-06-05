# gebug-work

Phase 2 of the **gebug** two-phase Web3 audit workflow for
[Claude Code](https://claude.com/claude-code).

`/gebug-work` consumes the four definition files written by
`/gebug-brainstorm` and runs the full audit pipeline: static analysis,
fuzzing, parallel `vuln-hunter` agents, cross-contract analysis,
validity gate, Foundry fork PoCs, per-finding files, and the headline
report.

EVM-only. Solidity / Vyper on Ethereum, BSC, Polygon, Arbitrum, Base,
Optimism, Avalanche, or any EVM-compatible chain.

## What it does

- Verifies the four definition files from `/gebug-brainstorm` exist
  and refuses to start if any is missing.
- Re-confirms the safety preflight with the user when stale.
- Runs Slither (full detector suite + optional Aderyn).
- Runs mandatory fuzzing / invariants / Halmos symbolic on
  math-bearing paths.
- Spawns parallel `vuln-hunter` agents per subsystem (with a token
  budget gate when > 10 agents would be spawned).
- Runs cross-contract analysis (trust boundaries, shared accounting,
  upgrade-path race, MEV ordering, reentrancy across contracts).
- Applies the rejection-only-with-proof validity gate (doubts are not
  rejections).
- Spawns `exploit-writer` agents for surviving candidates, builds
  Foundry fork PoCs.
- Writes per-finding files (one finding per file under `finding/`).
- Writes per-finding PoC bundles under `report/POC/<slug>/` with an
  executable `reproduce.sh`.
- Writes the headline exploit at `exploit/Exploit.sol` and the
  headline report at `report/REPORT.md`.
- Runs a final anti-hallucination check (every cite, every file, no em
  dashes).

## What it does NOT do

- Does not scope or interview (`/gebug-brainstorm`'s job).
- Does not write findings without a passing PoC for MEDIUM+ (downgrade
  rule).
- Does not auto-submit findings.
- Does not broadcast transactions. Mainnet (or matching testnet) fork
  only.
- Does not run `cast send`, `forge create`,
  `forge script --broadcast`, or anything using a real private key.

## Supported targets

- Languages: Solidity, Vyper.
- Chains: Ethereum, BSC, Polygon, Arbitrum, Base, Optimism, Avalanche,
  and any other EVM-compatible chain.
- Repos using Foundry, Hardhat, or any EVM toolchain.

## Safety policy

- Only audits contracts explicitly named in `DEFINITION.md` and
  `SAFETY_PREFLIGHT.md`.
- Exploit validation only on a local fork via `vm.createSelectFork`.
- Treats target repositories as untrusted. Reviews `foundry.toml`,
  package scripts, Makefiles, FFI settings, remappings, deployment
  scripts, and shell scripts before executing them. Tests with FFI,
  broad filesystem writes, private keys, or deployment hooks require
  user approval.
- Never auto-submits findings. Drafts are presented for human review.

## Installation

This skill ships as part of the [gebug-audit](
https://github.com/TarasBrilian/gebug-audit) monorepo, together with
its partner skill `gebug-brainstorm`.

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

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, `anvil`)
- [Slither](https://github.com/crytic/slither)
- Optional but recommended: [Aderyn](https://github.com/Cyfrin/aderyn),
  [Echidna](https://github.com/crytic/echidna),
  [Halmos](https://github.com/a16z/halmos),
  [Medusa](https://github.com/crytic/medusa).

### Environment

- `PENTEST_HOME` (optional): scratch space for intermediate Slither
  output and fuzzing harnesses-in-progress.

## Usage

After `/gebug-brainstorm` finishes:

```
/gebug-work
```

The skill will:

1. Verify the four files in
   `<target-repo>/docs/gebug-audit/definition/` exist.
2. Re-confirm the safety preflight if stale.
3. Run the full pipeline end to end.
4. Stop and ask for approval before spawning more than 10
   `vuln-hunter` agents.
5. Produce per-finding files, per-finding PoCs, the headline exploit,
   and the final report.

If the four definition files are missing, the skill refuses to start
and tells you to run `/gebug-brainstorm` first.

## Output

```
<target-repo>/docs/gebug-audit/
├── definition/                          INPUT (from /gebug-brainstorm)
│   ├── DEFINITION.md
│   ├── CANDIDATES.md
│   ├── SAFETY_PREFLIGHT.md
│   └── BOUNTY_MATRIX.md
│
├── finding/                             OUTPUT (one file per finding)
│   ├── CRITICAL_<short>.md
│   ├── HIGH_<short>.md
│   ├── MEDIUM_<short>.md
│   ├── LOW_<short>.md
│   └── INFO_<short>.md
│
├── fuzzing/
│   ├── FUZZING.md
│   ├── *_Invariant.t.sol
│   ├── echidna.yaml
│   └── halmos_*.out
│
├── exploit/
│   └── Exploit.sol                      headline exploit
│
└── report/
    ├── REPORT.md
    ├── INVARIANTS.md
    ├── slither-summary.txt
    ├── slither-high-impact.txt
    └── POC/
        └── <finding-slug>/
            ├── Exploit.t.sol
            └── reproduce.sh
```

`reproduce.sh` is executable and runs the per-finding PoC via
`forge test --match-path`.

## How the pipeline works

Loads `references/work-pipeline.md` and walks every phase:

- **PHASE -1**: Full toolchain pre-flight.
- **PHASE 0**: Re-validate definition inputs.
- **PHASE 1**: Static analysis (Slither + optional Aderyn).
- **PHASE 2**: Fuzzing / invariants / Halmos (mandatory for
  math-bearing paths).
- **PHASE 3**: Reconnaissance with adversarial eyes.
- **PHASE 4**: Parallel `vuln-hunter` agents (with token-budget gate).
- **PHASE 5**: Cross-contract analysis.
- **PHASE 6**: Compile candidates (rejection-only-with-proof).
- **PHASE 7**: PoC development via `exploit-writer` agents.
- **PHASE 8**: Write per-finding files.
- **PHASE 9**: Write headline report.
- **PHASE 10**: Final anti-hallucination check.
- **PHASE 11**: Closing summary.

## Findings

Each finding lives in its own file under `finding/{SEVERITY}_<short>.md`.
Each finding includes:

- Bounty platform submission info (target URL, severity, bug
  classification).
- Calibration table (`severity_post_gate`, `confidence_0_100`,
  `single_strongest_reject`, `smallest_falsifier`, `gate_failures`,
  `poc_status`, `poc_path`).
- Summary, detail, impact, step-by-step exploitation.
- Proof of concept (link to `report/POC/<slug>/Exploit.t.sol` and
  `reproduce.sh`, plus the actual forge output).
- Recommended fix.
- Anticipated triager rejection reasons + counter-arguments.
- References.

If `confidence_0_100 < 60` or any validity gate fails, the finding is
NOT flagged as a recommended submission.

## Honest negative result

A "no submittable findings" report is only acceptable after the
pipeline ran completely, including:

- Loading every attack-vector doc named in `DEFINITION.md`.
- Running Foundry invariant tests OR Echidna OR Halmos on math-bearing
  paths.
- Spawning multiple `vuln-hunter` agents for any contract > 300 LoC.
- Attempting at least one Foundry PoC per `recommended_for_poc = yes`
  candidate.

Otherwise the report is marked INCOMPLETE.

## Focused modes

If you do not need the full pipeline (after `/gebug-brainstorm`
finished):

- `audit-only <subsystem>` - skip PoC; cap severity at HIGH pending PoC.
- `exploit-only <candidate-id>` - run only Phase 7 for one candidate.
- `fork-test <slug>` - re-run an existing PoC at a different block.
- `triage <candidate-id>` - apply the validity gate to one candidate.
- `report-only` - regenerate the report from existing PoCs.

## Bundled agents

- `agents/vuln-hunter.md` - adversarial vulnerability hunter, invoked
  per subsystem in Phase 4.
- `agents/exploit-writer.md` - Foundry fork PoC writer, invoked per
  surviving candidate in Phase 7.

These are bundled with the skill (not loaded from
`~/.claude/agents/`) so the skill is self-contained.

## Attack-vector references

- `references/attack-vectors/amm.md` - AMM (Uniswap v2/v3/v4, Curve,
  Balancer, hooks).
- `references/attack-vectors/bridge.md` - Cross-chain bridges
  (LayerZero, Wormhole, CCIP, Axelar, Hyperlane).
- `references/attack-vectors/governance.md` - On-chain governance
  (Compound Bravo forks, OZ Governor, Snapshot / SafeSnap, timelocks).
- `references/attack-vectors/lending.md` - Lending markets (Aave,
  Compound, Morpho, HyperLend).
- `references/attack-vectors/lst-lrt.md` - LST / LRT mechanics
  (mint, burn, queue, rate provider).
- `references/attack-vectors/oracle-integration.md` - Chainlink, Pyth,
  Redstone, Uniswap TWAP, LP fair-value.
- `references/attack-vectors/restaking.md` - EigenLayer, Symbiotic,
  Karak, AVS opt-in, slashing.

Which docs apply is decided in `/gebug-brainstorm` Phase 6 and recorded
in `DEFINITION.md`.

## Files

- `SKILL.md` - skill manifest and operating doctrine.
- `references/work-pipeline.md` - phase-by-phase execution.
- `references/attack-vectors/*.md` - domain attack catalogs.
- `agents/vuln-hunter.md` - bundled subagent.
- `agents/exploit-writer.md` - bundled subagent.
- `README.md` - this file.

## License

MIT
