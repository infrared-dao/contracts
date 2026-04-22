# AI-assisted security tooling

This repo ships two complementary tools to help Claude (and humans)
review Infrared contracts for security issues:

1. **Ethskills baseline scan** — a one-shot router that maps every
   `src/**.sol` file to the audit checklists that apply to it. Run once,
   read the checklists, fix what's relevant, move on. Not recurring.
2. **Daily hack monitor** — a scheduled workflow that pulls recent DeFi
   exploits from several feeds, asks Claude whether each one is
   applicable to this codebase, and opens a GitHub issue per hack. The
   goal is early warning, not auto-remediation.

Neither tool touches on-chain state. Everything actionable still goes
through the existing multisig governance flow (see `shell/gov/` and
`script/gov/`).

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

### Cost controls

- `MAX_HACKS_PER_RUN=3` — at most three hacks trigger Claude calls per
  run. Beyond that, extras are deferred to the next run.
- State is persisted in `.github/security/seen-hacks.json` (committed
  by the workflow with `[skip ci]`). Already-seen IDs are short-circuited
  before any Claude call.
- `seen_ids` list capped at 500 entries (oldest drop off).

### Output

Each new hack opens a GitHub issue with labels:

- `security`, `hack-monitor`, `auto-generated`
- Applicability verdict: `applicable` / `needs-review` / `not-applicable` / `needs-triage`
- Severity (if Claude analyzed): `severity-critical` / `high` / `medium` / `low`

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
