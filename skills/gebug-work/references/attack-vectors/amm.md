# AMM attack vectors

Use this when the target is an automated market maker: Uniswap v2 / v3 / v4
forks, Curve, Balancer, Maverick, Camelot, Trader Joe v2, Velodrome v2,
PancakeSwap v3, or any constant-product / weighted / stable-swap / hooks-based
AMM.

Always pair with `oracle-integration.md` since AMMs are oracle sources
AND consumers (LP token pricing, TWAP feeds).

Items below are organized by mechanism. Every candidate must include a
file:line citation per the rejection-only-with-proof rule in
`gebug-work/agents/vuln-hunter.md`.

## Reachability check before writing each candidate

For each candidate, answer in plain English:

1. Who can call? (anyone, LP, swapper, hook, admin)
2. What can the attacker control? (token-in, amount, recipient, deadline,
   hook calldata, callback, flash-loan size)
3. What does the attacker want? (steal LP fees, break k-invariant,
   inflate LP shares, drain via callback, manipulate TWAP, JIT
   liquidity, MEV sandwich)
4. What blocks the attack at the audit fork block? (slippage param,
   deadline, k-check after, lock guard)
5. Map to bounty Critical Impact line.

## A1. k-invariant breakage (constant product)

Pattern: `x * y >= k` checked after each swap. If the check is missing,
miscalculated, or done with rounding in the wrong direction, attackers
can extract value per swap.

**Probe**:

- Is the post-swap k check present in every swap path (incl. flash
  swap)?
- Is the check `>=` (correct) or `>` (incorrect, allows zero-fee swap)?
- Does the check account for fee in the right direction? `k_new >=
  k_old + fee_contribution`.
- For Uniswap v2 forks: is the `balance0Adjusted * balance1Adjusted >=
  uint(_reserve0) * _reserve1 * (1000**2)` math correct? Some forks
  changed `1000` to `10000` without updating the multiplier.

## A2. First-LP share inflation (Uniswap v2 class)

Pattern: first mint computes shares as `sqrt(amount0 * amount1)`. v2
locks `MINIMUM_LIQUIDITY = 1000` shares to address(0) to prevent
inflation.

**Probe**:

- Does the fork still lock `MINIMUM_LIQUIDITY`?
- Some forks reduced it to `1` for "efficiency", reintroducing the
  attack.
- Custom hook-AMMs: does the hook bypass the lock?

If MINIMUM_LIQUIDITY is missing or insufficient, an attacker can:

1. Mint 1 share with 1 wei of each token.
2. Donate large amounts directly to the pair, inflating reserves.
3. Next LP's deposit rounds to 0 shares; their tokens enrich the
   attacker.

## A3. Direct-donation accounting drift

If the pool relies on `IERC20(token).balanceOf(address(this))` for
accounting (not internal `reserve` storage), an attacker can:

1. Send tokens directly to the pool (no LP mint).
2. The `balanceOf` view returns inflated value.
3. Functions using `balanceOf` mis-price swaps, mint LP shares, or
   compute fees.

**Probe**: every read of `balanceOf(address(this))` vs internal
`reserve` storage. Uniswap v2 uses both intentionally (`_update` syncs
storage), but `skim()` exists to drain donations. Forks may have removed
`skim()`.

## A4. Flash-loan callback reentrancy

AMMs that support flash swaps (Uniswap v2 `swap` with non-zero
`data.length`, v3 `flash()`, Balancer `flashLoan`) call user code
mid-swap. Reentrancy into the same or a different pool is the canonical
2020 exploit (e.g., bZx).

**Probe**:

- Is the swap function `nonReentrant`?
- If the user contract reenters another pool, can the state of pool A
  observe pool B's mid-flight reserves?
- Cross-pool reentrancy: in v3, can the callback reenter `swap()` on a
  different fee tier of the same pair before the original `swap`
  finalizes accounting?

## A5. JIT (just-in-time) liquidity sandwich

A searcher provides large concentrated liquidity right before a big
swap, captures most of the fee, then removes liquidity right after.
Liquidity providers earn fractions of what they would have.

