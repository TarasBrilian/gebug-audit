# Oracle integration catalog

Use this for any contract that reads an external price / rate / value via
Chainlink, Pyth, Redstone, Tellor, Uniswap V3 TWAP, Maverick, Curve, or a
custom on-chain oracle.

## O1. Chainlink staleness

```solidity
(uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound)
    = feed.latestRoundData();
```

Required checks (any missing = High):

- `answer > 0` (negative price catastrophically wrong)
- `updatedAt > 0` (round not started)
- `block.timestamp - updatedAt < HEARTBEAT * SAFETY` (within tolerance)
- `answeredInRound >= roundId` (M2 sequencer ECR-related; actually no longer
  required by Chainlink docs, but historically critical on L2s)

## O2. min / max answer bounds bypass

Some Chainlink feeds have `minAnswer` and `maxAnswer` clamps. During market
extremes (Luna, FTX collapse, depeg events), the reported price clamps to
the bound while the true price moves further.

**Probe**: does the consumer read `aggregator.minAnswer()` and
`maxAnswer()` and revert / refuse to act if `answer` is within EPSILON of
the bound?

## O3. L2 sequencer-uptime feed

On L2s (Arbitrum, Optimism, Base), the Chainlink sequencer-uptime feed
reports whether the L2 sequencer is healthy. If down:

- Old prices stale.
- Cannot submit new transactions to maintain positions.

Consumers MUST check `sequencer.latestRoundData().answer == 0` (up) AND
`block.timestamp - startedAt > GRACE_PERIOD` (recently recovered).

**Probe**: every L2-deployed consumer.

## O4. TWAP window size

Uniswap V3 / V2 TWAP price depends on window length:

- Window < ~5 blocks: manipulable by a flash-loan-funded swap.
- Window ~30 blocks: requires multi-block sustained pressure.
- Window ~3600 seconds: economically robust.

**Probe**: what TWAP window does the consumer use? At the target chain's
gas cost and liquidity depth, what does it cost to move TWAP by 10%?

## O5. Cross-venue oracle arbitrage

If the contract reads price from oracle A but settles trades on venue B,
and A != B, an attacker can:

1. Manipulate B's price (cheap on small venues).
2. Read manipulated price from A (which sources from B).
3. Exploit consumer using the corrupted A.

This is the canonical oracle attack class. Quantify cost-to-move on B vs
extracted value from consumer.

## O6. Per-asset oracle vs per-pool oracle

For LP tokens (Curve, Balancer): pricing via `(reserve0 + reserve1) /
totalSupply` is manipulable via flash-loan in-pool swap. Use
Curve / Balancer-native fair-value oracles (e.g., Curve's
`get_virtual_price`, Balancer's BPT pricing).

**Probe**: how does the consumer price LP shares? Direct sum-of-reserves is
broken; fair-value is safer.

## O7. Cross-chain oracle latency

Bridges that relay oracle data across chains introduce latency.
Manipulated source value can be acted on at destination before the
correction propagates.

**Probe**: what is the bridge SLA? Can a sandwiching window be opened?

## O8. Oracle aggregator vs single source

A contract reading a single oracle is at the mercy of that oracle's
failure modes. Aggregating N oracles with median / TWAP / fallback
reduces single-point risk.

**Probe**: how many independent sources are aggregated? What is the
median's failure mode if N-1 are wrong?

## O9. Custom on-chain oracle internals

Some protocols implement their own oracle (e.g., LST rate provider that
reads beacon-chain accumulated balance, validator effective balance,
etc.).

**Probe** every internal oracle:

- Where does data ultimately come from? Trust-traverse.
- Can any actor manipulate the data source?
- What is the heartbeat / freshness?
- Is there a circuit breaker on >X% per-update change?

## O10. Oracle in liquidation path

Loan-to-value computation uses oracle price. If oracle deviates from true
price by Y%:

- LTV is mis-reported by Y%.
- Positions that should be liquidatable aren't (bad debt accrues).
- Positions that shouldn't be aren't (innocent liquidation).

**Probe**: every liquidation function. What does a 10% oracle deviation
do? Is there a circuit breaker?

## O11. Same-block update / staleness window

If the oracle updates at block N and the consumer reads at block N+1:
fine. If consumer reads at block N (atomic with update), they get stale or
in-flight data.

**Probe**: any consumer that reads oracle in same block as the oracle's
underlying source moves (e.g., Uniswap TWAP and the consumer both reading
same block).

## O12. Sequence/freshness on Pyth / Redstone

Pyth: pull-based, caller submits price update. The caller controls WHICH
price update they push. They can choose to push an older valid update if
that benefits them.

Redstone: similar pull pattern.

**Probe**: does the consumer reject updates older than X seconds? Does it
verify update is the LATEST signed by the publisher?

## O13. Confidence interval (Pyth)

Pyth reports `(price, conf)`. High `conf` (uncertainty) means the price
is unreliable. Consumers that ignore `conf` and use only `price` are
trusting potentially-unreliable data during volatility spikes.

**Probe**: does the consumer reject reads where `conf / price > MAX_REL_CONF`?

## Reachability check

Same five-question check from `restaking.md` and `lst-lrt.md`.
