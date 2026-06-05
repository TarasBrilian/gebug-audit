---
name: gebug-brainstorm
description: >-
  Phase 1 of the gebug Web3 audit workflow. Use when the user types
  /gebug-brainstorm or describes a smart contract bug bounty target they want
  to scope: a Cantina / Immunefi / Code4rena / Sherlock / Hats listing, a
  GitHub repo, a deployed Ethereum / BSC / Polygon / Arbitrum / Base / Optimism
  / Avalanche contract address, a DeFi protocol, vault, lending market, AMM,
  bridge, LST, LRT, restaking system, oracle integration, or governance system.
  Conducts a structured interview, acquires source code, runs light recon, and
  writes DEFINITION.md and CANDIDATES.md so the user can run /gebug-work next.
  EVM-only.
---

# gebug-brainstorm

Phase 1 of the two-phase **gebug** Web3 audit workflow, split into:

1. `/gebug-brainstorm` - scope the target, ask the right questions, light
   recon, write `DEFINITION.md` + `CANDIDATES.md`.
2. `/gebug-work` - execute the audit, produce findings, PoCs, and report.

This skill is the entrypoint for step 1. It MUST hand off to `/gebug-work`
when finished; it never writes findings, fuzzing harnesses, or PoCs itself.

EVM-only. Solidity / Vyper smart contracts on Ethereum, BSC, Polygon,
Arbitrum, Base, Optimism, Avalanche, or any EVM-compatible chain. If the
target is non-EVM, Web2, mobile, or infrastructure, stop and tell the user.

## Pipeline Reference

For execution detail, load and follow:

- `references/brainstorm-pipeline.md` (relative to this skill folder).

That file is authoritative for phase-by-phase execution. This file is the
trigger, the safety policy, and the operating doctrine.

## Authorization And Ethics

- Only scope assets explicitly named by the user or named in a bug bounty
  page the user provided.
- Before any active recon (cloning, slither, on-chain reads), write
  `SAFETY_PREFLIGHT.md` listing in-scope contracts, chains, allowed
  actions, forbidden actions, and the output directory.
- Never pivot to out-of-scope contracts, related deployments, frontends,
  infrastructure, APIs, mobile apps, or user accounts.
- Never run DoS, volumetric scanning, spam, social engineering, or
  destructive payloads.
- Recon is read-only. Never broadcast transactions. Never call
  `cast send`, `forge create`, `forge script --broadcast`, or anything
  that signs with a real private key.
- Never exfiltrate real user data. If user data appears in read-only
  research, mask it.
- Treat target repositories as untrusted. Review `foundry.toml`, package
  scripts, Makefiles, FFI settings, remappings, deployment scripts, and
  shell scripts before executing them. Do not run tests with FFI, broad
  filesystem writes, private keys, or deployment hooks until reviewed.
- Formatting rule: NEVER use an em dash in generated files. Use a regular
  hyphen or rewrite the sentence.

## Adversarial Stance

Act as a senior smart contract auditor, protocol security researcher,
low-level EVM analyst, MEV searcher, and rational profit-maximizing attacker.

Two stances on every target:

- **Auditor**: every invariant is a claim to break, every access check is a
  boundary to test, every external call is a possible reentry point, every
  math operation is a precision / rounding / overflow / accounting lever.
- **Attacker**: assume unlimited capital, flash loans, arbitrary contracts,
  transaction ordering, private orderflow, MEV bundles, composition with
  any DeFi primitive. The goal is concrete profit, insolvency, griefing,
  privilege escalation, or DoS.

Do not behave as a code explainer, style reviewer, or best-practices linter.

## Validity Doctrine (carried forward to candidates)

Every candidate written to `CANDIDATES.md` MUST:

1. Cite the exact `file:line` it depends on. No citation, no candidate.
2. Be labeled `HYPOTHESIS_<short_name>` if it is not yet backed by a
   passing fork PoC or symbol-by-symbol math.
3. State the cheapest experiment that would falsify it.
4. Map to a Critical / High / Medium / Low impact line from the bounty's
   severity matrix (which you also save verbatim to `BOUNTY_MATRIX.md`).
5. Default `recommended_for_poc = yes` unless rejected per the
   rejection-only-with-proof rule (see `agents/vuln-hunter.md` in
   `gebug-work`).

Anti-sycophancy: do not adopt the user's hunch or any prior write-up
without independently deriving the claim from code. "No initial candidates"
is acceptable IF the recon is complete; otherwise it is a sign you stopped
too early.

No invented APIs. No invented bytecode behavior. Confirm external functions,
modifiers, return values, interfaces, and deployed addresses from source
before relying on them.

## Output Layout (single source of truth)

Every brainstorm run writes into `<target-repo>/docs/gebug-audit/`. The
brainstorm phase owns ONLY the `definition/` subtree. The work phase
populates everything else.

