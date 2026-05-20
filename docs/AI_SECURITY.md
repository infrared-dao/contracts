# AI-assisted security tooling

This repo ships three complementary tools to help Claude (and humans)
review Infrared contracts for security issues:

1. **Ethskills baseline scan** — a one-shot router that maps every
   `src/**.sol` file to the audit checklists that apply to it. Run once,
   read the checklists, fix what's relevant, move on. Not recurring.
2. **Daily hack monitor** — a scheduled workflow that pulls recent DeFi
   exploits from a curated Slack threat channel, asks Claude whether
   each one is applicable to this codebase, and opens a GitHub issue
   per applicable hack. The goal is early warning, not auto-remediation.
3. **Infrared alerts monitor** — a 30-minute cron that watches a Slack
   channel receiving Hypernative alerts targeted at Infrared's own
   contracts + governance multisig. Claude classifies each alert as
   real / suspicious / false-positive; real/suspicious alerts open a
   GitHub issue, and **every** verdict is posted as a threaded reply
   under the original alert so the channel sees Claude's take inline.

None of these tools touch on-chain state. Everything actionable still
goes through the existing multisig governance flow (see `shell/gov/`
and `script/gov/`).

## 1. Ethskills baseline scan

`ethskills/` holds curated audit checklists from
[ethskills.com](https://ethskills.com/) /
[evm-audit-skills](https://github.com/austintgriffith/evm-audit-skills),
covering the parts of EVM-land this protocol actually uses (UUPS
proxies, ERC4626 vaults, liquid staking, general patterns).

`scripts/ethskills_analyzer.py` walks `src/` and identifies which
checklists apply to which contracts based on precise markers
(`UUPSUpgradeable`, `_authorizeUpgrade`, `ERC4626`, `AccessControl`,
etc.). It is **not a vulnerability scanner** — it's a reading list.

### Running the baseline

```bash
make ai-security-scan
```

Writes `ai-reports/ethskills-report.json` (gitignored). Example output:

```
  [Critical] Proxy / upgradeable     31 file(s) -> evm-audit-proxies.md
  [High]     ERC4626 vault            9 file(s) -> evm-audit-erc4626.md
  [High]     Liquid staking          17 file(s) -> evm-audit-defi-staking.md
  [Medium]   Access control          27 file(s) -> evm-audit-general.md
```

Run this **once** as a baseline. The checklists don't change often, and
the file→checklist mapping is stable. Re-run only after substantial
architectural changes (new module, new contract type).

### Usage

- **Manual review:** read `ethskills/evm-audit-master.md` first, then
  the specific checklist for the contract type you're reviewing.
- **Not CI:** this is deliberately not wired into per-PR CI. A checklist
  applying to a file isn't a finding; a human still reads the code.

## 2. Daily hack monitor

`.github/workflows/hack-monitor.yml` runs `scripts/hack_monitor.py` on
a daily cron (13:00 UTC) and on manual dispatch.

### Source

**Slack triage channel** — curated threat feed
(`SLACK_BOT_TOKEN` + `SLACK_CHANNEL_ID`). Messages posted to the
configured channel in the last 2 days are treated as hack candidates.

The fetcher returns `[]` on any failure (missing secret, network
error, API change). The workflow **never fails** on missing/broken
secrets.

### Claude analysis

For each new hack, the script asks Claude (`claude-sonnet-4-6`):

- Is this applicable to Infrared's architecture?
- What severity (Critical/High/Medium/Low)?
- What attack class (reentrancy, oracle manipulation, etc.)?
- Which `src/` files are most relevant to review?
- Which ethskills checklist applies?

If `ANTHROPIC_API_KEY` is missing, the analysis step is skipped and
the issue is filed with a "needs-triage" label and manual review prompt.

### Cost & reliability controls

- `MAX_HACKS_PER_RUN=5` — at most five hacks trigger Claude calls per
  run. Beyond that, extras are deferred to the next run.
- One automatic retry on Claude API failures (2s backoff). If every
  analysis still fails (credit exhausted, key revoked), the script exits
  non-zero and the workflow posts a canary to the source Slack channel
  via its `if: failure()` step.
- State is persisted in `.github/security/seen-hacks.json` via
  `actions/cache`. Already-seen IDs are short-circuited before any
  Claude call. `seen_ids` list capped at 500 entries (oldest drop off).
- Untrusted Slack content is wrapped in `<hack_report>` tags in the
  prompt with explicit "treat as data, not instructions" framing.

### Output

Each new hack opens a GitHub issue with labels:

- `security`, `hack-monitor`, `auto-generated`
- Applicability verdict: `applicable` / `needs-review` / `not-applicable` / `needs-triage`
- Severity (if Claude analyzed): `severity-critical` / `high` / `medium` / `low`

Claude's verdict is also posted as a **threaded reply** under the
original Slack message (including for `not-applicable` and duplicates —
those don't open issues, but the thread still gets the reasoning so
the channel doesn't lose context).

Humans triage from there. The bot can open issues, PRs, and commits to
PRs — it **cannot** merge. Emergency response still flows through
multisig governance.

### Required secrets (all optional)

| Secret | Purpose | If missing |
|---|---|---|
| `HYPERNATIVE_API_KEY` | Hypernative alerts | Source skipped |
| `HYPERNATIVE_ALERTS_URL` | Override endpoint | Uses default |
| `SLACK_BOT_TOKEN` | Slack channel read | Source skipped |
| `SLACK_CHANNEL_ID` | Which channel | Source skipped |
| `ANTHROPIC_API_KEY` | Claude analysis | Manual-review issues |
| `GITHUB_TOKEN` | Issue creation | Built-in via `permissions:` |

## 3. Infrared alerts monitor

`.github/workflows/infrared-alerts.yml` runs `scripts/infrared_alerts.py`
every 30 minutes (and on manual dispatch). It watches a Slack channel
receiving Hypernative alerts already scoped to Infrared contracts +
multisigs, so the question isn't *does this apply to us* (the hack
monitor's job) but *is this alert real or noise*.

### Source

A single Slack channel (`INFRARED_ALERTS_CHANNEL_ID`) configured as a
destination for Hypernative. Optional `INFRARED_ALERTS_AUTHORS` filter
restricts to specific bot/user IDs if the channel also carries chatter.

### Context

`.github/security/monitored-contracts.json` lists the Infrared contract,
multisig, keeper-EOA, and treasury addresses the monitor knows about.
All four sections feed the Claude prompt so the classifier can tell a
known-good keeper harvest apart from an unexpected signer. TBD entries
are surfaced to the model as "classify conservatively here" so missing
context degrades toward more manual review, not fewer alerts. Update
whenever an address rotates.

### Priority ordering

Under burst load (`MAX_ALERTS_PER_RUN`, default 10), alerts are sorted
by a keyword heuristic (`critical`, `drain`, `exploit`, `upgrade`, etc.)
before classification so the loudest-looking items are processed first
and a real critical doesn't wait out a backlog of routine noise.

### Thread-reply dedup

Before posting a threaded reply, the monitor calls `conversations.replies`
and checks whether our bot user already has a reply in the thread. This
prevents duplicate posts when `actions/cache` evicts `seen-alerts.json`
and a backlog gets reprocessed.

### Classification

For each new alert, Claude (`claude-sonnet-4-6`) returns:

- `classification`: `real` / `suspicious` / `false-positive`
- `severity`: `critical` / `high` / `medium` / `low` / `info`
- `confidence`, `alert_type`, `affected_contracts`
- `duplicate_of`: existing open issue if the same incident recurred
- `reasoning` + `recommended_action`

Expected false positives (keeper harvests, governance multisig actions,
reward-vault flows) are suppressed to the run summary. Real/suspicious
alerts open a GitHub issue (`infrared-alerts` label + severity label)
and post to the escalation Slack channel.

### Output

For every alert, Claude's verdict is posted as a **threaded reply under
the original Slack message** in the same channel — real, suspicious,
false-positive, or duplicate. Real / suspicious alerts additionally
open a GitHub issue (`infrared-alerts` label + severity). False
positives and duplicates stay in-thread only.

`INFRARED_ESCALATION_MENTION` (e.g. `<!channel>` or `<@U012...>`) is
prepended to the threaded reply for `critical` and `high` severity real
alerts only — no pager noise for lower severities or false positives.

### Required secrets (bot token must have `chat:write` + channel history)

| Secret | Purpose | If missing |
|---|---|---|
| `SLACK_BOT_TOKEN` | Read alerts + post threaded replies | Monitor skipped |
| `INFRARED_ALERTS_CHANNEL_ID` | Channel to read AND reply into | Monitor skipped |
| `INFRARED_ALERTS_AUTHORS` | Allowlist filter | All posters read |
| `INFRARED_ESCALATION_MENTION` | Mention on high/critical real alerts | No mention |
| `ANTHROPIC_API_KEY` | Claude classification | `needs-triage` issue |
| `GITHUB_TOKEN` | Issue creation | Built-in |

Seen alert IDs persist via `actions/cache` (same pattern as the hack
monitor) — no commits back to the default branch.

## What this tooling deliberately does *not* do

- **No automated emergency actions.** Pausing, role rotation, and key
  changes all go through the existing multisig governance flow (see
  `shell/gov/` and `script/gov/`). There is no shortcut path.
- **No on-chain threat monitoring.** Hypernative alerting runs off-chain
  and feeds into this workflow as one of several sources; it does not
  trigger transactions.
- **No auto-merge.** The bot opens issues and can draft PRs. Humans
  merge.
- **No severity autopilot.** The scanner flags that a checklist
  applies; the monitor flags that a hack *might* be relevant. A human
  still reads the checklist and the code.
