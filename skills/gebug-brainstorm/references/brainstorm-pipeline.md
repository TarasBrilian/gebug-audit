# gebug-brainstorm pipeline

Phase-by-phase execution reference for `/gebug-brainstorm`. The SKILL.md
file is authoritative for safety and doctrine. This file is authoritative
for execution.

EVM-only. Solidity / Vyper. Ethereum, BSC, Polygon, Arbitrum, Base,
Optimism, Avalanche, and other EVM-compatible chains.

## Conventions

- Capture the audit date once at start: `AUDIT_DATE=$(date -u +%F)`.
- Path resolution is determined by `SCENARIO` (see PHASE 0):
  - Scenario A (external): `<target-repo>` = `$CWD/<repo-name>/`,
    `AUDIT_DIR` = `<target-repo>/docs/gebug-audit/`.
  - Scenario B (self): `<target-repo>` = `$CWD`,
    `AUDIT_DIR` = `<target-repo>/gebug-audit/`.
- Set the output directory once at start and reuse:
  ```bash
  CWD=$(pwd)
  # SCENARIO resolved in Phase 0 below.
  # In Scenario A, after Phase 3 clone:
  TARGET_REPO="$CWD/<repo-name>"
  AUDIT_DIR="$TARGET_REPO/docs/gebug-audit"
  # In Scenario B (no clone):
  TARGET_REPO="$CWD"
  AUDIT_DIR="$TARGET_REPO/gebug-audit"
  # Definition dir is identical in both:
  DEFINITION_DIR="$AUDIT_DIR/definition"
  SCRATCH_DIR="$AUDIT_DIR/_scratch"
  mkdir -p "$DEFINITION_DIR" "$SCRATCH_DIR"
  ```
- Scratch lives in `$SCRATCH_DIR` (NOT `$PENTEST_HOME`). `$PENTEST_HOME`
  is reserved for global toolchain cache only.
- FORMATTING: never use an em dash. Use a regular hyphen.

## Supported chains

| Chain | RPC URL | Chain ID |
|-------|---------|----------|
| Ethereum | https://eth.llamarpc.com | 1 |
| BSC | https://bsc-dataseed.binance.org | 56 |
| Polygon | https://polygon-rpc.com | 137 |
| Arbitrum | https://arb1.arbitrum.io/rpc | 42161 |
| Base | https://mainnet.base.org | 8453 |
| Optimism | https://mainnet.optimism.io | 10 |
| Avalanche | https://api.avax.network/ext/bc/C/rpc | 43114 |

## PHASE -1: Tool pre-flight

Verify the tools needed for recon. The full toolchain check (including
Echidna, Halmos, Medusa) is the work-pipeline's job.

```bash
command -v forge   >/dev/null || echo "MISSING: forge (Foundry) - needed for fork checks"
command -v cast    >/dev/null || echo "MISSING: cast (Foundry) - needed for on-chain reads"
command -v slither >/dev/null || echo "MISSING: slither (pip install slither-analyzer)"
command -v git     >/dev/null || echo "MISSING: git"
```

If `forge`, `cast`, `slither`, or `git` are missing, stop and tell the user
to install them before continuing.

## PHASE 0: Auto-detect scenario + pre-check (skip already brainstormed)

### 0a. Auto-detect Scenario A vs B from cwd

```bash
CWD=$(pwd)
SCENARIO=""

# Marker F: foundry project
if [ -f "$CWD/foundry.toml" ] && { [ -d "$CWD/src" ] || [ -d "$CWD/contracts" ]; } && [ -d "$CWD/test" ]; then
  SCENARIO="B"
  MARKER="F (foundry.toml + src/contracts + test)"
fi

# Marker H: hardhat project
if [ -z "$SCENARIO" ] && { [ -f "$CWD/hardhat.config.js" ] || [ -f "$CWD/hardhat.config.ts" ]; } && [ -d "$CWD/contracts" ]; then
  SCENARIO="B"
  MARKER="H (hardhat config + contracts/)"
fi

# Marker P: package.json with hardhat/foundry-rs dep
if [ -z "$SCENARIO" ] && [ -f "$CWD/package.json" ]; then
  if grep -qE '"(hardhat|@nomicfoundation/hardhat-|@foundry-rs/)' "$CWD/package.json"; then
    SCENARIO="B"
    MARKER="P (package.json dev dep)"
  fi
fi

# Default: external repo
[ -z "$SCENARIO" ] && SCENARIO="A" && MARKER="(no markers detected)"

echo "Detected: Scenario $SCENARIO  [marker: $MARKER]"
```

