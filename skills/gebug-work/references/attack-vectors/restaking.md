# Restaking attack vectors (EigenLayer / Symbiotic / Karak / et al.)

Use this catalog when the target is a Liquid Restaking Token (LRT) protocol,
a restaking adapter, an EigenLayer integration contract, or any contract
that talks to a restaking platform (delegation, slashing, AVS rewards,
beacon-chain proofs).

Examples of in-scope targets: Swell rswETH stack, ether.fi weETH, Renzo
ezETH, KelpDAO rsETH, Eigenpie mLRT, Symbiotic vaults, Karak adapters.

Each item below MUST be probed against the assigned contract. If you reject
an item, do it per the rejection-only-with-proof rule in
`gebug-work/agents/vuln-hunter.md`.

## EigenLayer-specific attack classes

### R1. Validator pubkey front-running (Lido-class)

Mechanism: the staker submits a pubkey to the Beacon Chain DepositContract.
The withdrawal credentials are set on the FIRST deposit for that pubkey;
subsequent deposits add stake but do NOT change credentials.

An attacker who learns a Swell-bound pubkey (via the NodeOperatorRegistry,
public mempool, or pre-published roster) can pre-deposit 1 ETH (or any
amount) to that pubkey with attacker-controlled withdrawal credentials.
When the protocol's bot later submits 32 ETH with protocol credentials, the
deposit succeeds but credentials stay attacker's - protocol's 32 ETH
becomes attacker's restaking stake at exit.

On-chain mitigation: the contract reverts if
`depositRoot != DEPOSIT_CONTRACT.get_deposit_root()` at submission time.
This blocks intra-block frontrun but not multi-block - the bot must abandon
compromised pubkeys off-chain.

**Probe**: does the on-chain code's depositRoot check exist AND is it placed
BEFORE every iteration's `deposit` call (not just at the top of a batch
loop)?

### R2. EigenPod credential drift across upgrades

After EigenLayer M2 / M3 / M4 / Pectra migrations, the recommended
withdrawal credential format and pod-ownership model has changed. A
contract that hardcodes M1-era credentials (e.g., `0x00...address`) or
keeps an `eigenPodDeprecated` reference with no setter may route new
validators' beacon withdrawals to a pod that no longer participates in the
current restaking flow.

Funds are not LOST (pod is still owned by the contract) but may become
stuck until a proxy upgrade.

**Probe**: trace every site that constructs withdrawal credentials. Confirm
the credential target is currently owned by an active StakerProxy or
equivalent.

### R3. Slashing-share vs deposit-share desync (M4+ era)

EigenLayer M4 introduced `SlashingLib`, separating deposit shares from
withdrawable shares. When an operator is slashed, all delegators' shares
are scaled down. Contracts that cache share amounts (instead of querying
`StrategyManager.stakerStrategyShares(staker, strategy)` live) over-report
backing to LRT holders, inflating the exchange rate.

**Probe**: search for any cached `shares` storage on the LRT or its
adapters. The cache must be refreshed on every accounting-relevant event
(slash, withdrawal complete, deposit).

### R4. Operator delegation re-org race

When an EIGENLAYER_DELEGATOR role calls `delegateToBySignature` followed by
push to the local `operatorToStakers[op]` mapping, a state-after-call
pattern exists. If the M4+ DelegationManager ever introduces a callback
hook (e.g., AVS opt-in confirmation), reentrancy could push the staker
into the wrong operator's list.

**Probe**: read the deployed DelegationManager source. Confirm `delegateTo`
makes no external call to the staker address other than EIP-1271
isValidSignature staticcall.

### R5. EIP-1271 wrapper / unwrapper mismatch

LRT adapters that act as EIP-1271 signers for their owned StakerProxies
often wrap the input hash (e.g., `toEthSignedMessageHash`) before
`ECDSA.recover`. If the calling contract (DelegationManager,
RewardsCoordinator, etc.) feeds raw EIP-712 digests, the wrapped recover
expects an off-chain signer that knows to sign the wrapped form.

