# Finding template

Per-finding file under `$AUDIT_DIR/finding/{SEVERITY}_{slug}.md`. The
orchestrator writes one file per finding in Phase 8 after the matching
PoC reaches `PASSING` status. Never bundle multiple findings into one
file: bounty platforms triage per-finding, and a multi-finding file
either gets rejected outright or loses one of its findings to the
triager's deduplication pass.

The `Calibration` block is the contract between Phase 7 (PoC) and Phase
9 (REPORT). K3 (submittable count) in the executive summary is computed
by filtering on `confidence_0_100`, `gate_failures`,
`would_submit_to_bounty`, and `triager_reject_probability`. Drop a
field and the summary silently mis-counts.

## Template

```markdown
# [SEVERITY] Title

## Bounty Platform Submission Info

- **Target:** <exact target URL from the bounty assets table>
- **Target Description:** <description from scope>
- **Severity Level:** Critical / High / Medium / Low
- **Bug Classification:** <matching category from BOUNTY_MATRIX.md>

## Calibration

| field | value |
|-------|-------|
| `severity_pre_poc` | vuln-hunter's `severity_hypothesis` |
| `severity_post_triager` | skeptical-triager's Phase 6.5 verdict (AFFIRM / DOWNGRADE <tier> / REJECT) |
| `severity_post_poc` | Critical / High / Medium / Low / Info, re-derived from measured PoC numbers |
| `confidence_0_100` | integer |
| `single_strongest_reject` | strongest rejection reason |
| `smallest_falsifier` | cheapest test that proves the claim wrong |
| `gate_failures` | failed validity gates or `none` |
| `poc_status` | PASSING / NOT_BUILT / FAILED / N/A |
| `poc_path` | report/POC/<slug>/Exploit.t.sol |
| `measured_attacker_pl_usd` | net USD profit observed in PoC (negative = grief) |
| `measured_victim_loss_usd` | USD loss for griefing variants |
| `would_submit_to_bounty` | yes / no - honest self-assessment |
| `triager_reject_probability` | 0-100% estimate that a bounty triager downgrades or rejects |

If `confidence_0_100 < 60` OR `gate_failures` is not `none` OR
`would_submit_to_bounty = no` OR `triager_reject_probability >= 30%`,
the finding moves to the report's "Code-walk observations" section
instead of the headline findings list. The orchestrator MUST honor
these fields in `REPORT.md` Phase 9 executive summary - K3 (submittable
count) is filtered by exactly this rule.

## Summary

One paragraph: the vulnerability, root cause, why it matters.

## Detail

- **Contract:** ContractName.sol
- **Function:** functionName()
- **Line:** L123 - L145
- **Category:** Reentrancy / Access Control / Oracle / Logic Error / etc.
- **Root Cause:** technical explanation
- **Affected Code:** relevant snippet

## Impact

What the attacker achieves. Quantify in dollar amounts or percent loss.

## Step-by-Step Exploitation

Numbered, exact function calls with parameters, ending in
"Result: attacker gains X, protocol loses Y".

## Proof of Concept

PoC path: `report/POC/<slug>/Exploit.t.sol`
Reproduce: `report/POC/<slug>/reproduce.sh`

### Test Output

```
# actual forge output showing PASS + console.log evidence
```

## Recommended Fix

How to fix, with a code diff if possible.

## Triager rejection reasons (anticipated)

List every reason a triager might reject. For each, the counter-argument.

## References

- Related Slither finding, similar known vulnerabilities, CVEs.
```

## Why the "Recommended Fix" section is not a style review

The adversarial stance in `SKILL.md` excludes style, naming, NatSpec,
gas, and best-practice notes. The fix recommendation here is different:
bounty platforms (Cantina, Immunefi, Code4rena, Sherlock, Hats) require
a remediation suggestion for the finding to be accepted as a submission.
The recommendation is scoped to the SPECIFIC exploit path the PoC
demonstrates, not a broader code-quality pass on unrelated functions.

If the only honest fix recommendation is "redesign the mechanism", say
so plainly rather than padding with cosmetic suggestions.