### 0b. Announce + confirm scenario

Print one sentence describing what the skill will do, then call
`AskUserQuestion`:

- Scenario A: `Output will land in $CWD/<repo-name>/docs/gebug-audit/ (repo name resolved in Batch 1 of the interview).`
- Scenario B: `Output will land in $CWD/gebug-audit/. Source is your current project (no clone).`

Options:
- "Proceed" (proceed with detected scenario)
- "Override to other scenario" (user wants Scenario A even though markers say B, or vice versa)
- "Cancel" (stop the skill)

If user picks "Override", ask follow-up free-form what they want.

### 0c. Pre-check (skip already brainstormed)

After scenario confirmed, resolve `AUDIT_DIR`:

- Scenario A: AUDIT_DIR will be `$CWD/<repo-name>/docs/gebug-audit/` (NOT YET KNOWN until Batch 1 reveals repo). Defer the existence check until after Batch 1.
- Scenario B: AUDIT_DIR = `$CWD/gebug-audit/`. Check now:

```bash
if [ -f "$AUDIT_DIR/definition/DEFINITION.md" ]; then
  head -30 "$AUDIT_DIR/definition/DEFINITION.md"
fi
```

Compare `source_commit` and `scope_sha256` in the header:

- BOTH match current commit + current scope SHA → print `[SKIP]` and ask
  the user whether to hand off to `/gebug-work` directly.
- Only commit changed → ask the user: (a) update in place, (b) start
  fresh, or (c) hand off to `/gebug-work` against the existing definition.
- Scope changed → restart the interview from scratch.

## PHASE 1: Structured interview

Use the `AskUserQuestion` tool in batches. Tool limit is 4 questions per
call, so do this in 2-3 batches.

### Batch 1: Target identity

Ask 4 questions:

1. **Bounty platform** - Cantina / Immunefi / Code4rena / Sherlock / Hats
   / Private / None (research only).
2. **Target type** - Vault (ERC4626) / Lending / AMM / Bridge / LST /
   LRT / Restaking / Oracle / Governance / Stablecoin / Perp / Other.
3. **Source location** - GitHub repo URL / Etherscan-style address /
   Local path / Inline paste.
4. **Chain** - Ethereum / BSC / Polygon / Arbitrum / Base / Optimism /
   Avalanche / Other EVM.

If "Other" is picked anywhere, follow up with a free-form clarification
question (one at a time).

### Batch 2: Scope and severity

After Batch 1, ask up to 4 more:

1. **In-scope contracts** - paste the exact list (paths or addresses).
   If only the bounty page URL was given, offer to fetch it via `WebFetch`
   and parse the assets table.
2. **Out-of-scope items** - exclusions from the bounty page (governance
   tokens, frontend, mocks, deprecated contracts, etc.).
3. **Critical impact lines** - copy the bounty's severity matrix verbatim.
   If user pastes the whole bounty page, extract the matrix yourself and
   show it back for confirmation.
4. **Prior audits** - links to public audit reports, known issues lists,
   or competition findings to avoid re-finding.

### Batch 3: Operational context (only if needed)

If anything is still unclear, ask up to 4 more:

1. **Commit hash** - if a GitHub repo, which commit should be audited?
   Default to `HEAD` only with explicit user confirmation.
2. **Deployment status** - testnet / mainnet / not yet deployed. Affects
   whether `/gebug-work` builds PoCs against a live fork or a deploy
   script.
3. **Known issues to skip** - anything the user wants explicitly
   deprioritized.
4. **Special rules** - bounty-specific conditions (e.g., "no theoretical
   findings without PoC", "valid only if loss exceeds 1 ETH", L2 sequencer
   exclusions).

### Batch 4: Defense inventory (required for realistic scoring)

