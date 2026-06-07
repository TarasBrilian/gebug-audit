<p align="center">
  <img src="assets/logo.png" alt="gebug" width="320" />
</p>

<h1 align="center">gebug-audit</h1>

<p align="center">
  <em>Two-phase Web3 smart-contract audit workflow for
  <a href="https://claude.com/claude-code">Claude Code</a>.<br/>
  Brainstorm the scope, then run the audit. EVM-only.</em>
</p>

---

`gebug-audit` is a pair of Claude Code skills that turn a bug bounty
page, a GitHub repo, or a deployed contract address into:

- A reviewed scope document (`DEFINITION.md`),
- A grounded list of initial vuln candidates (`CANDIDATES.md`),
- A safety preflight signed off by the user (`SAFETY_PREFLIGHT.md`),
- A bounty severity matrix copied verbatim (`BOUNTY_MATRIX.md`),
- Per-finding write-ups with passing Foundry fork PoCs,
- A headline audit report and per-finding reproducible exploits.

The two skills are:

| Skill | When you run it | What it does |
|-------|-----------------|--------------|
| `/gebug-brainstorm` | First | Interview, source acquisition, light recon, hypothesis generation. Writes the four definition files. |
| `/gebug-work` | After brainstorm | Static analysis, fuzzing, parallel vuln-hunter agents, validity gate, Foundry fork PoCs, per-finding files, headline report. |

## Why two skills

The split mirrors how an experienced auditor works:

- **Phase 1 (brainstorm)** is cheap, conversational, and reviewable. The
  user can correct the scope before any heavy lifting begins.
- **Phase 2 (work)** is expensive (parallel agents, fuzzing, PoCs). It
  refuses to start until the four definition files exist, so wasted
  agent runs are minimized.

It also forces a human-in-the-loop check at the most important moment:
right after scoping, before any active analysis runs.

## Features

### Strong doctrine carried into every audit

- **Adversarial stance**: auditor + attacker, not code explainer.
- **Validity doctrine**: every hypothesis cites `file:line`; nothing
  ships without a passing PoC or symbol-by-symbol math.
- **Rejection-only-with-proof rule**: doubts are not rejections. The
  PoC is the falsifier.
- **Sharp-edge rules**: treat "safe", "bounded", "not manipulable" as
  hypotheses, not conclusions.
- **Anti-sycophancy**: do not adopt the user's hunch or prior reports
  without re-deriving from code.
- **Honest negative result**: "no findings" is only acceptable after
  the pipeline ran completely (every attack-vector loaded, fuzzing
  run, PoC attempted per candidate).
- **Final anti-hallucination check**: every cite, every contract /
  function / address grep-verified before the report ships.

### Pipeline guard-rails

- **Scenario A vs B auto-detect**: the brainstorm phase inspects `cwd`
  for `foundry.toml`+`src/`+`test/`, Hardhat config, or a
  `package.json` with Foundry / Hardhat deps. External-repo audits
  land in `cwd/<repo-name>/docs/gebug-audit/`; self-audits land in
  `cwd/gebug-audit/`. The choice is announced and confirmed before any
  active recon.
- **Mandatory fuzzing exit gate**: `/gebug-work` refuses to enter
  Phase 3 unless `fuzzing/FUZZING.md` exists with evidence. A silent
  Phase 2 skip is the most common way a real bug (broken invariant,
  Halmos counterexample, fuzzing seed crash) escapes the audit.
- **Phase 6.5 skeptical-triager**: an independent realism filter
  applies the Economic and Defender falsifiers to every MEDIUM+
  candidate, returning AFFIRM / DOWNGRADE / REJECT with quantified
  citation. Counters the vuln-hunter's built-in surfacing bias
  without sliding into hand-wavy dismissal.
- **Token-budget gate at Phase 4**: when the in-scope LoC would spawn
  more than 10 `vuln-hunter` agents, the orchestrator prints an
  estimated output-token cost and refuses to proceed without user
  approval.
- **Diff-focused mode**: opt-in pipeline for repeat audits against a
  moved `source_commit`. Re-runs Phase 4 only over the call-graph
  blast radius of changed files, records previously-cleared SHAs so
  tampering is detectable, and tags the report with the old + new
  commits.

### Safety policy

- Only audits assets explicitly in `SAFETY_PREFLIGHT.md`.
- Exploit validation runs only on a local fork via
  `vm.createSelectFork`.
- Never broadcasts transactions. Never runs `cast send`,
  `forge create`, `forge script --broadcast`, or any command using a
  real private key.
- Treats target repositories as untrusted. Reviews `foundry.toml`,
  scripts, FFI settings, and remappings before executing them.
- Never auto-submits findings. The user reviews every draft.
- Never uses em dashes in generated files (consistent formatting).