**Probe**: trace the exact bytes signed by adminSigner vs the bytes recovered
by isValidSignature. Mismatch = DoS at minimum, signer-spoof at worst.

### R6. AVS reward routing manipulation

EigenLayer's RewardsCoordinator (`0x7750d328b314EfFa365A0402CcfD489B80B0adda`
on mainnet) lets a staker designate a `claimer` who can pull rewards on
their behalf. If a role-holder (or staker contract logic) can rewrite
claimer to attacker, AVS rewards leak.

**Probe**: every `setClaimerFor` invocation: which role is required, can it
be triggered against a staker by anyone, does the role-holder revocation
restore funds.

### R7. Beacon-chain checkpoint proof replay or front-run

Pectra-era EigenLayer uses `verifyCheckpointProofs` to convert beacon
balance into withdrawable shares. The proof is signed by the beacon-chain
oracle.

Potential bug: the contract caller controls `oracleTimestamp` and a
`BalanceProof[]`. If the contract does not verify the timestamp is
monotonic vs the last checkpoint, an attacker may replay an older proof
to revert balance state.

**Probe**: read the verify path. Confirm monotonic-timestamp guard.

### R8. EigenPod recoverTokens scope (admin sweep vs principal)

EigenLayer's `IEigenPod.recoverTokens(tokens, amounts, recipient)` is
designed to rescue ERC20s accidentally sent to the pod. It does NOT touch
beacon-chain ETH balance or restaked shares.

A bug class: contracts that EXPOSE `recoverTokens` to an admin role but
incorrectly believe it sweeps principal too. Off-chain monitoring built on
this assumption can mis-report TVL.

**Probe**: trace every consumer of recoverTokens. Confirm intent matches
EigenLayer semantics.

### R9. Withdrawal queue strategy-list manipulation

`DelegationManager.queueWithdrawals(QueuedWithdrawalParams[])` accepts
arbitrary strategy arrays. If the caller is `EIGENLAYER_WITHDRAWALS` role
on the LRT adapter, the role-holder can queue withdrawals against
strategies the LRT has zero shares in (no-op) or against the beacon
strategy (drain native ETH).

Centralization, but probe: can the role-holder's queue-withdrawal pull
funds out to themselves, or does EigenLayer enforce `withdrawer == msg.sender`
limiting funds to the StakerProxy?

### R10. Slashing-mode opt-in bypass

EigenLayer M4 introduces AVS opt-in via the OperatorAVSRegistration
mechanism. LRT operators that auto-opt-in to all AVSs (rather than a
whitelisted subset) expose stake to AVS slashing. If a malicious AVS can
trigger slashing, LRT exchange rate drops.

**Probe**: does the LRT adapter or operator config restrict AVS opt-in to
a vetted list?

## LRT-specific attack classes

### R11. Exchange-rate manipulation via unscoped LST deposits

LRT adapters that accept multiple LSTs (depositLST(token, amount, minOut))
use a per-token rate provider. If the rate provider reads from a
manipulable on-chain source (spot AMM price, single-block oracle), an
attacker can flash-loan the LST, push the source price, deposit at
inflated rate, then unwind.

**Probe**: trace every `ILstRateProvider.getRate` impl. If the source is a
TWAP with sufficient window, safer. If spot, exploitable.

### R12. depositLST uses requested amount vs received amount

`safeTransferFrom(_amount)` then `_amount * rate / 1e18` mint trigger.
For fee-on-transfer or rebasing LSTs, received != requested. Even if no
such LST is currently whitelisted, the bug exists in the code and ANY
future whitelist triggers it.

**Probe**: does the contract compute `balanceOf(this)` delta instead of
trusting the requested amount?

### R13. Rebasing LST snapshot drift

