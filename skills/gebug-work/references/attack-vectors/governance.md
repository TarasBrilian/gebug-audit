# Governance attack vectors

Use this when the target is a governance system: Compound Governor Bravo
forks, OpenZeppelin Governor, Aragon, Optimism Governor, Snapshot +
SafeSnap, custom timelock-based governance, or any on-chain voting
mechanism that controls protocol parameters or treasury funds.

Items below are organized by mechanism. Every candidate must include a
file:line citation per the rejection-only-with-proof rule in
`gebug-work/agents/vuln-hunter.md`.

## Reachability check before writing each candidate

For each candidate, answer in plain English:

1. Who can propose? Who can vote? Who can execute?
2. What can the attacker control? (proposal calldata, voting power
   acquisition path, timing)
3. What does the attacker want? (drain treasury, change critical
   param, mint governance tokens, freeze the protocol, censor honest
   proposals)
4. What blocks the attack at the audit fork block? (timelock, quorum,
   guardian veto, snapshot delay)
5. Map to bounty Critical Impact line.

## G1. Flash-loan vote borrowing

The canonical governance exploit: borrow N tokens via flash loan within
one tx, snapshot voting power, vote, return tokens. Cost: flash-loan
fee. Reward: control over the protocol.

Mitigations:

- **Snapshot at proposal creation**: only addresses holding tokens at
  block N can vote on proposal P. Flash loan in block M > N is
  useless.
- **Snapshot at vote start, with delay**: voting starts at block N +
  delay. Attacker would need to hold tokens at block N, before
  proposal is announced (impossible without front-running).
- **Per-block snapshot using checkpoints**: ERC20Votes pattern.

**Probe**:

- Does the governor use `getPastVotes(account, blockNumber)` or
  `balanceOf(account)`? Latter = vulnerable.
- Is the snapshot block at proposal creation or at vote start?
- If at vote start with delay, is the delay > flash-loan execution
  time (i.e., > 1 block)?

## G2. Vote delegation manipulation

ERC20Votes uses `delegate()`. Vote power = sum of delegations to an
address.

Bugs:

- `_moveVotingPower` not called on transfer: voting power desyncs from
  balances.
- Delegation does not auto-update when delegator's balance changes.
  ERC20Votes handles this via `_update`. Forks that override `_update`
  without calling super break it.
- Delegate-to-self required to vote: users who hold but did not
  delegate cannot vote. Some governors require explicit self-delegate;
  others auto.

**Probe**: `delegate`, `delegateBySig`, `_moveVotingPower`,
`getPastVotes`. Compare against OpenZeppelin reference. Custom
implementations are a common source of bugs.

## G3. Proposal cancellation race

After a proposal is queued in the timelock but before execution:

- Can anyone cancel?
- Can the proposer cancel?
- Can a guardian veto?

If the proposer can cancel anytime, they can use it as a coordination
mechanism: queue a malicious proposal, wait for the community to react
(maybe queue a defensive proposal), cancel and re-queue at a worse
time.

**Probe**: cancel function gating, guardian role permissions.

## G4. Timelock bypass via delegatecall

Timelock pattern: proposal is queued, must wait `delay`, then executed.
The execution is `call(target, calldata)`.

If the timelock contract has a `delegatecall` path (e.g., for upgrades
to itself, multicall), a proposal can delegatecall to arbitrary code,
changing the timelock's own state, including:

- Reducing `delay` to 0.
- Removing the admin role.
- Skipping queue + executing immediately.

**Probe**: any `delegatecall` in the timelock or related multicall
wrappers.

## G5. Proposal description / hash collision

Some governors hash `keccak256(targets, values, calldatas,
descriptionHash)` to identify proposals. If `description` is not
canonical (e.g., trailing whitespace ignored), two proposals can have
the same hash, leading to confusing states.

OpenZeppelin uses `keccak256(bytes(description))` - exact match
required. Forks may have replaced this.

**Probe**: proposal-ID derivation. Test that whitespace-only differences
produce different IDs.

## G6. Multiple-proposal MEV

If a single voter can cast votes across multiple proposals in one tx,
and the proposals interact (one changes a param the other reads), MEV
bots can sandwich the proposal execution.

**Probe**: are proposals strictly serialized in execution, or can they
land in any order?

## G7. Quorum manipulation

Quorum = minimum vote power needed for a proposal to pass.

- **Snapshot quorum**: quorum = `totalSupply() * quorumNumerator /
  quorumDenominator` at proposal creation. If `totalSupply` is at a
  local minimum (right after a burn), quorum is low.
- **Hardcoded quorum**: easier to game; if voter participation drops,
  small groups can pass proposals.
- **Quorum reduction proposal**: a proposal that reduces quorum can
  itself pass with low quorum if old quorum was hit by attacker.

**Probe**: how is quorum computed? Is it dependent on a manipulable
`totalSupply`?

## G8. Vote token mint / burn via governance

If the governance can mint or burn the governance token, two bugs:

- Mint-to-self proposal: attacker accumulates voting power
  retroactively.
- Burn-victim proposal: attacker reduces specific holders' voting
  power.

