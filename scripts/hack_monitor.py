#!/usr/bin/env python3
"""
DeFi hack monitor for Infrared Protocol.

Daily workflow:
  1. Fetch recent messages from a curated Slack threat channel.
  2. Filter against seen-hacks.json to dedupe.
  3. Optionally ask Claude to assess applicability to Infrared's src/.
  4. Open a GitHub issue per new hack.
  5. Persist seen IDs back to seen-hacks.json.

All integrations are best-effort: missing secrets or failing services are
logged and skipped. The workflow does not fail on external service state.

Environment variables (all optional except where noted):
  GITHUB_TOKEN, GITHUB_REPOSITORY     required to open/comment on issues
  SLACK_BOT_TOKEN, SLACK_CHANNEL_ID   required to fetch any hacks
  SLACK_ALLOWED_AUTHORS               optional comma-separated allowlist of
                                      Slack user / bot_id / app_id / username
                                      values. If set, all other authors are
                                      filtered out (use to keep Hypernative-
                                      only alerts in a channel with chatter).
  ANTHROPIC_API_KEY                   enables Claude auto-analysis
  MAX_HACKS_PER_RUN                   per-run cap (default 3)
  LOOKBACK_DAYS                       how many days of Slack history to scan
                                      (default 2; bump for discovery/backfill)
  GITHUB_STEP_SUMMARY                 set by GH Actions; filtered/duplicate
                                      hacks are written here instead of
                                      opening issues.
"""

import argparse
import hashlib
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

import requests

log = logging.getLogger("hack_monitor")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

STATE_PATH = Path(".github/security/seen-hacks.json")
SRC_DIR = Path("src")
DEFAULT_LOOKBACK_DAYS = 2
DEFAULT_MAX_HACKS = 3
HTTP_TIMEOUT = 30
SEEN_ID_HISTORY = 500


def _lookback() -> timedelta:
    try:
        days = int(os.environ.get("LOOKBACK_DAYS", DEFAULT_LOOKBACK_DAYS))
    except ValueError:
        days = DEFAULT_LOOKBACK_DAYS
    return timedelta(days=max(1, days))


@dataclass
class Hack:
    id: str
    source: str
    title: str
    url: str
    timestamp: str
    description: str = ""
    loss_usd: float | None = None
    raw: dict = field(default_factory=dict)


def stable_id(*parts: str) -> str:
    return hashlib.sha256("||".join(parts).encode()).hexdigest()[:16]


# ---------- state ----------

def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"version": 1, "seen_ids": []}
    try:
        return json.loads(STATE_PATH.read_text())
    except (OSError, json.JSONDecodeError) as e:
        log.warning(f"state: failed to read {STATE_PATH}: {e}; starting fresh")
        return {"version": 1, "seen_ids": []}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    state["seen_ids"] = sorted(set(state["seen_ids"]))[-SEEN_ID_HISTORY:]
    STATE_PATH.write_text(json.dumps(state, indent=2) + "\n")


# ---------- sources ----------

SLACK_SKIP_SUBTYPES = {
    "channel_join", "channel_leave", "channel_topic", "channel_purpose",
    "channel_name", "channel_archive", "channel_unarchive",
    "bot_add", "bot_remove", "pinned_item", "unpinned_item",
}


def _extract_slack_content(msg: dict) -> tuple[str, str]:
    """Return (title, description) for a Slack message.

    Bot messages posted via Incoming Webhooks often have an empty `text`
    field with the real content in `attachments[].fields[].value` (this is
    how Hypernative alerts arrive). Falling back through attachments keeps
    those posts visible.
    """
    text = (msg.get("text") or "").strip()
    if text:
        return text.split("\n")[0][:200], text[:4000]
    parts: list[str] = []
    for att in msg.get("attachments") or []:
        for field in att.get("fields") or []:
            title = (field.get("title") or "").strip()
            value = (field.get("value") or "").strip()
            if value:
                parts.append(f"*{title}*\n{value}" if title else value)
            elif title:
                parts.append(title)
        att_text = (att.get("text") or "").strip()
        if att_text:
            parts.append(att_text)
    body = "\n\n".join(parts).strip()
    if not body:
        return "", ""
    for line in body.splitlines():
        stripped = line.strip().strip("*").strip()
        if stripped:
            return stripped[:200], body[:4000]
    return body[:200], body[:4000]