### Attack-vector coverage (out of the box)

| Doc | Covers |
|-----|--------|
| `amm.md` | Uniswap v2/v3/v4 hooks, Curve, Balancer, JIT, k-invariant, donation, read-only reentrancy, LP fair-value |
| `bridge.md` | LayerZero, Wormhole, CCIP, Axelar, Hyperlane; spoof, replay, mint without proof, ZK proof verification |
| `governance.md` | Compound Bravo forks, OZ Governor, Snapshot / SafeSnap; flash-loan votes, timelock bypass, quorum manipulation |
| `lending.md` | Aave / Compound / Morpho / HyperLend; liquidation, IRM, LTV, oracle in lending, isolation / e-mode |
| `lst-lrt.md` | LST / LRT mechanics; mint, burn, withdrawal queue, rate provider, conversion-rate manipulation |
| `oracle-integration.md` | Chainlink, Pyth, Redstone, Uniswap TWAP, sequencer-uptime feed, LP fair-value |
| `restaking.md` | EigenLayer M2-Pectra, Symbiotic, Karak; pubkey front-run, AVS opt-in, slashing math |

### Output layout

The skill auto-detects the audit scenario at invocation time and routes
output accordingly:

- **Scenario A** (external repo, no Foundry/Hardhat markers in `cwd`):
  audit tree lives at `cwd/<repo-name>/docs/gebug-audit/` inside the
  cloned source.
- **Scenario B** (self-audit, `cwd` is itself a Foundry or Hardhat
  project): audit tree lives at `cwd/gebug-audit/` next to the user's
  `src/` and `test/`. No clone.

The subtree is identical in both cases:

```
<AUDIT_DIR>/                             (resolved per Scenario A or B)
├── definition/                          OUTPUT of /gebug-brainstorm
│   ├── DEFINITION.md
│   ├── CANDIDATES.md
│   ├── SAFETY_PREFLIGHT.md
│   └── BOUNTY_MATRIX.md
│
├── _scratch/                            intermediate work (gitignored)
│
├── finding/                             OUTPUT of /gebug-work (1 file per finding)
│   ├── CRITICAL_<short>.md
│   ├── HIGH_<short>.md
│   └── ...
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
            └── reproduce.sh             (executable)
```

## Requirements

