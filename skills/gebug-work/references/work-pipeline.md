# gebug-work pipeline

Phase-by-phase execution reference for `/gebug-work`. The SKILL.md is
authoritative for safety and doctrine. This file is authoritative for
execution.

EVM-only. Solidity / Vyper. Mainnet fork only for PoC validation; never
live broadcast.

## Conventions

- Capture once at start. Re-run the SAME detection from
  `/gebug-brainstorm` Phase 0 to recover `$AUDIT_DIR`:
  ```bash
  AUDIT_DATE=$(date -u +%F)
  CWD=$(pwd)

  # Auto-detect scenario (same logic as brainstorm-pipeline Phase 0)
  SCENARIO=""
  if [ -f "$CWD/foundry.toml" ] && { [ -d "$CWD/src" ] || [ -d "$CWD/contracts" ]; } && [ -d "$CWD/test" ]; then
    SCENARIO="B"
  elif { [ -f "$CWD/hardhat.config.js" ] || [ -f "$CWD/hardhat.config.ts" ]; } && [ -d "$CWD/contracts" ]; then
    SCENARIO="B"
  elif [ -f "$CWD/package.json" ] && grep -qE '"(hardhat|@nomicfoundation/hardhat-|@foundry-rs/)' "$CWD/package.json"; then
    SCENARIO="B"
  else
    SCENARIO="A"
  fi

  if [ "$SCENARIO" = "B" ]; then
    TARGET_REPO="$CWD"
    AUDIT_DIR="$TARGET_REPO/gebug-audit"
  else
    # Scenario A: find subdirectory of $CWD that has a populated
    # docs/gebug-audit/definition/. If multiple, ask user; if none, refuse.
    candidates=$(find "$CWD" -maxdepth 4 -type d -name 'definition' -path '*/docs/gebug-audit/definition' 2>/dev/null)
    # ... resolve to a single TARGET_REPO; AUDIT_DIR = $TARGET_REPO/docs/gebug-audit
    AUDIT_DIR="$TARGET_REPO/docs/gebug-audit"
  fi

  DEFINITION_DIR="$AUDIT_DIR/definition"
  FINDING_DIR="$AUDIT_DIR/finding"
  FUZZING_DIR="$AUDIT_DIR/fuzzing"
  EXPLOIT_DIR="$AUDIT_DIR/exploit"
  REPORT_DIR="$AUDIT_DIR/report"
  POC_DIR="$REPORT_DIR/POC"
  SCRATCH_DIR="$AUDIT_DIR/_scratch"
  mkdir -p "$FINDING_DIR" "$FUZZING_DIR" "$EXPLOIT_DIR" "$REPORT_DIR" "$POC_DIR" "$SCRATCH_DIR"

  # Auto-generate .gitignore (idempotent)
  cat > "$AUDIT_DIR/.gitignore" <<'EOF'
_scratch/
_preflight/
fout/
cache/
*.log
EOF
  ```
- All four definition files MUST exist before any other phase runs.
- All Foundry PoCs land in `$POC_DIR/<finding-slug>/Exploit.t.sol` with a
  sibling `reproduce.sh`.
- Headline exploit lives at `$EXPLOIT_DIR/Exploit.sol`.
- Use a mainnet fork for ALL exploit validation; never test on real
  mainnet.
- Use `vm.deal()` for attacker funding (simulated, zero risk).
- Pin block numbers for reproducibility.
- **Foundry env setup**:
  - Scenario A: skill creates `$TARGET_REPO/foundry.toml` (if not already
    present) + `$TARGET_REPO/fout-libs/forge-std/` for PoC compilation.
  - Scenario B: skill PATCHES the user's existing `$TARGET_REPO/foundry.toml`
    to add `gebug-audit/report/POC` to the test path. Original config
    saved to `$SCRATCH_DIR/foundry-toml.original`; patch diff saved to
    `$SCRATCH_DIR/foundry-toml-patch.diff`. If Hardhat-only (no foundry.toml),
    skill CREATES a minimal one at project root.
- FORMATTING: NEVER use an em dash. Use a regular hyphen.

## Slug derivation

A slug is lowercase, kebab-case, derived from the finding title plus the
attack class. Example: title "First-supplier hToken inflation drains
new depositors" → slug `first-supplier-htoken-inflation`.

Slugs must be unique within an audit. If two findings collide, append a
short hash of the contract path: `first-supplier-htoken-inflation-vault`.

## PHASE -1: Full toolchain pre-flight

```bash
command -v forge   >/dev/null || echo "MISSING: forge (Foundry)"
command -v cast    >/dev/null || echo "MISSING: cast (Foundry)"
command -v anvil   >/dev/null || echo "MISSING: anvil (Foundry)"
command -v slither >/dev/null || echo "MISSING: slither (pip install slither-analyzer)"
command -v aderyn  >/dev/null || echo "OPTIONAL: aderyn (cargo install aderyn)"
command -v echidna >/dev/null || echo "OPTIONAL: echidna - property fuzzing"
command -v medusa  >/dev/null || echo "OPTIONAL: medusa - Crytic Go fuzzer"
command -v halmos  >/dev/null || echo "OPTIONAL: halmos (pipx install halmos)"
```

