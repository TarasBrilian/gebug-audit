# Bridge / cross-chain attack vectors

Use this when the target is a cross-chain bridge or cross-chain
messaging integration: LayerZero (V1 / V2), Wormhole, Chainlink CCIP,
Axelar, Across, Hyperlane, Connext, custom optimistic / ZK bridges, or
any contract that consumes cross-chain messages.

Always pair with `oracle-integration.md` (oracle latency across chains)
and often `governance.md` (cross-chain governance amplifies
governance attacks).

Items below are organized by mechanism. Every candidate must include a
file:line citation per the rejection-only-with-proof rule in
`gebug-work/agents/vuln-hunter.md`.

## Reachability check before writing each candidate

For each candidate, answer in plain English:

1. Who can submit / relay messages? (anyone, trusted relayer, validator
   set, ZK prover, optimistic challenger)
2. What can the attacker control? (source chain, destination chain,
   payload, nonce, refund address, gas params)
3. What does the attacker want? (steal locked funds, mint unbacked
   tokens on destination, replay messages, censor, freeze)
4. What blocks the attack at the audit fork block?
5. Map to bounty Critical Impact line.

## B1. Message authenticity (the highest-value bug class)

Every cross-chain message has a verifier on the destination chain. The
verifier MUST prove:

- The message was emitted on the source chain.
- By the expected contract on the source chain.
- With the expected payload, nonce, and chainId.

**Probe**: every external entry point that consumes a cross-chain
message. Trace `msg.sender` back to the verifier. The verifier should
be a known bridge contract (LayerZero Endpoint, Wormhole Core, CCIP
Router) or a custom verifier with cryptographic proof.

Bugs:

- Verifier missing: any address can call the handler.
- Verifier address settable by admin without timelock: rug risk.
- Verifier check against `tx.origin` instead of `msg.sender`: bypass
  via call from a trusted contract.
- Verifier returns `true` on empty signature / zero address.

## B2. Source-chain spoofing

After authenticating the message came from a bridge, the handler MUST
also check the source chain identity:

- LayerZero: `srcChainId` and `srcAddress` (the trusted remote on the
  source chain).
- Wormhole: emitter chainId + emitter address.
- CCIP: source chain selector + sender.
- Axelar: source chain string + source address.

If the handler does NOT pin the trusted source, a sender on chain Y
can spoof a message that the handler treats as coming from chain X.

**Probe**: handler functions like `_lzReceive`, `_nonblockingLzReceive`,
`receiveWormholeMessages`, `_ccipReceive`, `executeWithToken`.

Verify the source pinning is set at deploy / config time and matches
the actual deployed bridge address on the source chain. Cross-reference
with the bridge's official deployment registry.

## B3. Replay across chains / contracts

A message signed (or proved) for chain A handler can be replayed to
chain B handler if:

- The message digest does not include `destChainId`.
- The handler does not track nonce per (srcChain, srcAddress) tuple.
- The handler accepts the same nonce twice.

**Probe**:

- LayerZero V2 introduced `Origin { srcEid, sender, nonce }`. Handlers
  must check uniqueness.
- Wormhole VAAs include `nonce` + `sequence`; ensure both are tracked.
- Custom bridges: the digest must commit to both chains and the
  handler must store consumed messages.

## B4. Nonce reuse / nonce-skipping

Some bridges allow out-of-order delivery. Issues:

- Handler that requires sequential nonces (1, 2, 3) blocks if message
  2 is lost: DoS via single dropped message.
- Handler that allows arbitrary nonces: replay an old high-nonce
  message after consuming a low-nonce one.

LayerZero V1 was strict-ordered (one channel per (src, dst, sender)
pair). V2 introduced unordered execution; verify the handler tracks
seen-set correctly.

## B5. Refund / gas-callback exploitation

Bridges that refund unused gas or expose a callback for failed
delivery:

- Refund address spoofable: attacker sets refund to victim, drains
  victim's wallet via the refund.
- Callback gas attached: attacker burns the relayer's gas by reverting
  in a heavy callback.