This batch feeds the skeptical-triager in /gebug-work Phase 6.5. Without
it, every MEDIUM+ finding will be scored without defender context and
will be inflated. Ask up to 4:

1. **Current TVL** in USD. If the user does not know, plan to read it
   on-chain in Phase 4 (see Phase 4 addendum). The TVL anchors the
   bounty matrix's "Critical = > X% of TVL" thresholds.
2. **Monitoring partners** - Hypernative / Forta / Tenderly / Chaos Labs
   / custom. What do they alert on? Estimated response time
   (minutes / hours / days)?
3. **Guardian / pause / veto roles** - who can pause, how fast can they,
   what they can pause. Are there cold-wallet signers? On-call rotation?
4. **Timelock durations** per privileged action: OWNER, UPDATER_*,
   RESERVE_MANAGER, etc. Plus the multisig threshold (e.g., 3/5, 2/3).
   Historical response-to-incident time if known.

If the user does not know defense details, mark `defense_inventory:
incomplete` in DEFINITION.md. The skeptical-triager will refuse to apply
the Defender falsifier without explicit citations, so missing context
biases the audit TOWARD keeping findings (i.e., gracefully degrades).

Do NOT pile on more questions. If something material is still missing
after Batch 4, ask the single most important follow-up as free-form text
rather than another structured batch.

## PHASE 2: Safety preflight

Resolve `<target-repo>` from the answers based on SCENARIO from PHASE 0:

- Scenario A (external, no project markers in cwd): if source is a GitHub
  URL, target repo will be created at `$CWD/<repo-name>/` after Phase 3.
  `<repo-name>` is the lowercased final path segment of the URL (e.g.,
  `https://github.com/rocket-pool/rocketpool` -> `rocketpool`). If source
  is an Etherscan address, `<repo-name>` = `<protocol-slug>-<address-prefix>`.
- Scenario B (project markers in cwd): `<target-repo>` = `$CWD` directly.
  No clone is performed.

For now (Phase 2 preflight), write to `$AUDIT_DIR/SAFETY_PREFLIGHT.md`
using the resolved AUDIT_DIR from Phase 0 / Phase 3 (see "Conventions"
at top of file for the exact computation).

Write `$DEFINITION_DIR/SAFETY_PREFLIGHT.md`:

```markdown
# Safety preflight

**Audit date:** 2026-06-06 (UTC)
**Bounty platform:** Cantina
**Target repo:** <absolute path>
**Chain:** Ethereum
**Output dir:** `$AUDIT_DIR` (see Conventions for scenario-specific resolution)

## In-scope contracts

- contracts/Vault.sol (0xAbCd...)
- contracts/Strategy.sol (0xEf01...)

## Out-of-scope

- governance/*
- frontend/*
- mock/*

## Allowed actions

- Read-only on-chain queries (cast call, cast storage, cast block-number).
- Local fork via anvil / forge test.
- Static analysis with Slither and Aderyn.

## Forbidden actions

- cast send, forge create, forge script --broadcast.
- Any command using a real private key.
- Any action that writes to mainnet.
- Touching any contract not in the in-scope list above.
- Touching frontend, mobile, infra, or off-chain APIs.

## Confirmation

User confirmed: _yes / no_
```

Show this back to the user and require explicit confirmation before any
active recon (clone, slither, cast call). If the user changes anything,
rewrite the file before continuing.

## PHASE 3: Acquire source

### 3a. GitHub provided (Scenario A only)

Skip this phase entirely in Scenario B (source is `$CWD`, already there).

```bash
# SCENARIO is A
REPO_NAME=$(basename "<repo-url>" .git | tr '[:upper:]' '[:lower:]')
TARGET_REPO="$CWD/$REPO_NAME"
if [ -d "$TARGET_REPO" ]; then
  echo "Existing target dir found at $TARGET_REPO. Ask user: update / start fresh / hand off."
  # Defer to user-confirmed branch per Phase 0 pre-check semantics.
else
  git clone <repo-url> "$TARGET_REPO"
fi
cd "$TARGET_REPO"
git checkout <commit_hash>
git rev-parse HEAD > "$SCRATCH_DIR/source_commit"
```

If the user did not pin a commit, fail loud and ask.

### 3b. Address provided (Scenario A)

