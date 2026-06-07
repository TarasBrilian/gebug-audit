---
name: gebug-work
description: >-
  Phase 2 of the gebug Web3 audit workflow. Use when the user types
  /gebug-work, or asks to execute / continue / finish / run / ship a gebug
  audit, or asks to audit / pentest / hunt vulnerabilities / build PoCs /
  produce a bounty report against a target that has already gone through
  /gebug-brainstorm. Reads docs/gebug-audit/definition/{DEFINITION,CANDIDATES,
  SAFETY_PREFLIGHT,BOUNTY_MATRIX}.md, runs static analysis, fuzzing,
  parallel vuln-hunter agents, applies the validity gate, builds Foundry
  fork PoCs, and writes per-finding files plus the headline report. EVM-only.
---

# gebug-work

Phase 2 of the two-phase **gebug** Web3 audit workflow.

This skill assumes `/gebug-brainstorm` has already run and produced the
four definition files. If they are missing, refuse to start and tell the
user to run `/gebug-brainstorm` first.

EVM-only. Solidity / Vyper on Ethereum, BSC, Polygon, Arbitrum, Base,
Optimism, Avalanche, or any EVM-compatible chain.

## Pipeline Reference

For execution detail, load and follow:

- `references/work-pipeline.md` (relative to this skill folder).

That file is authoritative for phase-by-phase execution. This file is the
trigger, the safety policy, and the operating doctrine.

Attack-vector docs to load are listed in
`<target-repo>/docs/gebug-audit/definition/DEFINITION.md`. Load them at
the start of Phase 4. The candidate-by-candidate exploration uses
spawned `vuln-hunter` agents (see `agents/vuln-hunter.md`).

## Authorization And Ethics

- Only test assets explicitly named in `definition/SAFETY_PREFLIGHT.md`
  and `definition/DEFINITION.md`.
- Re-confirm the safety preflight with the user before starting if the
  current date is more than 7 days after the brainstorm date, or if the
  source commit has changed.
- Never pivot to out-of-scope contracts, related deployments, frontends,
  infrastructure, APIs, mobile apps, or user accounts.
- Never run DoS, volumetric attacks, spam, mass scanning, social
  engineering, or destructive payloads.
- Exploit validation runs ONLY on a local fork (`vm.createSelectFork`) or
  a private / local testnet.
- Never execute live-chain transactions or deployments during audit work.
- Never run `cast send`, `forge script --broadcast`, `forge create`, or
  any command that uses a real private key.
- Treat target repositories as untrusted. Review `foundry.toml`, package
  scripts, Makefiles, FFI settings, remappings, deployment scripts, and
  shell scripts before executing them. Do not run tests with FFI, broad
  filesystem writes, private keys, or deployment hooks until reviewed and
  the user approves.
- Never auto-submit findings. Present drafts to the user for review.
- Formatting: NEVER use an em dash in generated files or reports. Use a
  regular hyphen or rewrite.

## Adversarial Stance

Same two stances as `/gebug-brainstorm`:

- **Auditor**: every invariant is a claim to break, every access check is
  a boundary, every external call is a possible reentry point, every math
  operation is a precision / rounding / overflow / accounting lever.
- **Attacker**: assume unlimited capital, flash loans, MEV bundles,
  composition with any DeFi primitive. The goal is concrete profit,
  insolvency, griefing, privilege escalation, or DoS.

Not a code explainer. Not a style reviewer. Not a best-practices linter.
Style, naming, missing NatSpec, gas inefficiency, and defense-in-depth
notes are OUT unless they directly enable an exploit.

## Validity Doctrine

A candidate is invalid until it survives attempts to disprove it.

Before writing a finding:

1. Identify the intended behavior. If the mechanism is doing its
   documented or obvious job, it is not a bug.
2. Prove attacker reachability. The attacker must be able to trigger the
   path against an honest victim or protocol funds without trusted-role
   cooperation.
3. Name whose money or protocol property is harmed. A valid finding needs
   in-scope impact, not only a surprising internal state.
