# Lending / borrowing protocol attack vectors

Use this when the target is a lending protocol: Aave v2/v3, Compound v2/v3,
Morpho Blue / MetaMorpho, Spark, Maker, Radiant, BENQI, Sonne, Sturdy,
Silo, Euler v2, Fluid, or any fork derivative (e.g., HyperLend).

Always pair with `oracle-integration.md` since lending protocols are
oracle consumers.

Items below are organized by mechanism. Every candidate must include a
file:line citation per the rejection-only-with-proof rule in
`gebug-work/agents/vuln-hunter.md`.

## Reachability check before writing each candidate

For each candidate, answer in plain English:

1. Who can call? (anyone, supplier, borrower, liquidator, owner)
2. What can the attacker control? (asset, amount, on-behalf-of address,
   oracle source, IRM parameters, flash-loan callback data)
3. What does the attacker want? (drain reserves, freeze withdrawals, get
   collateral without repaying, inflate hToken/aToken share price for
   later exit, force bad debt to insurance fund)
4. What blocks the attack at the audit fork block?
5. Map to bounty Critical Impact line.

## L1. Aave-fork specific class: hToken / aToken share donation

### L1.1 First-supplier hToken inflation

Pattern: `mint = assets * totalSupply / totalAssets`. If `totalSupply == 1`
after first supply, an attacker can donate underlying directly to the
aToken contract, inflating `totalAssets`. Next supplier mints zero shares.

Aave v3.1 mitigation: the protocol pre-mints a virtual supply.
Verification path: see `MintToTreasury` in `PoolLogic.sol`, the
`_minBorrowAmount` floor, and the `accruedToTreasury` mechanism.

**Probe**: confirm the virtual-supply / minted-on-init pattern is present.
For forks, check the deployment script primed the floor.

### L1.2 stataToken (ERC4626 wrapper) donation

stataTokenV2 is the Aave v3.1 ERC4626 wrapper around aTokens. Apply
ERC4626 donation analysis: shares = `assets * totalShares / totalAssets`,
attacker donates between approve+deposit calls to skim shares.

### L1.3 hToken cross-pool donation

If multiple isolated pools use the same hToken type for the same underlying,
a donation in pool A could affect accounting in pool B if hToken is shared.

## L2. Liquidation mechanics

### L2.1 Liquidation incentive arbitrage

Liquidator pays debt + receives collateral + bonus. If `bonus * debt > debt`,
the math holds. But if the COLLATERAL is mis-priced or the DEBT is
mis-priced relative to live market, the liquidator extracts more than
intended.

**Probe**:
- What price oracle is used for liquidation? Same as for borrow LTV?
- Is there a circuit breaker on liquidation incentive size?
- Can a self-liquidation cycle profit (deposit, borrow against, frontrun
  oracle update, liquidate yourself for bonus)?

### L2.2 Liquidation race (sandwich on oracle update)

Borrower's health factor depends on oracle. If oracle updates ON-CHAIN, an
MEV bot can sandwich: liquidate immediately after a price drop is posted,
denying the borrower a chance to repay.

Aave v3 design relies on Chainlink heartbeat. Aave v3.2 adds the
`liquidationGracePeriod` concept for emergency pauses, but normal
operation has no grace.

**Probe**:
- After oracle update, can the SAME tx call `liquidationCall`?
- Sequencer-uptime feed required on L2? Missing check → liquidations
  during downtime.

### L2.3 Bad debt / dust liquidation DoS

If a position is too small to be profitable to liquidate (gas > bonus),
it sits as bad debt until oracle moves enough to make profitable.

Aave v3.1 added `closeFactor` ramping for under-water positions to
incentivize partial liquidations.

**Probe**:
- For small markets, is there a dust threshold that prevents micro-positions?
- Bad-debt socialization: who pays? Insurance? Suppliers? If suppliers,
  is it pro-rata?

### L2.4 Liquidation while paused

`liquidationCall` should remain callable when supply/borrow are paused
(emergency situation). Some forks accidentally include it in the pause
modifier.

**Probe**: `liquidationCall` modifiers; does it respect the freeze flag?

### L2.5 Self-liquidation profit