```bash
REPO_NAME="<protocol-slug>-${ADDRESS:2:8}"
TARGET_REPO="$CWD/$REPO_NAME"
mkdir -p "$TARGET_REPO"
cast etherscan-source <address> --chain <chain> -d "$TARGET_REPO/"
```

If the chain is not Ethereum, set the explorer API key via
`ETHERSCAN_API_KEY` and the appropriate `--chain` flag.

### 3c. Scenario B (skip - source already in cwd)

```bash
TARGET_REPO="$CWD"
# No clone. Just verify expected structure based on detection marker:
#   F: src/ or contracts/ exists, foundry.toml exists
#   H: contracts/ exists, hardhat.config.* exists
#   P: at least one *.sol file under tree
find "$TARGET_REPO" -maxdepth 4 -name '*.sol' | head -5
```

### 3c. Both

Use GitHub as primary. Cross-reference Etherscan bytecode against the
GitHub commit's compiled bytecode if the user wants verification.

### 3d. Inline / local

Use the path the user provided as `<target-repo>`.

After acquisition:

```bash
find <target-repo> -name '*.sol' -not -path '*/lib/*' -not -path '*/node_modules/*' | wc -l
find <target-repo> -name '*.sol' -not -path '*/lib/*' -not -path '*/node_modules/*' -exec wc -l {} +
```

Record the file count and total LoC; you will need them for `DEFINITION.md`
and to decide vuln-hunter agent allocation in the work phase.

## PHASE 4: Light recon

Read in order:

1. `README.md`, `docs/`, NatSpec on public functions.
2. `foundry.toml` / `hardhat.config.{js,ts}` / `remappings.txt` for build
   layout.
3. Top-level contract files in the in-scope list. Identify:
   - Proxy pattern (UUPS / Transparent / Beacon / none).
   - Access control (Ownable / AccessControl / custom roles).
   - Token standards (ERC20 / ERC4626 / ERC721 / ERC1155 / custom).
   - External integrations (Chainlink / Pyth / Uniswap / Aave / EigenLayer
     / LayerZero / etc.).
   - Upgrade path (timelock? guardian? immediate?).

For deployed contracts, read on-chain state:

```bash
cast storage <address> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <rpc>
cast call <address> "owner()(address)" --rpc-url <rpc>
cast call <address> "implementation()(address)" --rpc-url <rpc>
```

Read any provided existing audits. Pull the published findings into the
"prior audits" section of `DEFINITION.md`.

### Phase 4 addendum: on-chain economic context

If the protocol is deployed, read live state via `cast` so the
skeptical-triager in /gebug-work Phase 6.5 has real numbers to apply
the Economic and Defender falsifiers. Save the output to
`$SCRATCH_DIR/onchain-state.md`. Skip this addendum if the protocol is
NOT yet deployed.

```bash
RPC=<choose from supported chains table>
PIN_BLOCK=$(cast block-number --rpc-url $RPC)

# 1. TVL anchor for "Critical = > X% of TVL" thresholds.
cast call <accounting_or_vault_addr> "<tvl-getter>()(uint256)" --rpc-url $RPC --block $PIN_BLOCK

# 2. Reserve balance for "admin can rescue" arguments.
cast call <accounting_addr> "<reserve-getter>()(uint256)" --rpc-url $RPC --block $PIN_BLOCK

# 3. Recent admin activity (gauge response cadence baseline).
cast logs --from-block $((PIN_BLOCK - 100000)) --to-block $PIN_BLOCK <admin_addr> --rpc-url $RPC | head -20
```

Substitute the actual getters from the target protocol. Document in
`onchain-state.md`: TVL in USD, reserve in USD, last 5 admin events with
timestamps. These numbers feed the mandatory
`attacker_cost_usd` / `attacker_profit_usd` / `protocol_tvl_required_usd`
fields that vuln-hunter MUST populate in /gebug-work Phase 4 output.

## PHASE 5: Quick static pass (recon only)

```bash
slither "$TARGET_REPO" --print human-summary 2>&1 | tee "$SCRATCH_DIR/slither-human-summary.txt"
```

If Slither fails on missing remappings:

```bash
slither <target-repo> --solc-remaps "@openzeppelin=lib/openzeppelin-contracts" --print human-summary
```