If `forge`, `cast`, `anvil`, or `slither` are missing, STOP and tell the
user to install them. Do not silently skip a phase.

## PHASE 0: Re-validate definition inputs

```bash
for f in DEFINITION.md CANDIDATES.md SAFETY_PREFLIGHT.md BOUNTY_MATRIX.md; do
  test -f "$DEFINITION_DIR/$f" || { echo "MISSING: $f"; exit 1; }
done
```

If any is missing, refuse to start and tell the user to run
`/gebug-brainstorm`.

Read `DEFINITION.md` header. If `source_commit` differs from
`git -C "$TARGET_REPO" rev-parse HEAD`, ask the user whether to:

- (a) rebrainstorm first,
- (b) run in DIFF-FOCUSED mode against changed files only (prioritize
      vuln-hunter coverage on the changed files and any function whose
      call-graph touches them; note previously-cleared areas so you do
      not re-spend the full budget on unchanged code), or
- (c) continue anyway.

Read the list of attack-vector docs from `DEFINITION.md` under
"Attack-vector docs to load". Verify each exists in
`<this-skill>/references/attack-vectors/`. If any is missing, name it
and stop.

## PHASE 1: Static analysis

```bash
slither "$TARGET_REPO" --print human-summary 2>&1 \
  | tee "$REPORT_DIR/slither-summary.txt"

slither "$TARGET_REPO" \
  --detect reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events,reentrancy-unlimited-gas,uninitialized-state,uninitialized-storage,arbitrary-send-erc20,arbitrary-send-eth,unchecked-transfer,unprotected-upgrade,suicidal,delegatecall-loop,controlled-delegatecall,events-access,events-maths,incorrect-equality,locked-ether,unused-return,weak-prng,divide-before-multiply,incorrect-shift,tx-origin \
  2>&1 | tee "$REPORT_DIR/slither-high-impact.txt"
```

If Slither fails on dependencies:

```bash
slither "$TARGET_REPO" --solc-remaps "@openzeppelin=lib/openzeppelin-contracts" ...
```

Second-engine pass when available:

```bash
aderyn "$TARGET_REPO" -o "$REPORT_DIR/aderyn-report.md"
```

Cross-reference detector findings against `CANDIDATES.md`. New patterns
flagged by Slither / Aderyn that are NOT in `CANDIDATES.md` should be
appended as new candidates.

## PHASE 2: Fuzzing, invariants, and symbolic analysis

**Mandatory trigger** - Phase 2 cannot be skipped if ANY of:

- Contract has arithmetic beyond plain ERC20 transfer (multiply, divide,
  share math, rate math, fee math, slashing math).
- Contract is a vault, AMM, lending market, staking adapter, LST, LRT,
  bonding curve, oracle, or restaking integration.
- Contract has a state machine with ≥ 3 distinct phases.
- `BOUNTY_MATRIX.md`'s Critical lines include "conversion rate
  manipulation", "share inflation", "fund accounting", or any
  quantitative bound.

If the trigger applies and Phase 2 is skipped, the audit is INCOMPLETE.
`REPORT.md` must state explicitly which fuzzing was attempted and what
was found (even if no counterexample).

### Foundry invariant / fuzz

```solidity
// $FUZZING_DIR/{slug}_Invariant.t.sol
contract ProtocolInvariant is Test {
    Target target;
    function setUp() public {
        vm.createSelectFork("mainnet", BLOCK);
        target = Target(TARGET_ADDR);
        targetContract(address(target));
    }
    function invariant_totalSupplyEqualsSumBalances() public view { ... }
    function invariant_shareValueMonotone() public view { ... }
    function invariant_noFreeMoney() public view { ... }
}
```

Run: `forge test --fuzz-runs 50000 --match-contract Invariant`.

A broken invariant is a Phase 3 lead. Save counterexamples to
`$FUZZING_DIR/{invariant_name}.counterexample`.

### Echidna / Medusa

```yaml
# $FUZZING_DIR/echidna.yaml
testMode: "assertion"
testLimit: 100000
seqLen: 100
deployer: "0x10000"
sender: ["0x10000", "0x20000", "0x30000"]
```

Run: `echidna "$TARGET_REPO/contracts/Target.sol" --config "$FUZZING_DIR/echidna.yaml"`.

### Halmos symbolic execution

```bash
halmos --contract Target --function {functionName} --solver-timeout-assertion 30000
```

Halmos is MANDATORY for: rate / share computation, fee accounting,
liquidation threshold math, signature recovery, ECDSA, BLS verification,
proof verification, slashing math.

If halmos hangs or finds counterexamples, save to
`$FUZZING_DIR/halmos_{function}.out`.

### Invariant catalog by contract type