4. Quantify the exploit. Show attacker cost, capital, slippage, fees,
   gas, and extracted value at a pinned fork block.
5. If rejecting, prove the protection. If an oracle cap, TWAP, sanity
   bound, role check, state transition, or accounting rule blocks the
   attack, demonstrate it with code, math, or a counter-PoC.

Anti-sycophancy: do not accept the user's hunch, prior reports, prior
agent notes, or an existing write-up without independently deriving the
claim from code and behavior. "No valid findings" is acceptable IF the
pipeline ran completely (see Honest Negative Result below).

Grounding: every hypothesis cites the exact `file:line` it depends on. If
you cannot cite the code path, do not assert the behavior.

Hypothesis rule: anything not backed by a passing fork PoC or explicit
symbol-by-symbol math is labeled `HYPOTHESIS_<short_name>`. State the
cheapest experiment that would falsify it.

No invented APIs. No invented bytecode behavior.

## Sharp-Edge Rules

1. Treat "not manipulable", "not atomic", "bounded", and "safe" as
   hypotheses, not conclusions. Falsify on a fork before relying on them.
2. A manipulable input is not a finding by itself. The output must become
   exploitable after all dampeners, caps, TWAPs, min / max logic, and
   slippage constraints.
3. Reachability is mandatory. A latent defect is only a valid finding if
   an attacker-controlled path reaches it against an in-scope victim or
   protocol asset.
4. Distinguish privileged power from privilege escalation. A trusted role
   doing its intended job is normally out of scope. A public or unintended
   path to that power can be a bug.
5. Map every candidate to the bounty program's exact impact list in
   `BOUNTY_MATRIX.md` before spending PoC budget.
6. Counter-test loss and freezing claims. Show honest users are affected,
   the attacker can trigger the condition, and recovery is not available
   by design.

## Output Layout (single source of truth)

`<target-repo>` and `AUDIT_DIR` are resolved by Phase 0 based on the
scenario detected by `/gebug-brainstorm`:

