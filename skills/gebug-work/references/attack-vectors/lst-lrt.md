# Liquid Staking / Restaking Token catalog

Use this when the target is an LST (stETH, swETH, rETH-class) or LRT
(rswETH, weETH, ezETH-class). Many of these also apply to ERC4626 vaults.

Restaking-specific items live in `restaking.md`. This doc focuses on
exchange-rate, mint, burn, deposit, and withdrawal-queue mechanics.

## L1. Mint amount uses requested, not received, balance

```solidity
token.safeTransferFrom(user, address(this), requested);
uint256 shares = requested * rate / 1e18;  // BUG if FoT or rebase
```

Correct pattern:

```solidity
uint256 before = token.balanceOf(address(this));
token.safeTransferFrom(user, address(this), requested);
uint256 received = token.balanceOf(address(this)) - before;
uint256 shares = received * rate / 1e18;
```

**Probe**: every `safeTransferFrom` followed by an arithmetic mint.

## L2. First-depositor share inflation

See `restaking.md` R14.

## L3. Rate-provider trust boundary

If `rate = oracle.getRate()` and the oracle is admin-set:

- Is the oracle's data source manipulable in a single tx (spot price)?
- Does it use a TWAP with a sufficient window for the value being moved?
- Is there a circuit-breaker on >X% per-block movement?

**Manipulation econ**: for a real exploit, attacker spend < extracted
value. Quantify this - same-pool manipulation is by-design (costs equal
gains).

## L4. Withdrawal queue invariant

`totalAssets >= sum(pendingExitShares) * rate`

If this can break, late-exiting users get less than they queued for.

**Probe**: how is `exitingETH` computed? Is it a live view or cached?
Can deposits race against pending exits and use up the protocol's exit
reserve?

## L5. Conversion rate manipulation > X%

The bounty's Critical impact line is usually "conversion rate manipulation
> N%". To map a candidate to this, you must show:

- Attacker action X causes `rate()` view to misreport by >N%.
- At least one downstream consumer (LP, lending market, AMM) acts on the
  misreported rate within the attack window.
- Attacker extracts value via the downstream consumer.

A rate that misreports for 1 block but no consumer reads it = no impact.

## L6. Slippage protection (minSharesOut)

Deposits and withdrawals should both accept a minOut. If only one side
has it, the other side is sandwichable.

**Probe**: every `deposit` / `mint` / `redeem` / `withdraw`. Each must take
slippage param. Missing slippage = High severity if a sandwicher can
extract.

## L7. Permit / EIP-712 implementation

LST tokens typically implement ERC2612 (permit). Common bugs:

- `chainId` missing from domain separator → cross-chain replay if same
  token deployed on multiple chains.
- `signer == address(0)` not checked → malleable signature accepts (0,0,0).
- Nonce reuse or non-monotonic nonces.
- DOMAIN_SEPARATOR cached at construction → wrong after fork.

## L8. Reprice / oracle integration

LST contracts that admin-`reprice()` based on off-chain beacon-chain data:

- Sanity bounds on `newRate` vs `oldRate` (e.g., revert if delta >5%).
- Time-lock on rate updates.
- Reprice frequency cap.

Without these, a compromised REPRICER role can set arbitrary rate, draining
LP / lending market positions instantly.

## L9. Burn-on-withdrawal vs mint-on-deposit asymmetry

If shares mint = `assets * supply / total` (round down) but burn = `assets * supply / total` (round up), the protocol gains dust per cycle. Over many
cycles, this is significant.

If the asymmetry is REVERSED, the protocol loses dust per cycle. With
flash loans, attackers can cycle deposit + withdraw to drain.

**Probe**: compare the rounding direction of mint vs burn.

## L10. Fee-on-transfer / rebasing whitelisted asset

Same as L1. If admin EVER whitelists a FoT or rebasing token, all the L1
math breaks.

This is a "trapdoor admin action" - bug exists in the code today, latent
until activation.

## L11. Withdrawal-queue strategy ordering

LRTs that hold N strategies and serve withdrawals from "the first one with
enough balance" can be griefed by attackers depositing into strategy 1 and
forcing later users to wait for the slower strategy 2.

**Probe**: how does the contract pick which strategy to withdraw from? Is
the choice user-controllable?

## L12. ETH dust at deposit boundary (rounding)

Deposit accepting native ETH with `_amount * rate / 1e18` math rounds down.
The rounded-off wei stays in the contract. A non-issue per deposit, but
documents whether the protocol has a sweep function or accumulates.

This is informational unless the dust can be coordinated into a >1 ETH
attack.

## L13. Pause and recover patterns

LSTs commonly have `pause()` and `unpause()` roles. While paused:

- Are withdrawal queues frozen?
- Are mints frozen?
- Are admin sweeps still possible?

A pause that freezes both sides is fine. A pause that only freezes one
side (e.g., users can't exit but admin can still sweep) is a centralization
red flag.

## L14. Total-supply vs balance-sum invariant

`totalSupply() == sum(balances)`. Broken by:

- Mint without supply increment.
- Burn without supply decrement.
- Direct storage write bypassing the standard ERC20 paths.

This is the canonical Echidna / Halmos invariant. Always testable.

## L15. Rate increase from beacon-chain rewards is centralization

LST rate increases due to beacon-chain accrual must be reflected in
`rate()`. If the contract has no automatic accrual and waits for admin
`reprice()`, the rate is **stale** between reprices. Users who deposit at
stale rate get less than they should; users who withdraw at stale rate get
more.

Quantify: how stale can the rate get? Daily reprice on a 4% APR LST means
~0.011% stale per day. Cross the 10% threshold? Only if reprice halts for
months. Map to bounty severity.

## Reachability check

Same checklist as `restaking.md`. Every candidate must answer who, what,
why, what blocks, in-scope.