This is a feature of v3 / v4, not necessarily a bug. But it becomes a
finding if:

- The protocol claims "no JIT possible" in its docs / NatSpec.
- The protocol's fee distribution to existing LPs is mathematically
  broken by JIT.
- The fork added an anti-JIT mechanism (mint cooldown, fee tax on
  short-duration LPs) that fails open.

**Probe**: any anti-JIT lock that the protocol relies on. Verify it
actually triggers.

## A6. Tick / price-range manipulation (v3 / v4)

Concentrated-liquidity pools track active tick. Edge cases:

- Tick spacing rounding: deposit at tick boundary may activate
  unexpected ranges.
- Tick underflow / overflow: `MIN_TICK` / `MAX_TICK` boundary checks.
- `tickBitmap` storage manipulation: forks that change tick spacing
  without updating bitmap word indices break swap traversal.
- Empty-ticks denial: if the active tick has zero liquidity, swaps
  cross it for free.

**Probe**: any change to v3's `TickMath`, `TickBitmap`, or
`SwapMath` libraries vs the upstream Uniswap v3 reference.

## A7. Hooks (Uniswap v4)

v4 introduces user-defined hooks at every pool lifecycle event
(`beforeSwap`, `afterSwap`, `beforeAddLiquidity`, etc.). Hooks can:

- Charge custom fees.
- Block transactions.
- Mint / burn tokens.
- Call back into the PoolManager.

Attack classes:

- **Hook impersonation**: contract checks `msg.sender == poolManager`
  but does not verify the pool / key, allowing arbitrary pool to
  trigger the hook's logic.
- **Reentrancy via hooks**: hook callbacks during swap can reenter the
  PoolManager. v4 uses a singleton with locks; verify the lock is
  active for every hook entry.
- **Malicious hook attached to a pool**: anyone can create a pool with
  any hook. Routing aggregators that auto-list new pools route user
  funds through malicious hooks.
- **Fee skim via hook**: hook collects "delta" from PoolManager beyond
  the user's intent.

**Probe**: every external hook entry point. Validate `msg.sender`,
poolKey, and the `BeforeSwapDelta` math.

## A8. Slippage / deadline missing

Swap functions should accept `amountOutMin` (or `amountInMax`) and
`deadline`. Missing either:

- No slippage: every swap is sandwichable.
- No deadline: tx can sit in mempool indefinitely, executed when price
  is unfavorable.

**Probe**: every public swap function. Both params present and
enforced. Note: Uniswap V2 router enforces these but pair contract
itself does not. Forks may expose the pair directly.

## A9. Curve-style stable-swap invariant

Curve's invariant: `An * sum(x) + D = An * D^n / prod(x) * D`. Solving
for D requires Newton iteration. Bugs:

- Newton iteration max-steps reached without convergence: function
  reverts, DoS on large pool imbalance.
- Newton iteration converges to a local min instead of the true root.
- Precision loss in `D` computation amplified by `A` (amplification
  coefficient) changes.
- A-ramp manipulation: admin ramps `A` over time. Attackers front-run
  the ramp to extract value.

**Probe**: any custom stable-swap math. Compare against Curve's
reference (or use Halmos to symbolically check D computation).

## A10. Balancer weighted-pool math

Weighted pools: `x^w_x * y^w_y = k`. Power computation uses fixed-point
log / exp. Bugs:

- `_compute` overflow at extreme weights (98 / 2).
- Precision loss for small swaps; attackers force rounding to favor
  them via many tiny swaps.
- Token weights settable by admin mid-pool: attackers front-run weight
  changes.

**Probe**: any deviation from Balancer's reference FixedPoint math.

## A11. LP token pricing (oracle consumer)

LP tokens priced via `(reserve0 * price0 + reserve1 * price1) /
totalSupply` are manipulable: a flash loan + in-pool swap inflates one
reserve, deflates the other, but the sum (in USD terms) increases due
to slippage, inflating the LP price.

**Probe**: any consumer using sum-of-reserves LP pricing. Replace with
fair-value:

- Uniswap v2: `2 * sqrt(reserve0 * reserve1) * sqrt(price0 * price1) /
  totalSupply`.