| Contract type | Invariants to assert |
|---|---|
| ERC20 / LST | `totalSupply == sum(balances)`, `transfer(a,b,x); transfer(b,a,x);` net zero |
| ERC4626 vault | `convertToShares(convertToAssets(x)) <= x`, share value monotone, `totalAssets >= totalSupply * minSharePrice` |
| LRT / restaking | rate monotone (modulo slashing), `totalShares <= sum(stakerShares)`, withdrawal queue conservation |
| Lending | `totalBorrow * IRM(util) <= totalSupply * IRM`, LTV always < liquidation threshold |
| AMM | `k = x*y` constant (or x^(1-w)*y^w for weighted), no extractable value via add-remove liquidity cycle |
| Oracle consumer | `read_consecutive(N).delta < HEARTBEAT_TOLERANCE` |
| Bridge | sum-in == sum-out across chains |

Write `$REPORT_DIR/INVARIANTS.md` listing every invariant asserted, the
status (passing / broken with counterexample / not yet checked), and the
harness file path.

Write `$FUZZING_DIR/FUZZING.md`:

```markdown
# Fuzzing summary

| Harness | Tool | Runs | Status | Counterexample |
|---------|------|------|--------|----------------|
| Vault_Invariant.t.sol | foundry | 50000 | PASS | - |
| echidna.yaml | echidna | 100000 | PASS | - |
| halmos rate() | halmos | timeout 30s | found | halmos_rate.out |

## Notes

Per-harness commentary. What each tested, what was learned, follow-ups.
```

## PHASE 2 EXIT GATE: hard-check fuzzing artifacts

Before Phase 3 can start, `$FUZZING_DIR/FUZZING.md` MUST exist. This
mirrors the Phase 0 refusal for missing definition files: Phase 0
refuses without scoping evidence; this gate refuses without fuzzing
evidence. A silent Phase 2 skip is the most common way a real bug
(broken invariant, halmos counterexample, fuzzing seed crash) goes
undiscovered, and the "mandatory trigger" prose at the top of Phase 2
is not self-enforcing.

```bash
if [ ! -f "$FUZZING_DIR/FUZZING.md" ]; then
  echo "REFUSE: Phase 2 did not produce $FUZZING_DIR/FUZZING.md."
  echo "Either run Phase 2 properly or write FUZZING.md documenting"
  echo "why fuzzing was not applicable. The exemption MUST cite ALL"
  echo "four conditions: no arithmetic beyond plain ERC20 transfer,"
  echo "not a vault / AMM / lending / staking / oracle / restaking /"
  echo "bridge integration, no state machine with >= 3 phases, no"
  echo "quantitative bound in BOUNTY_MATRIX.md Critical lines."
  exit 1
fi
```

If the file exists but the table is empty (no rows), treat as failure
unless the "Notes" section explicitly cites all four exemption
conditions above. The orchestrator may NOT continue to Phase 3 on
implicit skip.

## PHASE 3: Reconnaissance (re-read with adversarial eyes)

`/gebug-brainstorm` already did light recon. Re-read with the adversarial
stance:

- Read every NatSpec comment with skepticism. Words like "safely",
  "should never", "trusted" mark places to attack.
- For each external integration, read the integrated contract's source
  too (not just the interface). Trust boundaries are the highest-value
  attack surface.
- For each proxy, read the implementation and ALL prior implementations
  (via Etherscan).
- For each role, list every function it can call and the worst outcome
  per call.

Add anything new to `CANDIDATES.md` as a new `HYPOTHESIS_*` candidate.

## PHASE 4: Parallel deep analysis

### 4a. Subsystem split

For each in-scope contract, decide the subsystem split:

| Contract LoC | Min agents | Recommended allocation |
|---|---|---|
| ≤ 200 | 1 | single agent covers the whole file |
| 201 – 500 | 2 – 3 | split by subsystem (admin / user / view) |
| 501 – 1000 | 4 – 5 | split by subsystem |
| > 1000 | one agent per natural subsystem | each gets ≤ 300 LoC focus |

Subsystem identification heuristics:

- Functions sharing a state machine (delegate / undelegate / queue /
  complete).
- Functions sharing a storage cluster (mappings, structs).
- Functions sharing a role gate.
- Functions sharing an external contract dependency.
- View functions stand alone (or attach to their writers).

### 4b. Token-budget gate

If total proposed agent count > 10, STOP. Show the user:

- Total in-scope LoC.
- Proposed agent count.
- Per-agent subsystem list.

Ask for approval, scope narrowing, or split into multiple runs. Do not
spawn until the user approves.

### 4c. Spawn vuln-hunter agents

Spawn in parallel via the `Agent` tool. The agent definition lives at
`<this-skill>/agents/vuln-hunter.md`. Pass it via `subagent_type` if your
agent registry has it; otherwise inline the prompt from that file.

Each agent receives:

- Absolute path to the contract source file(s) and subsystem assignment
  (function list).
- `DEFINITION.md`, `INVARIANTS.md` (from Phase 2), and relevant
  candidates from `CANDIDATES.md`.
- On-chain addresses.
- Names of `attack-vector` docs to load. Defaults from the Phase 6 map in
  `brainstorm-pipeline.md`.