Pattern: attacker supplies V, borrows V * LTV, accumulates positive
interest faster than supplier rate (impossible normally - borrow rate
> supplier rate by reserve factor). Or: position becomes liquidatable
due to oracle move, attacker self-liquidates to capture the bonus.

Aave fork mitigation: usually allowed but bonus < cost of self-liquidation
under normal conditions. If a market has extreme bonus, profitable.

**Probe**: bonus % on each market. Is any > 15%?

## L3. Interest rate model (IRM)

### L3.1 IRM utilization curve manipulation

Kinked IRM (Aave v3, Compound v3): linear ramp up to `OPTIMAL_USAGE_RATIO`,
then steep ramp. If attacker pushes utilization just past the kink, rates
spike. Suppliers earn briefly, borrowers pay more.

**Probe**:
- Can attacker flash-loan to push utilization past kink, profit, unwind?
- Reserve factor: is the spike captured by protocol or by suppliers?
- IRM update authority: who controls slopes?

### L3.2 IRM precision loss

Rate accrued = rate * dt. dt in seconds, rate in WAD. If accrual happens
infrequently (every N transactions), interim precision loss can favor or
disadvantage one side.

Aave's `_updateState` calls `MathUtils.calculateLinearInterest`. Probe its
rounding direction.

### L3.3 Per-second compounding vs per-block

Aave v3 uses per-second compounding via Taylor approximation:
`compoundedRate = 1 + r*t + (r*t)^2/2 + (r*t)^3/6`. Compounding error
accumulates for high rates over long t. Check for overflow at extreme
rates.

### L3.4 Default IRM swap by admin

If admin can hot-swap the IRM contract on a market, attacker pre-positions
borrows before the swap (low rates), benefits after (still low rates
mid-tx until next update).

**Probe**: who can call `setReserveInterestRateStrategy`? Timelocked?

## L4. Oracle-in-lending

(Cross-load `oracle-integration.md`.)

### L4.1 Single oracle source per asset

Aave uses one Chainlink feed per asset (plus a fallback in some forks). If
that feed depegs or freezes, liquidations cascade.

**Probe**: per-asset fallback oracle? L2 sequencer check?

### L4.2 LP token pricing

Aave avoids LP collateral by default. Forks that add LP collateral often
use bad pricing (sum-of-reserves manipulable via flash).

**Probe**: every collateral asset. Is it an LP? If yes, fair-value pricing?

### L4.3 LST / LRT collateral pricing

If wstETH / weETH / rsETH is collateral, its price is usually computed
as `lst_token_price = lst_per_eth * eth_price`. Stale `lst_per_eth`
favors one side. Check refresh cadence.

**Probe**: rate provider for each LST. Heartbeat? Staleness check on caller
side?

### L4.4 Custom oracle adapter

Forks often add adapters: `RatioAdapter`, `ERC4626Adapter`,
`StHypeAdapter`, etc. Each is a new attack surface.

**Probe**: every adapter - check inputs, decimals, rounding, sanity
bounds, who can update the source, what happens if source returns 0 /
negative / stale / inf.

### L4.5 PT (Pendle) token pricing as collateral

PT tokens trade at discount to underlying. If priced as underlying,
attacker borrows against PT, lets time pass, value converges, attacker
profits via the over-collateralization gap.

Aave's PT-pricing oracle compensates: prices PT at the implied yield
discount. Probe its implementation if listed.

### L4.6 Stable price oracles for "1:1 pegged" assets

Some forks hardcode `USDC == $1`, `WETH == ETH_PRICE`, etc. If asset
depegs, no protection. Aave v3.2 added a "depeg mode" for collateral
that drops to 0 LTV on depeg.

**Probe**: any hardcoded 1:1 oracle?

## L5. Borrow / supply mechanics

### L5.1 Borrow on-behalf-of bypass

`borrow(asset, amount, ..., onBehalfOf)`. Requires `onBehalfOf` to have
delegated credit. If delegation check is missing, attacker borrows in
victim's name.

Aave v3 has `BORROWING_CREDIT_DELEGATION` mechanism via `borrowAllowance`.
Probe its enforcement.

### L5.2 Supply on-behalf-of side effects