stETH and similar rebase up daily. If the LRT adapter accepts stETH at
deposit (mint X rswETH for Y stETH at today's rate), and rebase increases
the held stETH balance, the protocol pockets the rebase yield. This
**favors the protocol but disadvantages depositor IF** the rate provider
fails to track stETH's compounded value.

**Probe**: does the rate provider for rebasing LSTs use the underlying
exchange rate (stETH per ETH), not the bare token amount?

### R14. Mint inflation via first-depositor

ERC4626-style LRTs that mint shares = `assets * totalShares / totalAssets`
are vulnerable to the first-depositor attack:

1. Attacker deposits 1 wei, mints 1 share (totalShares=1, totalAssets=1).
2. Attacker donates large amount X directly to the vault, inflating
   totalAssets to 1+X without changing totalShares.
3. Victim deposits Y < X. `shares = Y * 1 / (1+X) = 0` (rounding). Victim
   gets 0 shares, attacker holds 100% of value.

**Probe**: does the vault mint a non-redeemable `INITIAL_LOCKED_SHARES`
batch (Uniswap V2 pattern) or reject the first deposit pattern? Does the
share computation use `mulDivUp` for the unfavorable direction?

### R15. ERC4626 donation share inflation

Same class as R14 but on subsequent deposits. If totalShares is always
incremented by `assets * totalShares / totalAssets` (down-rounded), an
attacker who donates between user's `approve` and `deposit` calls can
cause user to receive fewer shares than expected.

**Probe**: does deposit honor a `minSharesOut` slippage param?

### R16. Withdrawal accounting drift on slash event

When EigenLayer slashes, all deposit shares scale by the slashing factor.
The LRT's `totalAssets()` must drop accordingly. If the LRT caches
totalAssets or uses a delayed update, attackers can:

1. See slash event in mempool.
2. Frontrun by depositing at the pre-slash exchange rate.
3. After slash applies, totalAssets drops, but their newly-minted shares
   are accounted at the old rate.

**Probe**: is `totalAssets()` computed live from on-chain
`StrategyManager.shares()` calls, or cached?

### R17. Withdrawal-queue griefing (Renzo-class)

LRTs with a centralized withdrawal queue can be griefed if:

- Anyone can enqueue a withdrawal of size N.
- The queue is FIFO and the protocol must service queue before new
  deposits can be honored.

An attacker can flood the queue with self-withdraw requests, locking real
users behind their fake exits.

**Probe**: is there a per-user rate limit, queue depth cap, or anti-spam
mechanism?

## Cross-protocol composition risks

### R18. Composability with EigenLayer Slasher upgrade

If the LRT adapter assumes a specific Slasher contract address or
interface, an EigenLayer upgrade that changes Slasher semantics can break
the LRT's accounting silently.

**Probe**: any hardcoded EigenLayer contract addresses in the LRT? Any
assumed return-value patterns?

### R19. Bridge interaction (LRT on L2)

LRTs that bridge to L2s (rswETH on Swell L2, ezETH on Mode, etc.) carry a
representation layer. The L1 LRT can be slashed while the L2
representation continues to circulate at the pre-slash rate, creating an
arbitrage where attackers buy depressed L1 and sell on L2.

This is largely off-chain economic but the bridge contract may have a
peg-check function that misroutes.

**Probe**: does the bridge expose a `rate()` view that the L2 trusts? How
often is it updated?

## Reachability check before writing each candidate

For each candidate, answer in plain English:

1. Who calls the entry point? (anyone, role X, only address Y)
2. What CAN the attacker control? (calldata, msg.value, msg.sender if Y is
   contract attacker controls)
3. What does the attacker WANT? (drain N ETH, mint M shares for free, DoS
   victim withdrawals)
4. What blocks them today? (cite the file:line of the check; if no check,
   no block)
5. Is the bounty impact line that maps cleanly satisfied?

If 1-4 produce a non-trivial story, the candidate is real - pass to PoC,
let the test be the judge.