- Known issues to skip (from `DEFINITION.md` prior audits section).
- Relevant Slither / Aderyn findings on the agent's subsystem.
- The verbatim in-scope contract list and `BOUNTY_MATRIX.md`.

**STRICT IN-SCOPE FILTER**: only analyze contracts EXPLICITLY listed in
`DEFINITION.md` "In-scope contracts" table. BOUNDARY exploration is
allowed (how does the in-scope contract trust an out-of-scope one?), but
findings ship only against in-scope contracts.

Wait for all agents to complete. Collect the union of candidates, do NOT
pre-dedup (Phase 6 dedups). Two agents finding the same candidate
independently is a confidence boost.

### 4c-validate. Schema-check every vuln-hunter output

Before any candidate flows into Phase 5/6/6.5, parse and validate the
YAML block defined in `agents/vuln-hunter.md` § Output format. The
downstream phases READ fields by key, so a missing or mis-typed field
silently breaks Phase 6.5's falsifier checks and Phase 8's severity
recalibration.

Save each agent's raw YAML to `$SCRATCH_DIR/vh-<agent-id>.yaml`, then:

```bash
# Minimal validator. Requires: python3 + python3-yaml (pip install pyyaml).
python3 - <<'PY' "$SCRATCH_DIR"/vh-*.yaml
import sys, yaml, pathlib

REQUIRED_PER_CAND = ["title", "severity_hypothesis", "confidence_0_100",
    "contract", "citations", "root_cause", "attack_path", "preconditions",
    "single_strongest_doubt", "cheapest_falsifier",
    "in_scope_impact_mapping", "domain_attack_class",
    "slither_cross_ref", "recommended_for_poc"]

# These six fields are required ONLY when severity_hypothesis is
# Critical/High/Medium. Low/Info candidates may omit them.
REQUIRED_FOR_MEDIUM_PLUS = ["precondition_probabilities",
    "attacker_cost_usd", "attacker_profit_usd", "pure_grief_motive",
    "protocol_tvl_required_usd", "defender_response_time_estimate"]

MEDIUM_PLUS = {"Critical", "High", "Medium"}
fail = 0
for path in sys.argv[1:]:
    doc = yaml.safe_load(pathlib.Path(path).read_text())
    if not isinstance(doc, dict) or "candidates" not in doc:
        print(f"INVALID: {path} - missing top-level `candidates`"); fail += 1; continue
    cands = doc["candidates"]
    if cands == [] and "honest_negative_result" not in doc:
        print(f"INVALID: {path} - empty candidates without honest_negative_result"); fail += 1; continue
    for i, c in enumerate(cands):
        for k in REQUIRED_PER_CAND:
            if k not in c:
                print(f"INVALID: {path} cand[{i}] missing {k}"); fail += 1
        if c.get("severity_hypothesis") in MEDIUM_PLUS:
            for k in REQUIRED_FOR_MEDIUM_PLUS:
                if k not in c:
                    print(f"INVALID: {path} cand[{i}] ({c.get('title')}) MEDIUM+ missing {k}"); fail += 1
sys.exit(1 if fail else 0)
PY
```

If validation fails for ANY agent, re-spawn THAT agent with stricter
framing quoting `agents/vuln-hunter.md` § Output format. Do NOT
hand-patch missing fields - the agent must produce them so the
provenance is traceable. After two re-spawns of the same agent without
success, fall back: take the candidates that DID validate, mark the
failing subsystem `subsystem_skipped_due_to_schema_failure` in the
working ledger, and continue. The `REPORT.md` Honest Negative Result
section MUST surface skipped subsystems explicitly.

### 4d. Anti-dismissal AND anti-pile-on (symmetric)

If all spawned agents return "no candidates", the orchestrator MUST
investigate WHY before re-spawning. Two scenarios:

- **Genuine clean codebase**: the protocol is well-defended and the
  in-scope contracts have been audited multiple times. Honest negative
  result is the correct outcome - proceed to Phase 5 / 6 with empty
  candidate pool and let Phase 11 produce an honest-negative report.
- **Biased agent prompts**: the prompts under-specified attack vectors,
  missed subsystem boundaries, or excluded relevant attack-vector docs.
  Symptom: a different reviewer would surface candidates the agents
  missed. In this case re-spawn with stricter framing quoting the
  rejection-only-with-proof rule from `agents/vuln-hunter.md`.

You may NOT re-spawn just because the audit "feels empty". Re-spawn
only when you can name (a) specific attack vectors the agents skipped
or (b) specific subsystems with > 300 LoC that received zero candidates.

This is symmetric with the anti-pile-on rule in `agents/skeptical-triager.md`
(Phase 6.5): just as unanimous "all High" suggests vuln-hunter bias,
unanimous "no candidates" can be honest. Do not force findings to
appear; let the pipeline speak.

## PHASE 5: Cross-contract analysis

Address each explicitly:

### 5a. Trust boundary inventory

For every external call, answer:

- Who is the callee? Address pinned in source, or settable by an admin?
- What happens if the callee returns malicious data (revert, reentry,
  unexpected return value, gas exhaustion)?
- What happens if the callee is upgraded? (Most EigenLayer / Aave /
  Chainlink contracts are upgradable behind a proxy.)

### 5b. Shared storage / accounting consistency

For every contract pair that updates a shared accounting variable
(e.g., totalShares, totalAssets across vault + adapter), prove that no
sequence of legitimate calls can desynchronize them. Counter-example
goes to PoC.

### 5c. Upgrade-path race

For each upgradable contract:

- Who can upgrade?
- Is there a timelock? How long?
- Does the upgrade preserve storage layout? (Run `forge inspect <contract>
  storage-layout` against old and new implementations if both are
  available.)
- What user state could be invalidated by the upgrade?

### 5d. MEV / ordering

For every state-changing call that depends on external state:

- Can an MEV bot sandwich it (front + back run)?
- Is the call value-bearing (oracle update, liquidation, deposit at a
  rate that drifts)?

### 5e. Reentrancy across contracts

The CEI pattern protects a single contract. Across contracts, the call
graph A → B → C → A is reentrant even if every contract uses CEI
internally. Trace every external call.

Add findings from 5a-5e to the candidate pool as new
`HYPOTHESIS_*` entries.

## PHASE 6: Compile candidates (rejection-only-with-proof)

Collect candidates from: `CANDIDATES.md`, Slither, Aderyn, fuzzing,
vuln-hunter agents, cross-contract analysis. Deduplicate (same root
cause = one candidate).

**PoC is the falsifier, NOT this phase.** Candidates with
`recommended_for_poc = yes` flow to Phase 7. Candidates with
`recommended_for_poc = economic-gate-needed` are flagged for
skeptical-triager review in Phase 6.5 below. This phase only applies
rejections that meet the rejection-only-with-proof rule (the SIX
quantified falsifier types - see `agents/vuln-hunter.md` § Rejection-only-
with-proof rule for full definitions).

Doubts are NOT rejections. Record doubts in each candidate's
`single_strongest_doubt` field and let PoC empirically falsify.

### Strict in-scope filter (carefully, not aggressively)

- Contract / target NOT in `DEFINITION.md` in-scope list → write NO
  findings for it, not even "out-of-scope". Skip entirely.
- Out-of-scope vuln classes per `BOUNTY_MATRIX.md` → EXCLUDE.
- Undeployed contracts → LOW at most unless the bounty includes
  undeployed code.
- "Best practices", "defense-in-depth", "documentation mismatch" →
  generally OUT unless they directly cause fund loss. NatSpec / doc
  mismatch is NOT a vuln.
- "Temporarily blocked" (funds recoverable after admin unpause / update)
  is NOT fund loss - unless the bounty matrix says otherwise.
- `// TODO`, `// XXX`, placeholder reverts are known dev items, NOT
  findings.

### Economic validation for price-manipulation candidates

Quantify "attacker spends X to manipulate, extracts Y". If Y ≤ X,
EXCLUDE. Same-pool manipulation costs real money and is by design; only
cross-venue oracle attacks with cost / value asymmetry are vulns.

### For every MEDIUM+ candidate, answer:

- Exact sequence of user-controlled actions that triggers it.
- Mathematical proof it is possible.
- Is the damage permanent / irreversible? (Recoverable via admin = not a
  vuln unless bounty says otherwise.)
- Is the behavior intentional design?
- Would a dev fix the code or the docs?

Candidates that survive flow to Phase 6.5. Write the working ledger to
`$AUDIT_DIR/_candidates_working.md` (template below) and keep it
appended-to through Phases 6, 6.5, 7, and 8. Do NOT write findings yet;
findings are only written after PoC in Phase 8.

### Working ledger template (`_candidates_working.md`)

This file is the single source of truth that the orchestrator and the
spawned skeptical-triager / exploit-writer agents read to decide what
flows where. Without a deterministic format, each phase re-parses ad-hoc
prose and silently drops candidates - the symptom is "findings missing
in REPORT.md even though vuln-hunter surfaced them in scratch". The
file is gitignored via `$AUDIT_DIR/.gitignore`.

Initial structure (Phase 6 writes this; later phases append columns,
verdict blocks, and severity updates):

````markdown
# Working ledger (gebug-audit)

Updated continuously from Phase 6 through Phase 8. Each candidate has
ONE row; status moves left to right as phases complete. Phase 6 fills
columns id..phase6_status. Phase 6.5 fills triager_verdict. Phase 7
fills poc_status. Phase 8 fills final_severity and finding_file.

| id | slug | title | source | severity_hypothesis | phase6_status | triager_verdict | poc_status | final_severity | finding_file |
|----|------|-------|--------|---------------------|----------------|------------------|------------|----------------|--------------|
| C1 | first-supplier-htoken-inflation | First-supplier hToken inflation | brainstorm | Critical | KEEP | AFFIRM | PASSING | Critical | finding/CRITICAL_first-supplier-htoken-inflation.md |
| C2 | oracle-staleness | Stale Chainlink round accepted | vuln-hunter:vault | High | KEEP | DOWNGRADE Medium | PASSING | Medium | finding/MEDIUM_oracle-staleness.md |
| C3 | admin-key-loss | Admin key loss bricks vault | slither | Medium | REJECTED | n/a | n/a | n/a | (see rejection citation below) |