- [Claude Code](https://claude.com/claude-code).
- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, `anvil`).
- [Slither](https://github.com/crytic/slither)
  (`pip install slither-analyzer`).
- `git`.

Optional but recommended:

- [Aderyn](https://github.com/Cyfrin/aderyn)
  (`cargo install aderyn`).
- [Echidna](https://github.com/crytic/echidna).
- [Halmos](https://github.com/a16z/halmos) (`pipx install halmos`).
- [Medusa](https://github.com/crytic/medusa).

## Install

### Option 1: install script (recommended)

```bash
git clone git@github.com:TarasBrilian/gebug-audit.git
cd gebug-audit
./install.sh
```

The installer symlinks `skills/gebug-brainstorm/` and
`skills/gebug-work/` into `~/.claude/skills/` so updates via `git pull`
propagate automatically.

Restart Claude Code (or start a new session) after install.

### Option 2: manual copy

```bash
git clone git@github.com:TarasBrilian/gebug-audit.git
cp -R gebug-audit/skills/gebug-brainstorm ~/.claude/skills/
cp -R gebug-audit/skills/gebug-work       ~/.claude/skills/
```

### Option 3: project-scoped install

If you only want these skills available in one project:

```bash
git clone git@github.com:TarasBrilian/gebug-audit.git
mkdir -p .claude/skills
ln -s "$PWD/gebug-audit/skills/gebug-brainstorm" .claude/skills/gebug-brainstorm
ln -s "$PWD/gebug-audit/skills/gebug-work"       .claude/skills/gebug-work
```

### Uninstall

```bash
cd gebug-audit
./uninstall.sh
```

## Usage

Inside Claude Code:

```
/gebug-brainstorm
```

then describe the target. Examples:

```
/gebug-brainstorm audit this bounty: https://cantina.xyz/competitions/<id>
```

```
/gebug-brainstorm scope contracts at github.com/<org>/<repo>
```

```
/gebug-brainstorm I want to hunt vulnerabilities in 0xAbCd... on Ethereum
```

The skill asks 1 - 3 batches of structured questions, fetches source,
runs Slither for context, and writes the four definition files.

When it finishes, run:

```
/gebug-work
```

`/gebug-work` reads the definition files and runs the full audit:
static analysis, fuzzing, parallel `vuln-hunter` agents, cross-contract
analysis, the validity gate, Foundry fork PoCs, per-finding files, and
the headline report.

### Focused modes (after brainstorm)

| Mode | What it does |
|------|--------------|
| `audit-only <subsystem>` | Skip PoCs; cap severity at HIGH pending PoC. |
| `exploit-only <candidate-id>` | Run only Phase 7 for one candidate. |
| `fork-test <slug>` | Re-run an existing PoC at a different block. |
| `triage <candidate-id>` | Apply the validity gate to one candidate. |
| `report-only` | Regenerate the report from existing PoCs. |
| `diff-focused` | Repeat audit against a moved `source_commit`: re-runs only over the call-graph blast radius of changed files and tags the report with old + new commits. |

## Supported targets

- **Languages:** Solidity, Vyper.
- **Chains:** Ethereum, BSC, Polygon, Arbitrum, Base, Optimism,
  Avalanche, and any other EVM-compatible chain. Non-EVM (Solana,
  Move, CosmWasm) is intentionally out of scope; use a different
  skill for those.
- **Frameworks:** Foundry, Hardhat, or any EVM toolchain that produces
  standard Solidity / Vyper artifacts.
- **Bounty platforms:** Cantina, Immunefi, Code4rena, Sherlock, Hats,
  or private programs.

## How a typical audit looks

1. User pastes a Cantina bounty URL into Claude Code:
   `/gebug-brainstorm audit https://cantina.xyz/competitions/xyz`.
2. Skill detects Scenario A vs B from `cwd`, announces the resolved
   output directory, and asks the user to confirm.
3. Skill asks: bounty platform, target type, chain, source location.
4. Skill asks: in-scope contracts, out-of-scope, severity matrix,
   prior audits.
5. Skill writes `SAFETY_PREFLIGHT.md` and the user confirms.
6. Skill clones the repo (Scenario A) or reuses `cwd` (Scenario B),
   runs Slither, generates initial candidates.
7. Skill writes `DEFINITION.md`, `CANDIDATES.md`, `BOUNTY_MATRIX.md`.
8. User reviews; if anything is off, user corrects and reruns the
   relevant phase.
9. User runs `/gebug-work`.
10. Skill verifies the four files exist, runs the full pipeline, asks
    for approval before spawning more than 10 `vuln-hunter` agents.
    Phase 2 refuses to advance without `fuzzing/FUZZING.md` evidence.
11. Phase 6.5 runs the skeptical-triager over every MEDIUM+ candidate
    and records AFFIRM / DOWNGRADE / REJECT per candidate.
12. Skill produces per-finding files, per-finding PoCs (each with a
    runnable `reproduce.sh`), a headline exploit, and the final
    `REPORT.md`.
13. User reviews; nothing is auto-submitted.

## Project structure

```
gebug-audit/
├── README.md                       this file
├── CLAUDE.md                       instructions for Claude Code in this repo
├── CONTRIBUTING.md
├── LICENSE                         MIT
├── install.sh                      symlink installer
├── uninstall.sh
├── assets/
│   └── logo.png
├── scripts/
│   └── check-layout-sync.sh        pre-commit guard against output-tree drift
├── tests/
│   └── fixtures/
│       └── vulnerable-vault/       manual regression target (see its README)
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
        │   ├── vuln-hunter.md      spawned per subsystem in Phase 4
        │   ├── skeptical-triager.md spawned in Phase 6.5
        │   └── exploit-writer.md   spawned per surviving candidate in Phase 7
        └── references/
            ├── work-pipeline.md
            ├── finding-template.md per-finding file template (loaded in Phase 8)
            └── attack-vectors/
                ├── amm.md
                ├── bridge.md
                ├── governance.md
                ├── lending.md
                ├── lst-lrt.md
                ├── oracle-integration.md
                └── restaking.md
```

## Contributing

Contributions welcome, especially:

- New attack-vector docs (perp, stablecoin, intent-protocol,
  account-abstraction, etc.).
- Improvements to the validity gate or severity calibration (Phase 6 /
  Phase 6.5 skeptical-triager).
- Better focused-mode flows on top of the existing `audit-only`,
  `exploit-only`, `fork-test`, `triage`, `report-only`, and
  `diff-focused` modes.
- Bug reports from real audits where the pipeline missed something.

When adding an attack-vector doc, follow the existing pattern: numbered
items (e.g. `A1`, `A2`), each with `**Probe**:` lines, a "Reachability
check" section, and a "Common bugs" historical table. Cite file:line
where possible.

## License

[MIT](LICENSE).

## Acknowledgements

- [Anthropic Claude Code](https://claude.com/claude-code) for the skill
  + subagent system.
- [Trail of Bits / Crytic](https://github.com/crytic) for Slither,
  Echidna, and Medusa.
- [Foundry](https://book.getfoundry.sh/) for the fork-test infrastructure
  this skill depends on.
- The Web3 security research community whose published exploits and
  postmortems shaped the attack-vector docs.