- Storefront-style retry: anyone can retry a failed message; if the
  retry charges fees to the original sender, attacker grief-loops.

**Probe**: refund address validation, callback gas limit, retry
permission gating.

## B6. Token-bridge mint / burn asymmetry

Lock-and-mint bridges:

- Source: `lock(amount)` → message → destination: `mint(amount, to)`.
- Source: `burn(amount)` ← message ← destination: `unlock(amount, to)`.

Invariant: `sum(locked on source) == sum(minted on destination) +
sum(in-flight)`.

Bugs:

- Mint without source lock proof (cf. Ronin, Nomad).
- Burn without destination unlock (funds destroyed).
- Mint to attacker via spoofed source message (B2).
- Double-lock / double-mint due to nonce reuse (B3).
- Decimals mismatch: source token has 6 decimals, destination minted
  with 18 decimals.

**Probe**: every mint path. Trace back to the cryptographic proof of a
source-chain lock event. If the proof is "the bridge said so"
(centralized), the bridge operator is the trust assumption.

## B7. Optimistic bridge challenge window

Optimistic bridges (Across, Connext) allow a challenge window before
finalization. Bugs:

- Challenge bond too low: attacker spam-challenges legit transfers.
- Challenge bond paid in volatile asset: bond value drops below cost
  of false claim.
- Window too short: honest challenger cannot react.
- Window does not cover L1 reorg: an L2 → L1 transfer finalized inside
  a reorg.

**Probe**: bond amount in USD vs max-possible-bridge value, challenge
window vs source-chain finality time.

## B8. ZK-bridge proof verification

ZK bridges verify SNARK / STARK proofs of source-chain state. Bugs:

- Proof verifier accepts proofs from any verifier key: attacker
  generates valid proofs for fake circuits.
- Verifier key updatable by admin without timelock: rug risk.
- Public inputs to the proof not bound to the message: attacker
  bind-and-substitute.
- Trusted setup: who participated? Compromised setup = forged proofs.

**Probe**: every call to `verifyProof`. Confirm the verifier key is
pinned and the public inputs include source chain, destination chain,
sender, recipient, amount, and nonce.

## B9. Multi-sig validator-set bridge

PoS / multi-sig bridges (older Wormhole, custom MPC):

- M-of-N threshold: 1 compromised key = ?. Verify threshold.
- Validator-set rotation: who can rotate? Timelock?
- Signature aggregation: BLS aggregation pitfalls (rogue-key attack
  without proof of possession).
- Slashing: are validators slashable for double-sign / liveness
  failure?

## B10. Cross-chain reentrancy

A message from chain A triggers a callback on chain B that emits another
message back to chain A:

A → bridge → B handler → callback → bridge → A handler → callback → ...

If A's handler is mid-state-update when B's callback message arrives,
state can be inconsistent. Most bridges use async delivery, so atomic
reentrancy is impossible. But asynchronous reentrancy across blocks is
possible if A's "send" tx and the relay of B's response land in a
sequence that A's handler did not expect.

**Probe**: any handler that re-emits a message during execution. Trace
the round-trip and verify state machines are independent per direction.

## B11. Gas / native-token wrapping

Native ETH / native gas wrapping at bridge boundary:

- Source: user sends ETH, bridge wraps to WETH, locks WETH.
- Destination: bridge unlocks WETH, unwraps to ETH, sends to user.

Bugs:

- Source wrapping reverts (e.g., WETH9 reverts on 0): grief by sending
  0 ETH, locking the bridge.
- Destination unwrap requires WETH balance the bridge may not have if
  prior unwraps drained it.
- Native token != WETH (chains where WETH is not the canonical
  wrapped representation).

## B12. Fee / relayer economics

Many bridges let anyone relay messages (decentralized relayers).
Economics:

- Relayer pays gas on destination, paid back in source-side fees.
- If destination gas spikes, relayer becomes unprofitable, messages
  back up.
- Attacker sends millions of low-fee messages to stuff relayer queue.

This is usually low-severity (DoS), but if the bridge handles time-sensitive
financial messages (liquidations, oracle updates), it escalates.