## Source legend

- `brainstorm`: from `definition/CANDIDATES.md`.
- `vuln-hunter:<subsystem>`: produced by a Phase 4 agent.
- `slither` / `aderyn` / `echidna` / `halmos`: surfaced by Phase 1 / 2.
- `cross-contract`: produced by Phase 5.

## phase6_status legend

- `KEEP`: passes rejection-only-with-proof. Flows to Phase 6.5.
- `REJECTED`: one of the SIX QUANTIFIED falsifiers fires; cite below
  under `## C<id> rejection`.
- `DEDUPED_TO_<id>`: same root cause as an earlier candidate.

## triager_verdict legend (Phase 6.5)

- `AFFIRM`: severity stands.
- `DOWNGRADE <tier>`: severity capped; falsifier cited in the
  skeptical-triager output saved at `_scratch/triager-<id>.md`.
- `REJECT`: dropped; falsifier cited.
- `n/a`: LOW / Info candidates skip Phase 6.5.

## poc_status legend (Phase 7)

`PASSING`, `FAILED`, `INVALID`, `NOT_BUILT` (per `agents/exploit-writer.md`).

## final_severity legend (Phase 8)

Re-derived from the PoC's measured numbers; capped by the triager
verdict. Never carried forward unchanged from `severity_hypothesis`.

## Per-candidate rejection / downgrade citations

For every REJECTED or DOWNGRADE row, add a block here. Example:

### C3 rejection
- **Falsifier:** Code-path (#1 of six in `agents/vuln-hunter.md`).
- **Citation:** `Vault.sol:L412-L419` - `emergencyWithdraw()` already
  on-chain, so the "permanent freezing" bounty line does not apply.
- **Reviewer:** Phase 6 orchestrator after slither cross-reference.
````

The orchestrator updates this file IN PLACE between phases; do not
rewrite it from scratch per phase. Spawned agents that need to read
candidate state (skeptical-triager, exploit-writer) take this file path
as input rather than re-parsing CANDIDATES.md.

## PHASE 6.5: Skeptical-triager pass

Independent realism filter. Counters the vuln-hunter agents' built-in
bias toward surfacing candidates by spawning a separate agent whose
mandate is to REJECT using the Economic + Defender falsifiers
(falsifiers #5 and #6 in `agents/vuln-hunter.md`).

Trigger: every candidate with `severity_hypothesis` in
{Critical, High, Medium} AND `recommended_for_poc` in
{yes, economic-gate-needed} flows through this phase.

For each such candidate, spawn one `skeptical-triager` agent (see
`agents/skeptical-triager.md`). Each agent receives:

- The candidate's full vuln-hunter output (including the mandatory
  economic + defender fields).
- `DEFINITION.md` (especially "Defense Inventory" section) and
  `BOUNTY_MATRIX.md`.
- Current on-chain state snapshot saved to `_scratch/onchain-state.md`
  (TVL, reserve, recent admin activity).

The agent returns one of:

- **AFFIRM** - severity stands. Candidate proceeds to Phase 7 at the
  vuln-hunter's proposed severity.
- **DOWNGRADE <new_severity>** - severity capped at `<new_severity>`
  with cited Economic or Defender reasoning. Candidate proceeds to
  Phase 7 at the capped severity.
- **REJECT** - candidate dropped. Citation MUST quote one of the six
  falsifiers from `agents/vuln-hunter.md`. Hand-wavy rejections are
  inadmissible here too.

Record each verdict in `_candidates_working.md` with the citation. If
vuln-hunter and skeptical-triager disagree, the FINAL `REPORT.md` must
present both views side-by-side.

**Anti-pile-on rule**: if skeptical-triager REJECTS more than 50% of
MEDIUM+ candidates, the orchestrator MUST re-spawn the triager once with
stricter framing quoting BOTH the Anti-rejection rule AND the
Anti-pile-on rule. Unanimous rejection across many candidates may
indicate triager bias toward "no findings" - symmetric to the
vuln-hunter anti-dismissal rule.

## PHASE 7: PoC development and validation

**Every MEDIUM+ candidate MUST be verified by RUNNING code, not just
reading source.** Spawn an `exploit-writer` agent per candidate.

The agent definition lives at `<this-skill>/agents/exploit-writer.md`.

Each agent receives:

- The candidate (title, contract, file:line, attack path, preconditions,
  expected impact).
- Chain name and a pinned fork block number.
- The slug derived from the candidate title.
- Path to write the PoC: `$POC_DIR/<slug>/Exploit.t.sol`.
- Sibling reproduce script path: `$POC_DIR/<slug>/reproduce.sh`.

### Foundry template + reproduce.sh template

The canonical PoC template (3 variants: profit / grief / invariant-breach)
and the reproduce.sh template live in `agents/exploit-writer.md` (§ EVM
template, § reproduce.sh template, § Hard rules). DO NOT duplicate them
here. The exploit-writer agent will produce a PoC that conforms to those
templates including:

- Mandatory profit-required assertion (variant A) OR documented-grief
  asymmetry assertion (variant B) OR named-invariant breach (variant C).
- Mandatory realistic-state requirement (initial TVL >=
  100x bounty de-minimis OR live mainnet fork).
- Mandatory mainnet-fork-only constraint, pinned block, no real keys.

### Validation outcomes

- **PASSING**: PoC compiles, runs, asserts profit. Candidate becomes a
  finding in Phase 8. Capture full forge output as `console.txt` in the
  POC folder.
- **FAILED**: PoC compiles but the assertion fails OR the math
  derivation does not check out. Mark candidate INVALID in the working
  ledger. Document why under the candidate's notes.
- **NOT_BUILT**: Candidate was discarded before PoC (per
  rejection-only-with-proof). Record the rejection citation.

**HARD RULE**: no MEDIUM+ finding ships in the final report without a
PASSING PoC or verifiable local execution output. Otherwise downgrade to
LOW / INFO.

### Headline exploit

After all per-finding PoCs, pick the single highest-impact PASSING PoC
and copy / adapt it to `$EXPLOIT_DIR/Exploit.sol`. This is the "showcase"
exploit. If there are no Criticals, the highest-severity PASSING PoC
becomes the headline. If no PoC passed, leave `$EXPLOIT_DIR/` empty and
note this in `REPORT.md`.

## PHASE 8: Write findings

For each PASSING PoC, write one file under
`$FINDING_DIR/{SEVERITY}_{slug}.md` using the Finding Template from
`references/finding-template.md` (load on demand).

Reference the per-finding PoC by relative path
(`report/POC/<slug>/Exploit.t.sol`) and the reproduce script
(`report/POC/<slug>/reproduce.sh`).

Paste the actual forge PASS output (truncate to the relevant lines).

Cross-link related findings (e.g., shared root cause across two
contracts) at the bottom of each finding's "References" section.

### Severity recalibration (mandatory)

The severity written in `{SEVERITY}_{slug}.md` MUST be RE-DERIVED from
the PoC's MEASURED outputs, not carried forward from the vuln-hunter's
`severity_hypothesis`. Specifically:

1. Read the PoC's logged `net attacker P/L`, `victim loss`, or
   invariant-breach magnitude. Use the ACTUAL numbers, not the
   pre-PoC estimate.
2. Apply the skeptical-triager's verdict from Phase 6.5 as a CEILING.
   You may only set severity at or below the triager's downgrade.
3. Apply the Severity Calibration checklist in `SKILL.md` (sections
   A - F) ONCE MORE using the post-PoC numbers.
4. If the PoC's measured impact does NOT meet the bounty matrix line
   the candidate originally mapped to, REMAP to the highest line that
   the measured impact does meet. If no line matches, severity caps
   at LOW with `would_submit_to_bounty: no`.

The "do not pre-downgrade" rule in `SKILL.md` Severity Calibration
applies to the WORK PHASE (before PoC). After PoC, evidence-based
re-derivation is REQUIRED. These are complementary, not contradictory:
do not soften without evidence; do harden / adjust with evidence.

## PHASE 9: Write the headline report

`$REPORT_DIR/REPORT.md`:

```markdown
# Security audit report: {Protocol Name}

- **Audit date:** YYYY-MM-DD
- **Source commit:** abc1234
- **Chain:** Ethereum
- **Auditor:** gebug (gebug-brainstorm + gebug-work)
- **Bounty platform:** Cantina

## Executive summary

- Scope: N contracts, M total LoC.
- **Raw findings produced by vuln-hunter**: c+h+m+l+i.
- **Findings surviving skeptical-triager (Phase 6.5)**: K1.
- **Findings surviving PoC severity recalibration (Phase 8)**: K2.
- **Findings recommended for bounty submission**: K3.
  - = candidates with `would_submit_to_bounty: yes`
    AND `triager_reject_probability < 30%`
    AND `poc_status: PASSING`.
- **Headline exploit attacker P/L**: $X (positive = real exploit,
  negative = grief with documented motive, zero = invariant-breach
  with no direct extraction).

Honesty discipline: if K3 = 0, the executive summary MUST emphasize
that as a positive defense-in-depth outcome. Do not inflate K3 by
relaxing the gates.

## Scope

| Contract | Address | LoC | GitHub |
| ... |

## Findings summary

| # | Severity | Title | Contract | PoC status | Confidence |
| 1 | Critical | First-supplier hToken inflation | Vault.sol | PASSING | 92 |
| ... |

## Detailed findings

Link each finding file. One bullet per finding with a one-sentence
summary.

## Fuzzing summary

Link to `fuzzing/FUZZING.md`. Note any broken invariants that turned into
findings, and any that surprised even though no exploit landed.

## Methodology

- Static analysis: Slither (+ Aderyn if used).
- Manual: parallel vuln-hunter agents per subsystem.
- Fuzzing: Foundry invariants (+ Echidna / Halmos as relevant).
- PoC: Foundry mainnet fork at pinned block.

## Out of scope

Verbatim from `BOUNTY_MATRIX.md`.

## Honest negative notes (if applicable)

For any rejected candidate, the rejection citation per the
rejection-only-with-proof rule.

## Cite verification

All file:line citations and contract / function names were grep-verified
against the source at commit abc1234.
```

## PHASE 10: Final anti-hallucination check + dramatic-phrasing linter

```bash
# 1. Citations
for f in "$FINDING_DIR"/*.md; do
  for cite in $(grep -oE '[a-zA-Z_/.-]+\.sol:L[0-9]+(-L[0-9]+)?' "$f"); do
    file=${cite%:L*}; line=${cite##*:L}
    test -f "$TARGET_REPO/$file" || echo "MISSING FILE in $f: $file"
  done
done

# 2. Em dashes (U+2014). The pattern is built via printf so the
#    skill source itself does not contain a literal em-dash.
EM_DASH=$(printf '\xe2\x80\x94')
! grep -rl "$EM_DASH" "$AUDIT_DIR/"

# 3. PoC smoke run
for poc in "$POC_DIR"/*/reproduce.sh; do
  test -x "$poc" || echo "NOT EXECUTABLE: $poc"
done

# 4. Dramatic-phrasing linter (NEW)
#    Phrases that trigger review: they sound severe but rarely carry
#    quantification. Each hit must be either quantified or removed.
for phrase in \
  "becomes un-updateable" \
  "persistent leakage" \
  "indefinite freeze" \
  "indefinite delay" \
  "bricked state" \
  "destroyed protocol" \
  "catastrophic loss" \
  "complete denial of service"; do
  grep -nH "$phrase" "$FINDING_DIR"/*.md && echo "DRAMATIC PHRASE in $f: $phrase"
done

# Each hit MUST be replaced with a quantified statement:
#   "becomes un-updateable" -> "all updates revert until <state X> is restored,
#                              which requires <Y action> taking <Z time>"
#   "persistent leakage" -> "Junior loses $A per block until <Y action>"
#   "indefinite freeze" -> "freezes for <T> hours/days until <admin/timelock>"
#   "bricked state" -> "<entrypoint X> reverts; the admin escape is <Y>
#                       which takes <Z time>"
#
# If a hit cannot be quantified, the underlying finding is likely an
# already-dead or trivial-precondition case - revisit Phase 6.5 verdict.

# 4. Required files present
for required in \
  "$REPORT_DIR/REPORT.md" \
  "$REPORT_DIR/INVARIANTS.md" \
  "$REPORT_DIR/slither-summary.txt" \
  "$REPORT_DIR/slither-high-impact.txt" \
  "$FUZZING_DIR/FUZZING.md"; do
  test -f "$required" || echo "MISSING REQUIRED: $required"
done
```

If any check fails, fix before closing.

## PHASE 11: Closing summary to user

Print exactly:

```
Audit complete.

Findings: N (Critical: c, High: h, Medium: m, Low: l, Info: i)
Submittable (confidence >= 60, no gate failures): K

Report:           $REPORT_DIR/REPORT.md
Findings dir:     $FINDING_DIR/
Headline exploit: $EXPLOIT_DIR/Exploit.sol
Per-finding PoCs: $POC_DIR/
Fuzzing:          $FUZZING_DIR/

(Print resolved absolute paths verbatim; $AUDIT_DIR depends on Scenario A vs B from Phase 0.)

All cites verified.

Never auto-submit. Review every finding before sharing externally.
```

If `K = 0`, list which gates failed for the closest candidates so the
user knows what evidence would flip them.

---

## Focused modes

If the user asks for a narrower task than the full pipeline (after a
brainstorm has produced the definition files), still use this pipeline
but narrow execution:

### `audit-only <subsystem>`

Skip Phase 7 (no PoC). Useful for early-stage review where the user
wants candidate quality before committing PoC budget. All `finding/`
files are written with `poc_status: NOT_BUILT` and severity capped at
HIGH pending PoC. Honest-negative rules still apply.

### `exploit-only <candidate-id>`

Run only Phase 7 for a single candidate from `CANDIDATES.md`. Writes a
single PoC at `$POC_DIR/<slug>/`. Updates `CANDIDATES.md` with the PoC
status.

### `fork-test <slug>`

Re-run an existing PoC at a different fork block. Update the
`reproduce.sh` block number, run, report pass / fail / profit / gas.

### `triage <candidate-id>`

Apply the validity gate to a single candidate without building a PoC.
Returns the rejection citation if rejected, or "passes gate; recommend
PoC" otherwise.

### `report-only`

Skip everything except Phases 8 - 11. Useful when the user fixed a
finding template and wants to regenerate the report from existing
PoCs.