`supply(asset, amount, onBehalfOf, ...)` mints aTokens to `onBehalfOf`.
Attacker can grief by supplying tiny amounts to victim → forces victim
into a state they didn't intend (e.g., e-mode auto-entry).

Aave v3 mitigation: no automatic e-mode entry on supply. Verify.

### L5.3 Repay-on-behalf with stuck collateral

If a borrower has stuck collateral (paused asset, frozen), can someone
repay their debt and unstick them? Or is the repay locked too?

### L5.4 Flash loan + supply + borrow + repay cycle

The canonical drain pattern: flash loan, supply as collateral, borrow at
inflated LTV, repay flash. If LTV math has any window where collateral is
counted before underlying is committed, drainage.

Aave's `executeFlashLoanSimple` uses CEI. Verify.

### L5.5 Withdraw to address(0)

`withdraw(asset, amount, to)`. If `to == address(0)`, tokens are burned.
Some forks silently allow this; the user's aTokens are gone but underlying
is locked.

**Probe**: zero-address check on `to`?

### L5.6 Atomic supply + withdraw flash

If `supply` and `withdraw` can both happen atomically (no time lock), and
`supply` accrues some hToken rewards / boost, attacker can supply, claim,
withdraw, repeat to drain the reward stream.

## L6. Aave v3-specific mechanisms

### L6.1 Isolation mode

Isolated assets have a debt ceiling. User in isolation mode can ONLY use
ONE isolated asset as collateral. Probe edge cases:

- Can user exit isolation mode while having debt against the isolated
  asset?
- If debt ceiling is decreased AFTER isolation enable, what happens?
- Liquidation of isolation-mode position: respects debt ceiling?

### L6.2 E-mode (Efficiency mode)

Allows higher LTV for correlated assets (e.g., ETH + LST). Probe:

- Switching e-mode while having debt: enforced LTV check?
- Asset added to e-mode category after user opted in: does user get the
  boost retroactively (good) or are they locked out (bad)?
- E-mode oracle override: some categories use a different oracle. If the
  category oracle disagrees with the main oracle, which wins?

### L6.3 Siloed borrowing (Aave v3.1)

Siloed asset can only be borrowed if user has NO OTHER debt. Mainnet
example: BAL borrows. Probe:

- Can user repay-and-re-borrow trick to add other debt while siloed asset
  is borrowed?
- What happens at liquidation when siloed asset's market is paused?

### L6.4 Supply cap and borrow cap

Per-asset caps. Probe:

- Cap calculation includes accrued interest? If excluded, supply cap can
  be bypassed by interest accrual.
- Cap reduction by admin: existing positions allowed to remain or forced
  liquidation?

### L6.5 LTV-to-zero freeze (Aave v3.2 "freeze" feature)

If admin sets LTV to 0, existing positions can't be liquidated for LTV
breach (LTV = 0 means anything is healthy or anything is unhealthy
depending on direction). Aave v3.2 added a specific freeze flag.

**Probe**: when LTV is 0, liquidation logic - does it default to "always
liquidatable" or "never liquidatable"?

## L7. Compound v3 (Comet) specific

(Skip if Aave-style fork. Apply to actual Compound v3 forks.)

### L7.1 Single-borrowable-asset model

Comet only lets users borrow ONE base asset per market. Multiple
collaterals supported. Probe:

- Reward accrual: must accrue before any position change.
- Liquidation: absorbs entire position, doesn't partially liquidate.
  Race conditions during absorption.

### L7.2 Reward accrual precision

`baseTrackingSupplyIndex` and `baseTrackingBorrowIndex` accrue rewards.
Precision loss favors / disfavors. Probe rounding.

## L8. Morpho Blue / MetaMorpho specific

### L8.1 IRM is per-market

Morpho Blue uses an immutable per-market IRM contract. Once set, can't
change. Probe: market creation params - was the IRM audited? Did the
creator use a known-good template or custom IRM?

### L8.2 MetaMorpho vault re-allocation

MetaMorpho vault allocates supply across underlying markets. Reallocation
is permissioned (allocator role).

- Can a malicious allocator drain by depositing into a malicious Blue
  market?