This is scratch only. The full detector pass (which lands in
`<target-repo>/docs/gebug-audit/report/`) is the work-pipeline's job.

Note the contract-by-contract LoC breakdown and any standout flags
(reentrancy detectors triggered, uninitialized variables, etc.) for
seeding candidates.

## PHASE 6: Map to attack-vector docs

Use the target type from Batch 1 plus what Phase 4 actually found.

| Target type observed | attack-vectors to load (in `/gebug-work`) |
|---|---|
| Vault (ERC4626) | `lst-lrt.md`, `oracle-integration.md` |
| LST | `lst-lrt.md`, `oracle-integration.md` |
| LRT / Restaking | `restaking.md`, `lst-lrt.md`, `oracle-integration.md` |
| Lending | `lending.md`, `oracle-integration.md` |
| AMM | `amm.md`, `oracle-integration.md` |
| Bridge | `bridge.md`, `oracle-integration.md` |
| Governance | `governance.md` |
| Oracle | `oracle-integration.md` |
| Stablecoin / Perp / Other | `oracle-integration.md` + nearest match |

ALWAYS add `oracle-integration.md` if any contract reads an external
price / rate / value. Multiple docs can apply.

Record the list in `DEFINITION.md` so `/gebug-work` knows what to load
without re-deriving.

### Phase 6 pre-flight: verify docs reachable from /gebug-work install

