#!/usr/bin/env python3
"""
Ethskills pattern scanner for Infrared Protocol.

Walks src/ and identifies which ethskills audit checklists apply to which
contracts based on their imports and contract declarations. Output is an
audit reading list — not a vulnerability scanner.

Skills live in ./ethskills/ (see ethskills/README.md).
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SRC_DIR = Path("src")
SKILLS_DIR = Path("ethskills")
REPORT_PATH = Path("ai-reports/ethskills-report.json")

# Map (contract trait) -> (skill filename, severity label, human category)
# Traits are detected via precise markers, not broad regex matches.
SKILL_MAP = [
    {
        "trait": "upgradeable",
        "skill": "evm-audit-proxies.md",
        "severity": "Critical",
        "category": "Proxy / upgradeable",
        "markers": [
            re.compile(r"\bUUPSUpgradeable\b"),
            re.compile(r"\bInitializable\b"),
            re.compile(r"\b_authorizeUpgrade\b"),
            re.compile(r"\bERC1967\b"),
            re.compile(r"Upgradeable\.sol"),
        ],
    },
    {
        "trait": "erc4626",
        "skill": "evm-audit-erc4626.md",
        "severity": "High",
        "category": "ERC4626 vault",
        "markers": [
            re.compile(r"\bERC4626\b"),
            re.compile(r"\bconvertToShares\b"),
            re.compile(r"\bconvertToAssets\b"),
            re.compile(r"\bpreviewDeposit\b"),
            re.compile(r"\btotalAssets\b"),
        ],
    },
    {
        "trait": "staking",
        "skill": "evm-audit-defi-staking.md",
        "severity": "High",
        "category": "Liquid staking",
        "markers": [
            re.compile(r"\bInfraredBERA\b"),
            re.compile(r"\bInfraredBERADepositor\b"),
            re.compile(r"\bInfraredBERAWithdrawor\b"),
            re.compile(r"\bBerachainRewardsVault\b"),
            re.compile(r"\bdeposit.*pubkey", re.IGNORECASE),
        ],
    },
    {
        "trait": "access_control",
        "skill": "evm-audit-general.md",
        "severity": "Medium",
        "category": "Access control",
        "markers": [
            re.compile(r"\bAccessControl\b"),
            re.compile(r"\bonlyRole\b"),
            re.compile(r"\bGOVERNANCE_ROLE\b"),
            re.compile(r"\bKEEPER_ROLE\b"),
            re.compile(r"\bPAUSER_ROLE\b"),
        ],
    },
]


def scan_file(path: Path) -> set[str]:
    """Return the set of trait names matched by this file."""
    try:
        content = path.read_text()
    except OSError:
        return set()
    return {
        entry["trait"]
        for entry in SKILL_MAP
        if any(m.search(content) for m in entry["markers"])
    }


def main() -> int:
    if not SRC_DIR.is_dir():
        print(f"error: {SRC_DIR} not found", file=sys.stderr)
        return 1

    sol_files = sorted(SRC_DIR.rglob("*.sol"))
    trait_to_files: dict[str, list[str]] = {entry["trait"]: [] for entry in SKILL_MAP}
    for f in sol_files:
        for trait in scan_file(f):
            trait_to_files[trait].append(str(f))

    findings = []
    for entry in SKILL_MAP:
        files = trait_to_files[entry["trait"]]
        if not files:
            continue
        findings.append({
            "severity": entry["severity"],
            "category": entry["category"],
            "title": f"{len(files)} file(s) match {entry['category'].lower()} patterns",
            "skill": entry["skill"],
            "recommendation": f"Apply ethskills/{entry['skill']}",
            "files": files,
        })

    available_skills = sorted(p.name for p in SKILLS_DIR.glob("*.md")) if SKILLS_DIR.is_dir() else []

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "skills_available": available_skills,
        "contract_analysis": {
            "solidity_files_found": len(sol_files),
        },
        "findings": findings,
        "summary": {
            "total_findings": len(findings),
            "by_severity": {
                sev: sum(1 for f in findings if f["severity"] == sev)
                for sev in ("Critical", "High", "Medium")
            },
        },
    }

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(json.dumps(report, indent=2) + "\n")

    print(f"Scanned {len(sol_files)} Solidity files.")
    print(f"Skills available: {len(available_skills)}")
    print(f"Findings: {len(findings)}")
    for f in findings:
        print(f"  [{f['severity']}] {f['category']:20s}  {len(f['files'])} file(s) -> {f['skill']}")
    print(f"Report: {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