- Vault donation attack: send underlying directly to vault - same as L1.1.

### L8.3 Bad-debt socialization

Morpho Blue has no liquidation incentive cap. If position becomes
liquidatable mid-block, anyone can liquidate. After bad debt, suppliers
in that market lose pro-rata. MetaMorpho aggregates across markets, so
suppliers in vault eat losses from ANY underlying market.

## L9. Maker / Spark specific

(Skip if not relevant.)

- DSR (Dai savings rate) adjustments: precision, accrual cadence.
- PSM (peg stability module): fee changes, reserve depletion.
- Sky / USDS: redemption ratios, USDS / sUSDS conversion.

## L10. Flash-loan composition

### L10.1 Flash loan + governance

Flash-loan governance tokens, vote yes on malicious proposal, repay.
Most protocols mitigate via snapshot-based voting (timelock between
proposal and snapshot).

**Probe**: how does the protocol's governance handle flash-loaned voting
power?

### L10.2 Flash loan + oracle manipulation

Flash loan, swap to move spot price, observe stale oracle, exploit
position, unwind. Standard cross-venue manipulation.

### L10.3 Flash loan + reentrancy

Most flash loans use callback. If callback runs WHILE protocol state is
mid-update, attacker can reenter to drain.

Aave v3 uses CEI in flash-loan execution. Verify.

## L11. Pause / emergency mechanisms

### L11.1 Selective pause

`pause()` may freeze deposits, borrows, or both. Liquidations should
remain active under most pause states.

**Probe**: pause matrix - which actions are blocked under which pause?

### L11.2 Emergency oracle override

Some forks have a "freeze price" mechanism. If admin sets a fixed price,
LTV calculation against that fixed price may diverge from market - used
intentionally for depeg events.

**Probe**: how is the override implemented? Can it freeze at the wrong
value?

## L12. Common Aave v3 fork bugs (observed historically)

| Pattern | Source |
|---|---|
| Missing sequencer-uptime check on L2 deployment | Multiple forks |
| Oracle adapter returning value in wrong decimals | Multiple |
| Custom IRM with unbounded utilization | At least 2 forks |
| Wrong reserve factor on a single market | Multiple |
| eMode category misconfigured (wrong assets grouped) | Multiple |
| Supply/borrow caps not enforced during interest accrual | Older forks |
| LP token collateral with sum-of-reserves pricing | Multiple |
| LST without rate provider, hardcoded 1:1 | Some |
| Liquidation incentive too high → self-liquidation profit | 1 fork |
| Wrong decimals in non-standard ERC20 listing (e.g., 18 vs 6) | Multiple |
| Pricing of PT (Pendle) tokens at underlying value | Multiple |
| Asset listing with wrong configuration (LTV > liqThreshold) | Listing bug |

## L13. Hyperliquid / HyperEVM-specific

(Apply to HyperLend and other Hyperliquid-deployed protocols.)

### L13.1 HyperCore precompile access from HyperEVM

HyperEVM contracts can read HyperCore state via precompiles. Oracle
adapters that pull from HyperCore (spot prices, perp marks) need to
verify the precompile output isn't spoofable or stale.

**Probe**: which adapter calls which precompile? What sanity bounds?

### L13.2 HYPE native token semantics

HYPE has both HyperCore (account-balance) and HyperEVM (ERC20-like)
representations. Bridging between the two has timing semantics. If a
collateral asset uses HYPE, race conditions across the two representations
matter.

### L13.3 stHYPE / kHYPE / wHLP

Staked-HYPE derivatives. New, less-audited tokens. Apply LST/LRT attack
classes from `lst-lrt.md` and `restaking.md`.

### L13.4 Hyperliquid block timing

Hyperliquid produces blocks at sub-second cadence. Per-block accrual
math may underflow / overflow when assuming 12s Ethereum blocks. Aave's
`MathUtils.calculateLinearInterest` uses seconds, so OK. But if the fork
added block-based accrual anywhere, check.

### L13.5 Permit2 / native HYPE in supply/borrow

Forks may add Permit2 to bypass `approve` UX. Check Permit2 integration
for usual permit-replay issues (`oracle-integration.md` L7).