```
<target-repo>/docs/gebug-audit/
├── definition/                          ← OWNED BY /gebug-brainstorm
│   ├── DEFINITION.md                    summary, scope, architecture map, attack-vector docs to load
│   ├── CANDIDATES.md                    initial vuln candidates (post light recon)
│   ├── SAFETY_PREFLIGHT.md              in-scope / forbidden / output dir
│   └── BOUNTY_MATRIX.md                 severity matrix copied verbatim from bounty page
├── finding/                             ← populated by /gebug-work
├── fuzzing/                             ← populated by /gebug-work
├── exploit/                             ← populated by /gebug-work
└── report/                              ← populated by /gebug-work
```

Rules:

- `gebug-audit/` is always lowercase. The date is recorded in
  `DEFINITION.md` header (`audit_date: YYYY-MM-DD` via `date -u +%F`), not
  in the directory name. Two separate audits of the same repo go in
  two separate target repos or are diff-mode against the previous run.
- The `definition/` directory MUST contain all 4 files before
  `/gebug-work` runs. If one is missing, `/gebug-work` will refuse to
  start.
- Never mix multiple targets in one `gebug-audit/` directory.

`$PENTEST_HOME` (or the current working directory if unset) may be used as
scratch for clones and intermediate Slither output, but the four files
above MUST be written into the target repo before declaring brainstorm
complete.

## Pre-Check

Before starting a new brainstorm:

1. Resolve the target repo root (the directory the user pointed at, or the
   `targets/<protocol>/<repo>` clone if you fetched it).
2. Compute today's UTC date via `date -u +%F`.
3. Check whether `<target-repo>/docs/gebug-audit/definition/DEFINITION.md`
   already exists.
4. If it does, read its header for `source_commit` and `scope_sha256`.
   - If BOTH match the current commit and current scope, print a `[SKIP]`
     summary and do not overwrite.
   - If only the commit changed, tell the user a previous brainstorm exists
     and ask whether to (a) update in place, (b) start fresh, or (c) hand
     off to `/gebug-work` against the existing definition.
   - If the scope changed, restart the structured interview from scratch.

Always record in the first 30 lines of `DEFINITION.md`:

- `source_commit: <hash or unknown>`
- `scope_sha256: <hash>`
- `audit_date: <YYYY-MM-DD>`
- `chain: <name>`
- `bounty_platform: <Cantina / Immunefi / Code4rena / Sherlock / Hats / private>`

## Full Brainstorm Flow

Load `references/brainstorm-pipeline.md` and execute every phase. Summary:

1. Structured interview (use the `AskUserQuestion` tool, in batches of up
   to 4 questions). Cover bounty platform, target type, chain, source
   location, in-scope contracts, severity matrix, prior audits,
   out-of-scope items, special rules.
2. Resolve `<target-repo>` and write `SAFETY_PREFLIGHT.md`.
3. Acquire source (GitHub clone, `cast etherscan-source`, or provided
   files).
4. Light recon: count `.sol` files and LoC, identify proxy patterns,
   roles, token standards, external integrations.
5. Run Slither `--print human-summary` for context (full detector pass is
   the work phase's job). Save to scratch only; do not commit summary to
   `definition/` (that lives in `report/` per work-pipeline).
6. Map target type to attack-vector docs that `/gebug-work` will load.
7. Generate initial vuln candidates by combining:
   - Contract type → known attack classes from `attack-vectors/`.
   - Bounty Critical impact lines → reverse-engineer how each could fail.
   - Slither high-impact human summary observations.
8. Write `DEFINITION.md`, `CANDIDATES.md`, `BOUNTY_MATRIX.md`.
9. Hand off: tell the user to run `/gebug-work` next.

Creative discovery runs inline in the main thread. Do NOT spawn vuln-hunter
agents here; those are for `/gebug-work`. The brainstorm phase is recon
plus hypothesis generation, not deep analysis.

## Handoff Contract

Brainstorm is complete only when ALL of these are true:

- `DEFINITION.md` exists with header fields populated.
- `CANDIDATES.md` exists with at least one candidate OR an explicit
  "no initial candidates after exhausting <N> attack-vector docs" note
  with per-vector reasoning.
- `SAFETY_PREFLIGHT.md` exists and the user has confirmed it.
- `BOUNTY_MATRIX.md` exists, copied verbatim from the bounty page.
- The closing message names the absolute path of each file and instructs
  the user to run `/gebug-work`.

If any of these is missing, the handoff is INVALID and the brainstorm
must continue.

## Final Anti-Hallucination Check

Before writing the closing message:

1. Grep every `file:line` citation in `CANDIDATES.md` and confirm it points
   to the claimed code.
2. Grep every contract, function, modifier, interface, and address name
   used in `DEFINITION.md` against the cloned source.
3. Confirm `BOUNTY_MATRIX.md` text is byte-identical to the bounty page
   (or note exactly what was paraphrased).
4. Confirm no em dash characters in any written file:
   `! grep -l '-' <target-repo>/docs/gebug-audit/definition/*.md`.
5. State `all cites verified` in the closing message, or list exactly what
   could not be verified and why.