Most governance setups put the token's mint authority in the same
timelock that the token controls, so this requires passing a proposal
first. But:

- If quorum is low + token holders are inactive, a 1% holder can pass
  it.
- If the protocol has a "treasury mint" function gated by governance,
  the attacker pumps treasury to itself.

**Probe**: every callable target the governance has authority over.
What params can be mutated?

## G9. Snapshot.org / SafeSnap off-chain voting

Hybrid governance: voting off-chain on Snapshot, on-chain execution
via SafeSnap (Reality.eth + Safe).

Bugs:

- Reality.eth question text differs from the Snapshot proposal -
  oracle reports YES on a different question.
- Bond amount too low: attacker challenges legitimate answers.
- Cooldown / challenge window short: not enough time to dispute.
- Snapshot strategy mis-configured: voting power computed via
  off-chain script that the team controls; team can rewrite history.

**Probe**: the Reality.eth question template, bond denomination, the
Snapshot space's "strategies" field.

## G10. Cross-chain governance amplification

Governance on chain A executes via bridges on chains B, C, D. Bugs:

- Replay across chains (cf. `bridge.md` B3).
- Partial execution: proposal succeeds on B, fails on C, leaves
  protocol in inconsistent multi-chain state.
- Bridge takeover: if attacker controls the bridge, they fabricate
  governance messages.

**Probe**: the cross-chain governance executor. Is it a wrapped
proposal type, or arbitrary calldata bridged?

## G11. Veto / guardian role

Many governance setups have a guardian role:

- Can veto malicious proposals.
- Can pause emergency actions.

Bugs:

- Guardian has more power than advertised: e.g., can also propose
  without governance, can drain treasury directly.
- Guardian is single EOA: single point of failure.
- Guardian role removable by governance: malicious proposal removes
  guardian, then drains.

**Probe**: enumerate guardian's permissions. List every function it
can call.

## G12. Proposal threshold (anti-spam)

Some governors require the proposer to hold N% of supply before they
can propose. Bugs:

- Threshold too low: anyone can spam proposals, drowning real
  proposals.
- Threshold based on `balanceOf` (manipulable) instead of
  `getPastVotes`.
- Threshold check bypassed via `proposeBySig` if the signature path
  does not re-check.

## G13. Vote-buying / bribery markets

Not necessarily a bug, but worth noting:

- Vote-escrow tokens (veCRV-style): voting power tied to lock period.
  Bribes pay LPs to vote a certain way.
- If the protocol claims "no bribery possible" but uses standard
  ve-tokens, the claim is false.

## G14. Compound Governor Bravo specific

Compound's Governor Bravo (and its forks: Uniswap, Aave, etc.):

- `initialProposalId`: legacy from Alpha. Upgrades broke when this
  was mis-initialized.
- `_initiate`: callable only once; if a fork omits the gate, can be
  reinitialized.
- `castVoteWithReason`: emits reason string; attackers can encode
  arbitrary data here (low severity, but indexers may render HTML).
- `state(uint proposalId)`: returns enum. If a new state is added in
  a fork without updating the enum's downstream consumers, off-chain
  indexers misreport.

## G15. OpenZeppelin Governor specific

OZ Governor uses module composition:

- `GovernorVotes`: counts voting power via ERC20Votes / ERC721Votes.
- `GovernorTimelockControl`: queues to a TimelockController.
- `GovernorCountingSimple`: simple For / Against / Abstain.

Forks that customize:

- `GovernorVotesQuorumFraction`: quorum as fraction of votes. Bugs in
  the quorum-numerator setter.
- `GovernorPreventLateQuorum`: voting period extends if quorum hit
  late. Bugs in extension math.

**Probe**: every override of `_quorumReached`, `_voteSucceeded`,
`_castVote`. Compare against the OZ reference.

## G16. Common governance bugs (observed historically)

| Pattern | Source |
|---|---|
| Flash-loan vote borrowing | Beanstalk (2022), $182M |
| Timelock bypass via self-call delegatecall | Multiple forks |
| Proposal hash collision via description format | At least 1 fork |
| Guardian role with more power than documented | Multiple |
| Cross-chain governance message spoofing | Multiple bridge-governance |
| Quorum computation off `balanceOf` | Multiple forks |
| Vote double-counting on delegation update | Multiple custom governors |
| Snapshot of voting power at execute time | Multiple early forks |

## G17. Treasury-control specifics

If governance controls a treasury (Compound, Uniswap, Aave):

- What assets does the treasury hold? Liquid (drainable in one tx) or
  illiquid (would require sale)?
- What is the maximum drain rate? Per-block / per-day cap?
- Is the treasury a Safe multisig backstop in addition to the
  governor?

A successful governance attack on a $1B treasury is the highest-impact
Web3 attack class. Map every candidate to "drain X% of treasury in one
proposal".

## G18. Veto-permissionless time-locks

Some setups use a "permissionless timelock": anyone can queue any
calldata, and a guardian must veto within `delay` or the call goes
through.

This inverts the trust model: attacker just keeps queuing malicious
proposals; the guardian must be 24/7 active.

**Probe**: is the timelock permissionless? Veto mechanism funded /
incentivized?