- **Scenario A** (external audit): `AUDIT_DIR = $CWD/<repo-name>/docs/gebug-audit/`
- **Scenario B** (user's own project): `AUDIT_DIR = $CWD/gebug-audit/`

In both cases the subtree below is identical (relative to AUDIT_DIR):

```
$AUDIT_DIR/
├── definition/                          ← INPUT (from /gebug-brainstorm)
│   ├── DEFINITION.md
│   ├── CANDIDATES.md
│   ├── SAFETY_PREFLIGHT.md
│   └── BOUNTY_MATRIX.md
│
├── _scratch/                            ← intermediate work (gitignored)
│   ├── slither-*.txt
│   ├── vh-*.md                          vuln-hunter agent outputs
│   └── foundry-toml-patch.diff          Scenario B only
│
├── finding/                             ← OUTPUT (one file per finding)
│   ├── CRITICAL_<short>.md
│   ├── HIGH_<short>.md
│   ├── MEDIUM_<short>.md
│   ├── LOW_<short>.md
│   └── INFO_<short>.md
│
├── fuzzing/                             ← OUTPUT
│   ├── FUZZING.md                       summary of harnesses + results
│   ├── *_Invariant.t.sol                Foundry invariant harnesses
│   ├── echidna.yaml                     if used
│   └── halmos_*.out                     counter-examples
│
├── exploit/                             ← OUTPUT
│   └── Exploit.sol                      headline exploit (fork-based)
│
└── report/                              ← OUTPUT
    ├── REPORT.md                        the headline audit report
    ├── INVARIANTS.md                    protocol invariants enumerated
    ├── slither-summary.txt
    ├── slither-high-impact.txt
    └── POC/
        └── <finding-slug>/
            ├── Exploit.t.sol            Foundry test, self-contained
            └── reproduce.sh             runnable command
```

Mandatory rules:

- The `finding/` directory MUST exist even if there are zero findings.
- The `fuzzing/` directory MUST exist; place harnesses there even if all
  runs produced negative results.
- One finding equals one file under `finding/`. Never bundle multiple
  findings into one file.
- Every per-finding PoC lives at `report/POC/<finding-slug>/Exploit.t.sol`
  with a sibling `reproduce.sh` that runs it via
  `forge test --match-path ...`.
- `exploit/Exploit.sol` is the single "headline" exploit when the audit
  has a primary critical finding. If multiple Criticals exist, pick the
  highest-impact one for `exploit/`. All Criticals also have per-finding
  PoCs under `report/POC/`.
- Never mix multiple targets in one `gebug-audit/` directory.
- The skill auto-generates `$AUDIT_DIR/.gitignore` that skips `_scratch/`,
  `_preflight/`, `fout/`, `cache/`, `*.log`. In Scenario B this prevents
  intermediate audit work from polluting the user's git history.

`$PENTEST_HOME` is NOT used for audit output. It may be used for global
toolchain cache only (solc downloads, etc.).

## Pre-Check

Before starting:

0. **Resolve `<target-repo>` and `AUDIT_DIR` from cwd** by re-running the
   detection logic from `/gebug-brainstorm` Phase 0:
   - Marker F (foundry.toml + src/contracts + test/), Marker H (hardhat
     config + contracts/), Marker P (package.json with hardhat/foundry-rs
     dep). Any match -> Scenario B; otherwise -> Scenario A.
   - Scenario A: AUDIT_DIR candidates = `$CWD/<dirname>/docs/gebug-audit/`
     for each subdirectory of `$CWD` that contains a populated
     `docs/gebug-audit/definition/` from a prior `/gebug-brainstorm` run.
     If multiple match, ask the user which one to audit.
   - Scenario B: AUDIT_DIR = `$CWD/gebug-audit/`.
1. Confirm `$AUDIT_DIR/definition/` contains all four files
   (`DEFINITION.md`, `CANDIDATES.md`, `SAFETY_PREFLIGHT.md`,
   `BOUNTY_MATRIX.md`). If any is missing, refuse to start and tell the
   user to run `/gebug-brainstorm` first.
2. Read `DEFINITION.md` header. If `source_commit` does not match the
   current `git rev-parse HEAD`, ask the user whether to (a) rebrainstorm
   first, (b) run in diff-focused mode against changed files only, or
   (c) continue anyway.
3. Read `SAFETY_PREFLIGHT.md`. Re-confirm with the user if the audit date
   is more than 7 days old or the commit changed.
4. Read `CANDIDATES.md` to seed Phase 4. Every `HYPOTHESIS_*` candidate
   becomes one of the threads vuln-hunter agents must consider.
5. Read `BOUNTY_MATRIX.md`. Every finding must map to a specific line.
6. Load every attack-vector doc named in `DEFINITION.md` under
   "Attack-vector docs to load".

## Full Work Flow

Load `references/work-pipeline.md` and execute every phase. The
nomenclature below mirrors `work-pipeline.md` exactly so cross-references
between this file, the agent specs, and the pipeline never drift.

- **Phase -1**: Tool pre-flight (full toolchain: forge, cast, anvil,
  slither; optional aderyn, echidna, medusa, halmos).
- **Phase 0**: Re-validate the four `definition/` files and resolve
  `$AUDIT_DIR` per Scenario A vs B (re-running brainstorm's detection).
- **Phase 1**: Full static analysis. Slither with targeted detectors,
  optional aderyn pass. Outputs land in `report/slither-*.txt`.
- **Phase 2**: Fuzzing / invariants / Halmos symbolic on math-bearing
  paths. Outputs land in `fuzzing/`. Save `INVARIANTS.md` to `report/`.
- **Phase 3**: Re-read in-scope contracts with the adversarial stance;
  feed observations into the candidate pool. Read every external
  integration's source, not just the interface.
- **Phase 4**: Parallel deep analysis via spawned `vuln-hunter` agents.
  Subsystem split decided in the Phase 4 prelude. Each agent's output
  MUST satisfy the YAML schema in `agents/vuln-hunter.md` § Output
  format; the orchestrator validates required fields before Phase 6.5
  and re-spawns on schema failure.
- **Phase 5**: Cross-contract and economic analysis (trust boundaries,
  shared accounting, upgrade-path races, MEV / ordering,
  cross-contract reentrancy).
- **Phase 6**: Compile candidates. Apply rejection-only-with-proof rule
  (six falsifiers). Doubts are recorded, not used to reject. Write the
  working ledger to `$AUDIT_DIR/_candidates_working.md` using the
  template in `references/work-pipeline.md` § Phase 6.
- **Phase 6.5**: Skeptical-triager pass over every MEDIUM+ candidate.
  Returns AFFIRM / DOWNGRADE / REJECT citing Economic or Defender
  falsifiers. See `agents/skeptical-triager.md`.
- **Phase 7**: PoC development per surviving candidate via spawned
  `exploit-writer` agents. Mainnet fork only. PASS / FAIL / INVALID per
  candidate. Headline copy lands in `exploit/Exploit.sol`.
- **Phase 8**: Write per-finding files in `finding/`. Severity is
  RE-DERIVED from measured PoC outputs (see § Severity Calibration).
  Write per-finding `report/POC/<slug>/` bundles.
- **Phase 9**: Write `report/REPORT.md`, `report/INVARIANTS.md`,
  `fuzzing/FUZZING.md`.
- **Phase 10**: Final anti-hallucination check (citations grep, em-dash
  linter, PoC smoke-run, dramatic-phrasing linter, required-files
  presence).
- **Phase 11**: Closing summary to the user with absolute paths.

### Phase 4 agent count rules (do not under-allocate)

| Contract LoC | Min agents | Recommended allocation |
|---|---|---|
| ≤ 200 | 1 | single agent covers the whole file |
| 201 – 500 | 2 – 3 | split by subsystem (admin / user / view) |
| 501 – 1000 | 4 – 5 | split by subsystem |
| > 1000 | one agent per natural subsystem | each gets ≤ 300 LoC focus |

### Token-budget ceiling

If the total in-scope LoC indicates more than 10 vuln-hunter agents, STOP
and ask the user for confirmation before spawning. State the proposed
agent count and the subsystem split. The user can approve, narrow the
scope, or split the audit into multiple runs.

### Anti-dismissal rule

If all spawned vuln-hunter agents return "no candidates", the
orchestrator MUST re-spawn at least one agent with stricter framing
quoting the rejection-only-with-proof rule from `agents/vuln-hunter.md`.
Unanimous "no findings" is a signal the agent prompts are biased - fix
that, do not accept it as the audit result.

## Severity Calibration (apply AFTER PoC passes, not before)

Build a passing PoC FIRST, then apply this checklist. Pre-PoC, candidates
carry only a `severity_hypothesis`.

- **A. Recoverability**: can the admin INSTANTLY recover the lost funds
  via a single role-gated call already on-chain (sweep, collectFee,
  rescueTokens)? If yes → consider downgrade by one tier. Note that
  "upgrade + migrate" is NOT instant recovery - proxy upgrades take days
  to weeks via timelock and are observable, so they do NOT trigger
  downgrade unless the bounty explicitly classifies upgradable contracts
  as "temporarily blocked".
- **B. Normal operation likelihood**: triggered only with extreme params
  the frontend would never pass? Apply judgment; do NOT downgrade more
  than one tier - attackers bypass frontends.
- **C. External attack vector**: third party steals from OTHER users?
  Map to External Theft tier. Self-inflicted loss without external profit
  → consider Medium ceiling unless the bounty has a specific exclusion.
- **D. Off-chain mitigation**: frontend computes safe params? Documents
  friction, does not eliminate the bug. Reduce ONE notch maximum.
- **E. Bounty severity matrix**: read `BOUNTY_MATRIX.md` VERBATIM. Do not
  assume your generic interpretation matches the platform's. Match each
  finding to a specific line. If no line matches, do not invent one.
- **F. Triager perspective**: list every reason a triager might reject.
  Address each in the finding write-up. Do NOT auto-reject because "2+
  reasons exist" - provide the counter-argument and let the triager
  decide.

Conservative-bias correction (pre-PoC): write the finding, build the
PoC, apply the matrix AS WRITTEN by the bounty. The triager downgrades;
you do not pre-downgrade WITHOUT EVIDENCE.

Post-PoC recalibration (REQUIRED, see work-pipeline.md Phase 8): once
the PoC produces measured numbers, re-derive severity from those
numbers using the same matrix. The skeptical-triager's Phase 6.5
verdict is a CEILING - you may settle at or below it but never above.
"Re-derive from evidence" and "do not pre-downgrade" are complementary:
do not soften without evidence; do harden / adjust with evidence.

## Finding Template (per-finding file in `finding/`)

Template lives at `references/finding-template.md` (loaded on demand by
Phase 8). It includes the headline structure, the mandatory
`Calibration` block whose fields feed `REPORT.md` K3 (submittable
count), and the rationale for keeping a "Recommended Fix" section
inside an otherwise adversarial doctrine.

## Honest Negative Result

A negative result ("no submittable findings") is acceptable ONLY after
the pipeline ran completely, including:

- Loading every attack-vector doc named in `DEFINITION.md`.
- Running Foundry invariant tests OR Echidna OR Halmos on math-bearing
  paths.
- Spawning multiple `vuln-hunter` agents for any contract > 300 LoC.
- Attempting at least one Foundry PoC per `recommended_for_poc = yes`
  candidate from `CANDIDATES.md` plus everything vuln-hunter agents
  added.

A pipeline that returns "no findings" without these is INCOMPLETE.

When the pipeline genuinely produces nothing, `REPORT.md` must include:

- Top candidates considered and the rejection-with-proof citation per
  candidate (per the rejection-only-with-proof rule in
  `agents/vuln-hunter.md`).
- Areas examined, with subsystem granularity.
- Areas not examined and why.
- What evidence would flip a rejected candidate into a valid finding.
- Fuzzing harness contents and runs attempted (`fuzzing/FUZZING.md`).
- PoCs attempted (file path, run command, why they failed to reach a
  passing exploit).
- Whether all `file:line` citations were verified.

Do not pad the report with by-design behavior, vague best-practice notes,
or informational issues dressed up as vulnerabilities. Do not pre-dismiss
candidates that were not attempted as PoCs.

## Final Anti-Hallucination Check

Before sending the report:

1. Grep every `file:line` citation in every `finding/*.md` and confirm it
   points to the claimed code.
2. Grep every contract, function, event, modifier, interface, and address
   name used in the report.
3. Remove or downgrade every claim that cannot be tied to code, math, a
   fork test, or explicit scope language.
4. Confirm no em-dash characters in any written file. Use the actual
   em-dash codepoint (U+2014), not a regular hyphen:
   `! grep -rl "$(printf '\xe2\x80\x94')" "$AUDIT_DIR/"`.
5. Confirm every per-finding PoC has a matching `reproduce.sh` that runs
   the test (smoke-run it once if possible).
6. State `all cites verified` in the closing summary, or list exactly
   what could not be verified and why.

## Closing Message

Print:

```
Audit complete.

Findings: <N> (Critical: <c>, High: <h>, Medium: <m>, Low: <l>, Info: <i>)
Submittable (confidence >= 60, no gate failures): <K>

Report:    $AUDIT_DIR/report/REPORT.md
Findings:  $AUDIT_DIR/finding/
Headline exploit: $AUDIT_DIR/exploit/Exploit.sol
Per-finding PoCs: $AUDIT_DIR/report/POC/

(Print resolved absolute paths verbatim; $AUDIT_DIR depends on Scenario A vs B from Phase 0.)

All cites verified.

Never auto-submit. Review every finding before sharing externally.
```

If any submittable finding has `poc_status != PASSING`, list it
explicitly and downgrade per the validity gate.