def fetch_slack() -> list[Hack]:
    token = os.environ.get("SLACK_BOT_TOKEN")
    channel = os.environ.get("SLACK_CHANNEL_ID")
    if not token or not channel:
        log.info("slack: no token/channel, skipping")
        return []
    allowed_raw = os.environ.get("SLACK_ALLOWED_AUTHORS", "").strip()
    allowed = {a.strip() for a in allowed_raw.split(",") if a.strip()} or None
    oldest = (datetime.now(timezone.utc) - _lookback()).timestamp()
    try:
        r = requests.get(
            "https://slack.com/api/conversations.history",
            headers={"Authorization": f"Bearer {token}"},
            params={"channel": channel, "oldest": f"{oldest:.0f}", "limit": 200},
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        payload = r.json()
        if not payload.get("ok"):
            log.warning(f"slack: api error: {payload.get('error')}")
            return []
        hacks = []
        seen_authors: dict[str, int] = {}
        for msg in payload.get("messages", []):
            if msg.get("subtype") in SLACK_SKIP_SUBTYPES:
                continue
            title, description = _extract_slack_content(msg)
            if not description:
                continue
            user = msg.get("user") or ""
            bot_id = msg.get("bot_id") or ""
            app_id = msg.get("app_id") or ""
            username = msg.get("username") or ""
            author_key = f"user={user or '-'} bot_id={bot_id or '-'} app_id={app_id or '-'} username={username or '-'}"
            seen_authors[author_key] = seen_authors.get(author_key, 0) + 1
            if allowed and not (
                (user and user in allowed)
                or (bot_id and bot_id in allowed)
                or (app_id and app_id in allowed)
                or (username and username in allowed)
            ):
                continue
            ts = msg.get("ts", "")
            try:
                when = datetime.fromtimestamp(float(ts), tz=timezone.utc).isoformat()
            except ValueError:
                when = datetime.now(timezone.utc).isoformat()
            hacks.append(Hack(
                id=f"slack-{ts}",
                source="slack",
                title=title,
                url=f"https://slack.com/archives/{channel}/p{ts.replace('.', '')}",
                timestamp=when,
                description=description,
                raw=msg,
            ))
        if seen_authors:
            # Log authors to help discover the right ID for SLACK_ALLOWED_AUTHORS
            for author, count in sorted(seen_authors.items(), key=lambda kv: -kv[1]):
                log.info(f"slack: author {author} ({count} msgs)")
        log.info(f"slack: fetched {len(hacks)} messages" + (f" (filtered from {sum(seen_authors.values())})" if allowed else ""))
        return hacks
    except Exception as e:
        log.warning(f"slack: fetch failed: {e}")
        return []




# ---------- github issue listing ----------

RECENT_ISSUES_LOOKBACK_DAYS = 14


def fetch_recent_issues() -> list[dict]:
    """Fetch recent open hack-monitor issues for duplicate detection.

    Returns a list of {"number", "title", "body"} dicts. Empty on any error
    or missing auth — dedup is best-effort, not correctness-critical.
    """
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repo:
        return []
    since = (datetime.now(timezone.utc) - timedelta(days=RECENT_ISSUES_LOOKBACK_DAYS)).isoformat()
    try:
        r = requests.get(
            f"https://api.github.com/repos/{repo}/issues",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            params={"labels": "hack-monitor", "state": "open", "per_page": 50, "since": since},
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        issues = []
        for item in r.json():
            # /issues returns PRs too; skip them
            if "pull_request" in item:
                continue
            issues.append({
                "number": item.get("number"),
                "title": item.get("title", ""),
                "body": (item.get("body") or "")[:500],
            })
        log.info(f"github: fetched {len(issues)} recent open hack-monitor issues")
        return issues
    except Exception as e:
        log.warning(f"github: fetching recent issues failed: {e}")
        return []


# ---------- analysis ----------

def analyze_with_claude(hack: Hack, src_files: list[str], recent_issues: list[dict]) -> dict | None:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return None
    try:
        import anthropic
    except ImportError:
        log.warning("anthropic package not installed, skipping analysis")
        return None

    file_summary = "\n".join(f"- {f}" for f in sorted(src_files)[:80])
    loss = f"${hack.loss_usd:,.0f}" if hack.loss_usd else "unknown"

    if recent_issues:
        issues_block = "\n\n".join(
            f"#{i['number']} · {i['title']}\n{i['body'][:400]}" for i in recent_issues
        )
        duplicate_section = f"""## Recent open hack-monitor issues

Each block is an existing open GitHub issue about a prior hack report. If
the new report below is about the same underlying incident as any of
these (same protocol, same attack, same asset — even if the report angle
is different), set `duplicate_of` to that issue number. Otherwise, set
it to null.

{issues_block}
"""
    else:
        duplicate_section = "## Recent open hack-monitor issues\n\n(none)\n"

    prompt = f"""You are reviewing a DeFi security incident against the Infrared Protocol codebase.

Infrared is a liquid staking protocol on Berachain. Key components:
- iBERA: liquid staked BERA (native gas token), queue-based deposit/withdrawal
- iBGT: liquid staked BGT (governance token)
- UUPS upgradeable contracts with ERC-7201 namespaced storage
- BerachainRewardsVault / BGT integration
- Multi-token reward distribution (MultiRewards)
- Cross-chain bridging uses LayerZero with a 2-of-2 DVN setup (LayerZero Labs + Berachain nodes)

## Hack report

**Source:** {hack.source}
**Title:** {hack.title}
**URL:** {hack.url}
**Reported loss:** {loss}

**Description:**
{hack.description[:3000]}

## Infrared source files (first 80)

{file_summary}

{duplicate_section}
## Your task

Assess whether this exploit pattern could apply to Infrared, and whether
it duplicates an existing open issue. Respond with ONLY a JSON object,
no prose:

{{
  "applicable": "yes" | "no" | "maybe",
  "severity": "critical" | "high" | "medium" | "low" | "info",
  "confidence": "high" | "medium" | "low",
  "attack_class": "short label, e.g. 'price manipulation', 'reentrancy'",
  "duplicate_of": null | <issue_number from the list above>,
  "files_to_review": ["src/path/to/file.sol", ...],
  "ethskills_checklists": ["evm-audit-*.md", ...],
  "reasoning": "2-4 sentences on why this does or does not apply to Infrared specifically",
  "suggested_actions": ["concrete next step", ...]
}}

Be strict on applicability: if the exploit is unrelated to Infrared's
threat model (bridges we don't use, oracles we don't integrate, CEX
exploits, chains we don't deploy to, single-DVN designs we don't share),
answer "no" with low severity. Only answer "yes" when you can point to
specific files or patterns present in the file list above.

Be strict on duplicates: only set `duplicate_of` when the issue listed
above is clearly about the same underlying incident. Different incidents
sharing an attack class are NOT duplicates."""

    try:
        client = anthropic.Anthropic(api_key=key)
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1500,
            messages=[{"role": "user", "content": prompt}],
        )
        text = response.content[0].text.strip()
        if text.startswith("```"):
            text = text.split("```", 2)[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip().rstrip("`").strip()
        return json.loads(text)
    except Exception as e:
        log.warning(f"claude: analysis failed: {e}")
        return None


# ---------- github issue ----------

def build_issue_body(hack: Hack, analysis: dict | None) -> str:
    lines = [
        f"**Source:** `{hack.source}`",
        f"**Observed:** {hack.timestamp}",
    ]
    if hack.url:
        lines.append(f"**URL:** {hack.url}")
    if hack.loss_usd:
        lines.append(f"**Reported loss:** ${hack.loss_usd:,.0f}")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(hack.description[:3000] or "_(no description available)_")
    lines.append("")

    if analysis:
        app = analysis.get("applicable", "unknown")
        emoji = {"yes": "🔴", "maybe": "🟡", "no": "🟢"}.get(app, "⚪")
        lines.extend([
            f"## Auto-analysis {emoji}",
            "",
            f"- **Applicable to Infrared:** `{app}`",
            f"- **Severity:** `{analysis.get('severity', '?')}`",
            f"- **Confidence:** `{analysis.get('confidence', '?')}`",
            f"- **Attack class:** {analysis.get('attack_class', '?')}",
            "",
            "**Reasoning:** " + str(analysis.get("reasoning", "_(none)_")),
            "",
        ])
        files = analysis.get("files_to_review") or []
        if files:
            lines.append("**Files to review:**")
            lines.extend(f"- `{f}`" for f in files[:20])
            lines.append("")
        checklists = analysis.get("ethskills_checklists") or []
        if checklists:
            lines.append("**Ethskills checklists to apply:**")
            lines.extend(f"- `ethskills/{c}`" for c in checklists)
            lines.append("")
        actions = analysis.get("suggested_actions") or []
        if actions:
            lines.append("**Suggested actions:**")
            lines.extend(f"- {a}" for a in actions)
            lines.append("")
    else:
        lines.extend([
            "## Manual review prompt",
            "",
            "No auto-analysis available (Anthropic API not configured or call failed). "
            "Paste the block below into Claude Code to analyze:",
            "",
            "```",
            f"Hack: {hack.title}",
            "",
            (hack.description[:1500] or "(no description)"),
            "",
            "Task: Check Infrared Protocol's src/ for this exploit pattern.",
            "For each candidate file, state: applicable / not applicable (reason) / needs deeper review.",
            "Reference ethskills/*.md checklists as appropriate.",
            "```",
            "",
        ])

    lines.extend([
        "## Triage",
        "",
        "- [ ] Reviewed against current codebase",
        "- [ ] Applicable — follow-up issue / PR opened",
        "- [ ] Not applicable — dismissed (record reason below)",
        "",
        "---",
        "_Automatically opened by the DeFi hack monitor. See `docs/AI_SECURITY.md`._",
    ])
    return "\n".join(lines)


def post_comment(issue_number: int, body: str) -> bool:
    """Add a comment to an existing hack-monitor issue (duplicate case)."""
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repo:
        log.warning("github: missing GITHUB_TOKEN or GITHUB_REPOSITORY, skipping comment")
        return False
    try:
        r = requests.post(
            f"https://api.github.com/repos/{repo}/issues/{issue_number}/comments",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            json={"body": body},
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        log.info(f"commented on issue #{issue_number}: {r.json().get('html_url', '(no url)')}")
        return True
    except Exception as e:
        log.warning(f"github: comment creation failed: {e}")
        return False


def build_comment_body(hack: Hack, analysis: dict | None) -> str:
    lines = [
        "**Additional report of the same incident** picked up by the hack monitor.",
        "",
        f"**Source:** `{hack.source}`",
        f"**Observed:** {hack.timestamp}",
    ]
    if hack.url:
        lines.append(f"**URL:** {hack.url}")
    lines.append("")
    lines.append(hack.description[:2000] or "_(no description available)_")
    if analysis:
        lines.extend([
            "",
            f"**Auto-analysis:** applicable={analysis.get('applicable', '?')}, "
            f"severity={analysis.get('severity', '?')}",
            "",
            str(analysis.get("reasoning", "")),
        ])
    return "\n".join(lines)


def append_step_summary(lines: list[str]) -> None:
    """Write markdown to the GitHub Actions run summary (falls back to stdout)."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    text = "\n".join(lines) + "\n"
    if not path:
        print(text)
        return
    try:
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)
    except OSError as e:
        log.warning(f"github: writing step summary failed: {e}")


def open_issue(hack: Hack, analysis: dict | None) -> bool:
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repo:
        log.warning("github: missing GITHUB_TOKEN or GITHUB_REPOSITORY, skipping issue")
        return False

    labels = ["security", "hack-monitor", "auto-generated"]
    if analysis:
        app = analysis.get("applicable", "unknown")
        if app == "yes":
            labels.append("applicable")
        elif app == "maybe":
            labels.append("needs-review")
        elif app == "no":
            labels.append("not-applicable")
        sev = analysis.get("severity")
        if sev in {"critical", "high", "medium", "low"}:
            labels.append(f"severity-{sev}")
    else:
        labels.append("needs-triage")

    try:
        r = requests.post(
            f"https://api.github.com/repos/{repo}/issues",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            json={
                "title": f"[hack-monitor] {hack.title[:100]}",
                "body": build_issue_body(hack, analysis),
                "labels": labels,
            },
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        log.info(f"opened issue: {r.json().get('html_url', '(no url)')}")
        return True
    except Exception as e:
        log.warning(f"github: issue creation failed: {e}")
        return False


# ---------- main ----------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1] if __doc__ else None)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print analysis to stdout; skip GitHub issue creation and seen-hacks state writes.",
    )
    args = parser.parse_args()

    max_hacks = int(os.environ.get("MAX_HACKS_PER_RUN", DEFAULT_MAX_HACKS))

    state = load_state()
    seen_ids = set(state.get("seen_ids", []))

    hacks = fetch_slack()
    log.info(f"fetched {len(hacks)} total hacks from Slack")

    new_hacks = [h for h in hacks if h.id not in seen_ids]
    log.info(f"{len(new_hacks)} hacks are new")

    if len(new_hacks) > max_hacks:
        log.warning(f"capping to {max_hacks} hacks this run (got {len(new_hacks)})")
        new_hacks = new_hacks[:max_hacks]

    src_files = [str(p) for p in SRC_DIR.rglob("*.sol")] if SRC_DIR.is_dir() else []
    recent_issues = [] if args.dry_run else fetch_recent_issues()

    summary_rows: list[str] = []

    for hack in new_hacks:
        log.info(f"processing: [{hack.source}] {hack.title[:80]}")
        analysis = analyze_with_claude(hack, src_files, recent_issues)
        applicable = (analysis or {}).get("applicable", "unknown")
        dup_of = (analysis or {}).get("duplicate_of")
        # duplicate_of can arrive as int or string; normalize
        try:
            dup_of = int(dup_of) if dup_of not in (None, "", "null") else None
        except (TypeError, ValueError):
            dup_of = None

        if args.dry_run:
            disposition = (
                f"duplicate of #{dup_of}" if dup_of
                else "filtered (not applicable)" if applicable == "no"
                else "would open new issue"
            )
            print(f"\n{'=' * 70}\n[hack-monitor] {hack.title[:100]}\n[{disposition}]\n{'=' * 70}")
            print(build_issue_body(hack, analysis))
            continue

        if dup_of:
            post_comment(dup_of, build_comment_body(hack, analysis))
            summary_rows.append(f"| 🔗 | {hack.title[:80]} | Comment added to #{dup_of} |")
        elif applicable == "no":
            reason = (analysis or {}).get("reasoning", "")
            summary_rows.append(f"| 🟢 | {hack.title[:80]} | Filtered as not applicable — {reason[:200]} |")
            log.info(f"skipping issue creation (applicable=no): {hack.title[:80]}")
        else:
            opened = open_issue(hack, analysis)
            emoji = "🔴" if applicable == "yes" else "🟡" if applicable == "maybe" else "⚪"
            status = "issue opened" if opened else "issue creation failed"
            summary_rows.append(f"| {emoji} | {hack.title[:80]} | {status} (applicable={applicable}) |")

        # Mark seen regardless: avoid retry loops on flaky data.
        seen_ids.add(hack.id)

    if not args.dry_run and summary_rows:
        today = datetime.now(timezone.utc).date().isoformat()
        append_step_summary([
            f"## Hack monitor triage — {today}",
            "",
            f"Processed {len(new_hacks)} new hack(s).",
            "",
            "| Status | Title | Disposition |",
            "|---|---|---|",
            *summary_rows,
        ])

    if not args.dry_run:
        state["seen_ids"] = sorted(seen_ids)
        save_state(state)
    log.info("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
