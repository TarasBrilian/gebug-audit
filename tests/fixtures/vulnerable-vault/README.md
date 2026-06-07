# vulnerable-vault: gebug-audit regression fixture

A minimal Foundry project containing a deliberately vulnerable ERC4626-style
vault. Exists as a manual regression target: after non-trivial changes to
the `gebug-brainstorm` or `gebug-work` skills, run them against this
fixture and confirm the expected findings still surface.

This fixture is NOT a deployment artifact. The Vault.sol contract ships
with a known share-inflation bug and must not be deployed to any chain.

## How to use

From this directory:

```bash
cd tests/fixtures/vulnerable-vault
# 1. Scope (Scenario B is auto-detected via foundry.toml + src/ + test/)
/gebug-brainstorm
# Answer interview as: target type = Vault (ERC4626), chain = local,
# in-scope = src/Vault.sol, bounty platform = None (research only).

# 2. Execute
/gebug-work
```

Expected `gebug-audit/` tree after a clean run:

```
tests/fixtures/vulnerable-vault/gebug-audit/
├── definition/{DEFINITION,CANDIDATES,SAFETY_PREFLIGHT,BOUNTY_MATRIX}.md
├── finding/CRITICAL_first-supplier-share-inflation.md  (or HIGH, depending on triager verdict)
├── fuzzing/FUZZING.md
├── exploit/Exploit.sol
└── report/REPORT.md + POC/first-supplier-share-inflation/{Exploit.t.sol,reproduce.sh}
```

## Expected findings

The pipeline MUST surface at least one finding mapped to attack class
`lending.md L1.1` (or the broader L1 class) with citation
`src/Vault.sol:L30-L46` covering the `deposit` mint formula. The PoC
must show:

1. Attacker is the first depositor of 1 wei. `totalShares = 1`.
2. Attacker donates underlying directly to the contract address (no
   `deposit` call), so `totalAssets` becomes large but `totalShares`
   stays at 1.
3. Honest depositor calls `deposit(amount)` where `amount < totalAssets`.
   The mint formula `amount * 1 / totalAssets` rounds to 0, triggering
   the `ZERO_SHARES` revert OR (in a variant) crediting the attacker
   with a disproportionate share of future yield.

Severity post-PoC: Critical or High, depending on the bounty matrix the
user picked during brainstorm (this fixture has no bounty, so any
non-trivial severity is acceptable).

## What "regression" means here

The fixture passes if `gebug-work` produces:

- A `finding/` file naming the inflation bug.
- A passing Foundry PoC under `report/POC/<slug>/Exploit.t.sol`.
- The four definition files from the brainstorm phase.

The fixture FAILS if any of:

- No finding is produced (false negative).
- A finding is produced but its PoC does not assert net attacker
  profit OR named victim loss (Phase 7 exit gate broken).
- The pipeline writes findings outside the expected subtree.
- Lint passes but layout-sync drift went undetected (rare; the
  cross-file synchronization checks should catch that separately).

This is a manual check, not a CI gate. The skills depend on
`AskUserQuestion` and other interactive tools that are not currently
scripted, so automation would require a headless harness that does not
yet exist.

## Why first-supplier inflation

It is the simplest known DeFi bug class that can be expressed in one
file under 60 lines, has a canonical citation in the gebug attack-vector
catalog (`lending.md` L1.1), and produces a testable PoC against a local
fork. Other candidates (oracle staleness, slippage gaps, reentrancy)
either need a Chainlink mock or a richer call graph and would balloon
the fixture beyond its purpose.