- Curve: `get_virtual_price() * price_of_underlying`.
- Balancer: BPT-specific fair-value oracle.

## A12. Read-only reentrancy on view functions

Curve and Balancer pools update internal state mid-callback. View
functions called during the callback return stale / inconsistent
state.

If a lending market reads `pool.get_virtual_price()` during a removal
callback, the value is post-burn-but-pre-supply-decrement. The
attacker borrows against the inflated reading.

**Probe**: every consumer of `get_virtual_price` /
`getRate` / similar. Does it ignore reentrancy on read?

Mitigations: Curve added `withdraw_admin_fees()` to refresh; consumers
should call before reading. Some Curve pools added an internal
`raw_call` reentrancy check.

## A13. Fee-on-transfer / rebasing token in pool

If the pool whitelists a FoT or rebasing token (USDT-style with future
fee toggle, stETH, Liquid-staked rebases):

- `transferFrom(user, pool, amount)` deposits less than `amount`.
- Subsequent k-check uses `amount`, fails.
- Or worse: succeeds but pool accounting is inflated.

Same direction for rebase: pool's `balanceOf` grows / shrinks without
LP mint / burn, breaking pro-rata accounting.

**Probe**: pool's `mint` / `swap` functions. Do they re-read
`balanceOf` post-transfer, or trust the requested amount?

## A14. Initialize-front-run for pool factories

Factory pattern: `createPool(tokenA, tokenB, fee)` deploys a new pool.
If `initialize(sqrtPriceX96)` is callable separately by anyone, the
first caller picks the price. They can:

1. Create pool.
2. Initialize at favorable price.
3. Add liquidity at favorable ratio.
4. Wait for honest users to swap into the bad price.

Uniswap v3 factory `createPool` calls `initialize` atomically. Forks
that decoupled them are vulnerable.

**Probe**: every `initialize` function on a pool. Is it gated to the
factory and called atomically?

## A15. Fee accrual / collect race

LP fees accrue per-position. If `collect()` and `swap()` race,
sandwicher can:

1. Swap to push price into a range that pays max fee.
2. Add liquidity at that tick.
3. Other swaps accrue fees to the new position.
4. Remove liquidity + collect.

This is the JIT pattern (A5) but specifically about fee distribution
math: does `collect` use the correct fee growth between the position's
add and remove blocks?

**Probe**: `FeeGrowthInside` math vs reference.

## A16. Router / aggregator integration risk

Routers (Uniswap UniversalRouter, 1inch, 0x) chain swaps across pools.
Issues:

- Permit2 integration: replay across pools if domain separator wrong.
- Wrapped-ETH dust trapped in router.
- Multi-hop slippage: per-hop slippage instead of end-to-end allows
  intermediate sandwiching.
- Approval race: user approves Permit2 → router → adapter → pool. Each
  hop is a trust boundary.

**Probe**: every router-to-pool boundary. Are permissions scoped
correctly?

## A17. Common AMM fork bugs (observed historically)

| Pattern | Source |
|---|---|
| Reentrancy via flash swap callback | bZx, Cream, Cheese Bank |
| LP donation share inflation | Multiple v2 forks |
| Sum-of-reserves LP pricing | Multiple lending markets accepting LP |
| Curve read-only reentrancy | Multiple lending markets |
| Missing slippage on hook bypass | Multiple v4 hook implementations |
| Wrong k-multiplier after fee tier change | Multiple v2 forks |
| Single-sided liquidity attack via uninit pool | Multiple v3 forks |
| Fee-on-transfer token whitelist breaks accounting | Multiple |
| Misconfigured oracle TWAP window | Multiple |
| Tick spacing change breaks bitmap traversal | At least 2 v3 forks |

## A18. Hyperliquid / non-standard EVM AMMs

For AMMs on non-standard EVM chains (Hyperliquid HyperEVM, Monad,
Berachain), check:

- Block time: short blocks compress TWAP windows.
- Native token semantics (HYPE has dual representation).
- Precompile-based oracle reads (HyperCore).

Pair with `oracle-integration.md` and `lending.md` L13 for HyperEVM
specifics.