## B13. Chain-id / EIP-1271 wallet on cross-chain

If the bridge accepts cross-chain messages signed by EIP-1271 smart
wallets, the wallet's `isValidSignature` is evaluated on the
destination chain. The wallet contract may not exist on the destination
chain, or may behave differently.

**Probe**: any cross-chain operation that depends on
`isValidSignature`. The signer wallet must be replicated on both
chains, OR the bridge must use chain-A's verdict cryptographically.

## B14. Chain-reorg on source

If source chain has weak finality (Polygon PoS, BSC, L2s during
sequencer issues), the bridge may relay a message for a tx that gets
reorged out:

- Source: lock 100 ETH.
- Relayer: prove lock to destination, mint 100 tokens.
- Source: reorg, lock tx no longer exists.
- Result: 100 tokens minted on destination without backing.

**Probe**: what finality does the bridge wait for? Each chain has a
different "safe block depth". L2 → L1 must wait for the L2's
challenge period (Optimism: 7 days).

## B15. Token allowlist / configuration

Bridges that allow arbitrary tokens vs allowlisted:

- Arbitrary: attacker creates malicious token, bridges it, malicious
  token's `transfer` reenters bridge.
- Allowlisted: who adds tokens? Timelock?

For allowlisted tokens, decimals / wrapper address / metadata must
match on both chains. Mismatch = silent drift.

## B16. Common bridge bugs (observed historically)

| Pattern | Source |
|---|---|
| Mint without valid proof | Nomad (2022), $190M |
| Spoofed signer set | Ronin (2022), $625M |
| Verifier accepting empty signature | Multiple |
| Replay across chains (no chainId in digest) | Multiple |
| Approval drain via bridge gateway | PolyNetwork (2021), $610M |
| Storage-slot collision in proxy upgrade | Multiple |
| Decimals mismatch on token wrap | Multiple |
| Reentrancy via callback | Multiple |
| Relayer fee inflation grief | Multiple |
| Optimistic challenge window too short | Across early |

## B17. LayerZero V2-specific

V2 introduced `Endpoint`, `MessageLibrary`, `Executor`, `DVN`
(Decentralized Verifier Network). Per-message security is set per OApp:

- Required DVNs: app must list at least one. Default config = default
  set.
- Optional DVNs: any subset of optional must agree.
- Confirmations: source-chain block confirmations the DVN waits for.

**Probe**:

- OApp `setSendLibrary` / `setReceiveLibrary` / `setConfig` access
  control.
- `setEnforcedOptions` - does the app force a min gas on destination?
- DVN config: does the app rely on the default DVN set? Default could
  change.
- `lzCompose`: composable messages - does the OApp validate the source
  message before composing?

## B18. CCIP-specific

Chainlink CCIP uses Risk Management Network (RMN) plus DON for
signature aggregation. Each destination has token-pool contracts.

**Probe**:

- Token pool rate limits: per-pool cap on inflows / outflows.
- Manual execution: who can manually execute a stuck message?
- `_ccipReceive` permission: only the Router can call. Verify.
- Fee token: paid in LINK or native. Refund logic.

## B19. Wormhole-specific

Wormhole VAAs (Verified Action Approval) are signed by the Guardian
set.

**Probe**:

- `parseAndVerifyVM` checks Guardian signatures. Apps that bypass and
  call `parseVM` directly skip verification (the Wormhole 2022 bug).
- Guardian set index: VAAs reference a guardian set index; old indices
  are still valid. Replay of old VAAs?
- `consistencyLevel`: which value does the app pass? Lower = faster
  but less safe.

## B20. Axelar / Hyperlane

- Axelar: validator set rotation, cross-chain GMP (General Message
  Passing) call format, token-transfer vs general call paths.
- Hyperlane: ISM (Interchain Security Module) per-app. App can choose
  ISM; weak ISM = weak security.

**Probe**: which ISM does the OApp use? Default Hyperlane ISM has
trust assumptions; sovereign ISM lets apps roll their own.