Before recording the list, confirm each doc exists in at least one
plausible install location. Without this check, the brainstorm "succeeds"
but `/gebug-work` Phase 0 refuses (work-pipeline.md "Verify each exists
in `<this-skill>/references/attack-vectors/`"), which forces the user
to rerun an entire brainstorm to recover. Loud failure here saves that
round-trip.

```bash
VECTORS_TO_LOAD=( "lst-lrt.md" "oracle-integration.md" )  # populated per target type
CANDIDATE_ROOTS=(
  "$HOME/.claude/skills/gebug-work/references/attack-vectors"
  "$HOME/.claude/plugins/cache/anthropic/claude-code/gebug-audit/skills/gebug-work/references/attack-vectors"
  "$CWD/.claude/skills/gebug-work/references/attack-vectors"
)

MISSING=()
for doc in "${VECTORS_TO_LOAD[@]}"; do
  FOUND=""
  for root in "${CANDIDATE_ROOTS[@]}"; do
    if [ -f "$root/$doc" ]; then FOUND="$root/$doc"; break; fi
  done
  [ -z "$FOUND" ] && MISSING+=("$doc")
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo "REFUSE: attack-vector docs not found in any known gebug-work install path:"
  printf '  - %s\n' "${MISSING[@]}"
  echo "Searched roots:"
  printf '  - %s\n' "${CANDIDATE_ROOTS[@]}"
  echo "Reinstall via gebug-audit/install.sh or copy the docs manually,"
  echo "then rerun /gebug-brainstorm."
  exit 1
fi
```

If your `/gebug-work` lives at a non-standard path (e.g., project-scoped
install at `.claude/skills/gebug-work/`), add the root to
`CANDIDATE_ROOTS` before running. The default list covers the three
common install modes from README.md (user, plugin cache, project).

## PHASE 7: Generate initial candidates

This is hypothesis generation, not deep analysis. Combine three sources:

### 7a. Contract-type heuristics

For each target type, scan the loaded attack-vector doc's items and ask:
"is the pattern that this attack class targets present in the source?"
File-level only at this stage; do not trace full call paths.

Example: target is a lending fork. Load `lending.md`. For L1.1
(first-supplier hToken inflation), grep the in-scope source for the mint
formula `mint = assets * totalSupply / totalAssets`. If present, candidate
`HYPOTHESIS_L1_1_first_supplier_inflation`.

### 7b. Reverse from bounty Critical lines

For each Critical impact line in `BOUNTY_MATRIX.md`, ask: "what code path
would cause this to occur?" Trace backward from the harm to the surface
that could trigger it.

Example: Critical line says "permanent freezing of user funds > 1 day".
Candidate: trace every public withdraw / redeem / claim function and
check for state that admin could set to lock them (paused flag, asset
whitelist, role gate).

### 7c. Slither human-summary

For each flagged item in the human-summary that lands in an in-scope
contract, derive a candidate. Most will be false positives by the work
phase, but recording them ensures coverage.

### Candidate format

Write to `CANDIDATES.md` using this template per candidate:

```markdown
## C{N}. HYPOTHESIS_{short_name}

- **Title:** one-line description
- **Contract:** ContractName.sol
- **Citations:** path/to/file.sol:L120-L145 (every line you depend on)
- **Attack class:** which attack-vector doc + item (e.g., lending.md L1.1)
- **Severity hypothesis:** Critical / High / Medium / Low (pre-PoC guess)
- **Bounty mapping:** which line in BOUNTY_MATRIX.md
- **Why plausible:** one paragraph
- **Cheapest falsifier:** the single cheapest test that would disprove it
- **Recommended for PoC:** yes (default) / no + rejection-with-proof
  citation per the vuln-hunter rejection rule
```

Aim for breadth, not depth. The validity gate runs in the work phase.

### Anti-rejection rule

A candidate is NOT rejected by "unlikely", "improbable", "users would
not", or "admin would not". The full doctrine is the SIX QUANTIFIED
falsifiers defined in `gebug-work/agents/vuln-hunter.md` § Anti-rejection
rule. Restated here so the brainstorm doctrine matches the work-phase
doctrine byte-for-byte:

1. Code-path falsifier with `file:line` of the blocking check.
2. Math falsifier with symbol-by-symbol derivation showing attacker
   nets ≤ 0.
3. State falsifier with on-chain `cast` read at the current block.
4. Bounty falsifier quoting exact exclusion language from
   `BOUNTY_MATRIX.md`.
5. Economic falsifier with cited numeric `attacker_cost_usd` and
   `attacker_profit_usd`, attacker rationally nets ≤ 0 USD AND no
   `pure_grief_motive` applies. Defer to /gebug-work Phase 6.5 if the
   numbers cannot be derived from on-chain reads alone.
6. Defender falsifier citing a specific mechanism named in
   `DEFINITION.md` "Defense Inventory" with response time shorter than
   the attack window. Defer to /gebug-work Phase 6.5 if the defense
   inventory is `incomplete`.

Brainstorm bias is BREADTH. The cheapest position is "keep the
candidate, let `/gebug-work` falsify with a PoC". Only invoke
falsifiers 5 and 6 here when the data is already in hand and the
verdict is unambiguous. Otherwise pass the candidate through and let
skeptical-triager apply Economic + Defender in Phase 6.5.

Anything else (hand-wavy "unlikely", "would not"): keep the candidate.

## PHASE 8: Write the four artefacts

### DEFINITION.md

```markdown
# Definition

- **audit_date:** 2026-06-06
- **source_commit:** abc1234
- **scope_sha256:** <sha256 of normalized scope list>
- **chain:** Ethereum
- **bounty_platform:** Cantina
- **bounty_url:** https://...
- **target_repo:** <absolute path>
- **brainstorm_skill_version:** gebug-brainstorm@1.0.0

## Summary

One paragraph: what the protocol does, the core mechanism, the assets at
risk, the trust model.

## In-scope contracts

| Path | LoC | Address | Type |
|------|-----|---------|------|
| contracts/Vault.sol | 412 | 0xAbCd... | ERC4626 |
| contracts/Strategy.sol | 287 | 0xEf01... | Adapter |

## Architecture

Core vs periphery, proxy patterns, access control, integrations, upgrade
paths. Funds flow: source → custody → strategy → user.

## Attack-vector docs to load (for /gebug-work)

- references/attack-vectors/lst-lrt.md
- references/attack-vectors/oracle-integration.md

## Defense Inventory

Required by /gebug-work Phase 6.5 (skeptical-triager). Without this
section, the Defender falsifier cannot fire and findings will be scored
without defender context. If a row's value is unknown, write `unknown`
explicitly - DO NOT guess.

| Mechanism | Address / Role | Trigger | Response time | Notes |
|-----------|----------------|---------|---------------|-------|
| Current TVL (anchor for de-minimis) | n/a | n/a | n/a | $X at block Y |
| Monitoring partner #1 | e.g. Hypernative | alert classes | minutes / hours | URL or contact |
| Monitoring partner #2 | e.g. Forta | ... | ... | ... |
| PAUSER multisig | 0x... (M-of-N) | what they can pause | est. minutes | on-call rotation? |
| Guardian / veto | 0x... | what they can veto | hours / days | identity |
| OWNER timelock | 0x... | privileged role | 48h | |
| Lower-tier timelock | 0x... | UPDATER_STRAT etc. | 24h | |
| Historical incident response | n/a | n/a | observed median | from public post-mortems |
| `defense_inventory_complete` | n/a | n/a | n/a | yes / no |

## Prior audits

- Spearbit Q3 2025: <link>, known issues: 7 informational, 0 critical fixed
- Code4rena Mar 2026: <link>

## Out-of-scope (verbatim from bounty)

- governance/*
- mocks/*

## Special rules

- Sequencer-uptime issues are out of scope (per bounty).
- Findings only valid if loss > 1 ETH (per bounty).

## Subsystem split (preview for /gebug-work Phase 4)

- Vault.sol: deposit / withdraw cluster (4 functions, ~120 LoC)
- Vault.sol: admin / role cluster (3 functions, ~60 LoC)
- Strategy.sol: harvest / report cluster (~150 LoC)

## Handoff

Next: run `/gebug-work` from the same working directory. It will read
this file and `CANDIDATES.md` to drive execution.
```

### CANDIDATES.md

```markdown
# Initial candidates

Generated by /gebug-brainstorm. Each candidate is a HYPOTHESIS until
/gebug-work either builds a passing PoC or rejects with proof per the
vuln-hunter rejection rule.

Total candidates: N

## C1. HYPOTHESIS_first_supplier_inflation
(per the template in Phase 7c)

## C2. HYPOTHESIS_oracle_staleness
...
```

### SAFETY_PREFLIGHT.md

Already written in Phase 2.

### BOUNTY_MATRIX.md

```markdown
# Bounty severity matrix

Copied verbatim from <bounty URL> on 2026-06-06.

## Critical

- Direct theft of user funds.
- Permanent freezing of funds > 1 day.
- Conversion rate manipulation > 5%.

## High

- ...
```

Every line in this file MUST be checkable against the source bounty page.
If you paraphrased anything, mark it `[paraphrased: original was "..."]`.

## PHASE 9: Final anti-hallucination check

Before declaring done:

1. Grep every `file:line` in `CANDIDATES.md`:
   ```bash
   for cite in $(grep -oE '[a-zA-Z_/.-]+\.sol:L[0-9]+' "$DEFINITION_DIR/CANDIDATES.md"); do
     file=${cite%:L*}; line=${cite##*:L}
     test -f "<target-repo>/$file" || echo "MISSING FILE: $file"
   done
   ```
2. Grep every contract / function / modifier / interface name used in
   `DEFINITION.md` against the cloned source:
   ```bash
   grep -rE 'contract [A-Z][A-Za-z0-9_]+ ' <target-repo>/contracts/
   ```
3. Confirm no em-dash characters. The pattern is the actual em-dash
   codepoint (U+2014), built via `printf` so the skill file itself does
   not contain a literal em-dash:
   ```bash
   EM_DASH=$(printf '\xe2\x80\x94')
   ! grep -l "$EM_DASH" "$DEFINITION_DIR/"*.md
   ```
4. If any check fails, fix the file before closing.

## PHASE 10: Handoff message to user

Print exactly:

```
Brainstorm complete.

Definition: $DEFINITION_DIR/DEFINITION.md
Candidates: $DEFINITION_DIR/CANDIDATES.md   (N candidates)
Safety:     $DEFINITION_DIR/SAFETY_PREFLIGHT.md
Bounty:     $DEFINITION_DIR/BOUNTY_MATRIX.md

(Resolved absolute paths printed verbatim; SCENARIO and $CWD determine the prefix.)

All cites verified.

Next: run /gebug-work from the same working directory.
```

If anything could not be verified, list it explicitly under
"Could not verify:" and tell the user how to resolve before running
`/gebug-work`.

Never auto-trigger `/gebug-work`. The user runs it.
