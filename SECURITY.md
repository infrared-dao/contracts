# Security

## Reporting a Vulnerability

Security vulnerabilities should be disclosed by email to **security@infrared.finance**.

**Do not open a public GitHub issue for security vulnerabilities.**

Please include a description of the issue, steps to reproduce, and an assessment of potential impact. We will acknowledge receipt promptly and work with you to understand and address the issue.

---

## Responsible Disclosure Scope

**In-scope contracts:**
- `src/core/` — Infrared, InfraredVault, BribeCollector, InfraredDistributor, MultiRewards
- `src/staking/` — InfraredBERA, InfraredBERADepositor, InfraredBERAWithdrawor, IBERAFeeReceivor
- `src/periphery/` — IRAuction, MerkleDistributor, CuttingBoardDutchAuction, CuttingBoardManager

**Out of scope:**
- `src/depreciated/` — historical implementations kept for reference only
- `src/vendors/` — third-party contracts vendored from OpenZeppelin
- `src/voting/` — external voting system interfaces (not implemented here)
- Tests, scripts, and deployment tooling
- Issues in dependencies (OpenZeppelin, Solmate, LayerZero) that are not exploitable in the context of Infrared contracts
- Issues requiring compromised governance multisig or keeper keys
- Economic attacks that are only profitable under conditions not present on Berachain mainnet

**Severity guidelines:**
| Severity | Examples |
|----------|----------|
| Critical | Direct theft of user funds, permanent protocol lock |
| High | Temporary fund lock, significant loss of yield, unauthorized minting |
| Medium | Access control bypass without direct fund loss, griefing with economic cost |
| Low | Edge cases with minor impact, gas optimisations |

---

## Audits

All audit reports are available in the [`audits/`](./audits/) directory and on the [Infrared documentation site](https://infrared.finance/docs/audits).

| Date | Auditor | Report |
|------|---------|--------|
| Apr 2024 | Zellic | [`Infrared - Zellic Audit Report.pdf`](./audits/Infrared%20-%20Zellic%20Audit%20Report.pdf) |
| Aug 2024 | Cantina | [`report-cantinacode-infrared.pdf`](./audits/report-cantinacode-infrared.pdf) |
| Oct 2024 | Zellic | [`Infrared Berachain Core Integration - Zellic Audit Report.pdf`](./audits/Infrared%20Berachain%20Core%20Integration%20-%20Zellic%20Audit%20Report.pdf) |
| Feb 2025 | Zenith | [`Zenith Audit Report - Infrared Finance.pdf`](./audits/Zenith%20Audit%20Report%20-%20Infrared%20Finance.pdf) |
| Feb 2025 | Cantina (competition) | [`report-competition-infrared-contracts.pdf`](./audits/report-competition-infrared-contracts.pdf) |
| Feb 2025 | Cantina | [`report-cantinacode-infrared-1.pdf`](./audits/report-cantinacode-infrared-1.pdf) |
| Feb 2025 | Spearbit | [`Infrared_Finance_Incidence_Response_Review_Report_Feb_2025_2.pdf`](./audits/Infrared_Finance_Incidence_Response_Review_Report_Feb_2025_2.pdf) |
| Mar 2025 | Cantina | [`report-cantinacode-infrared-0310-bribeCollector.pdf`](./audits/report-cantinacode-infrared-0310-bribeCollector.pdf) |
| Mar 2025 | Cantina | [`report-cantinacode-infrared-0320.pdf`](./audits/report-cantinacode-infrared-0320.pdf) |
| Apr 2025 | Zenith | [`Infrared - Zenith Audit Report.pdf`](./audits/Infrared%20-%20Zenith%20Audit%20Report.pdf) |
| Jul 2025 | Cantina | [`report-cantinacode-infrared-03072025.pdf`](./audits/report-cantinacode-infrared-03072025.pdf) |
| Jul 2025 | Zenith | [`Infrared - Zenith Audit Report 09.07.2025.pdf`](./audits/Infrared%20-%20Zenith%20Audit%20Report%2009.07.2025.pdf) |
| Aug 2025 | Zenith | [`Infrared - Zenith Audit Report - 20082025.pdf`](./audits/Infrared%20-%20Zenith%20Audit%20Report%20-%2020082025.pdf) |
| Sep 2025 | Cantina | [`Infraredv1.5.pdf`](./audits/Infraredv1.5.pdf) |
| Sep 2025 | Zenith | [`Infrared Merkle Distributor - Zenith Audit Report.pdf`](./audits/Infrared%20Merkle%20Distributor%20-%20Zenith%20Audit%20Report.pdf) |
| Nov 2025 | Cantina | [`Infrared Operations & Future Vaults Security Review.pdf`](./audits/Infrared%20Operations%20%26%20Future%20Vaults%20Security%20Review.pdf) |
| Nov 2025 | Cantina | [`infraredContractsSecurityReview.pdf`](./audits/infraredContractsSecurityReview.pdf) |
| Nov 2025 | Cantina | [`infrared_contract_security_review.pdf`](./audits/infrared_contract_security_review.pdf) |
| Nov 2025 | Cantina | [`infrared_security_review_12_11_2025.pdf`](./audits/infrared_security_review_12_11_2025.pdf) |
| Nov 2025 | Cantina | [`Infrared Smart Contract Security Assessment.pdf`](./audits/Infrared%20Smart%20Contract%20Security%20Assessment.pdf) |
| Nov 2025 | Spearbit | [`Infrared OFT Adapter Security Review.pdf`](./audits/Infrared%20OFT%20Adapter%20Security%20Review.pdf) |
| Nov 2025 | Cantina | [`report-cantinacode-infrared-5.pdf`](./audits/report-cantinacode-infrared-5.pdf) |
| Nov 2025 | Cantina | [`report-cantinacode-infrared-pr647.pdf`](./audits/report-cantinacode-infrared-pr647.pdf) |
| Dec 2025 | Cantina | [`report-cantinacode-infrared-1201.pdf`](./audits/report-cantinacode-infrared-1201.pdf) |
| Jan 2026 | Cantina | [`cantinacode-24.01.2026.pdf`](./audits/cantinacode-24.01.2026.pdf) |

### AI-Assisted Audit

An AI-assisted security review was conducted with findings and responses documented in [`docs/AI_AUDIT_NOTES.md`](./docs/AI_AUDIT_NOTES.md).

Published security advisories are available on the [GitHub Security tab](https://github.com/infrared-dao/infrared-contracts/security/advisories).

---

## Security Patches

Confirmed vulnerabilities will be patched as soon as responsibly possible. The general process:

1. Triage and confirm the report
2. Develop and internally review a fix
3. Deploy fix to testnet and verify
4. Coordinate disclosure timing with the reporter
5. Deploy fix to mainnet via governance multisig
6. Publish a GitHub advisory after the fix is live

For critical issues, emergency pause functionality is available:
- Per-vault: `pauseStaking(asset)` — requires `PAUSER_ROLE`
- Protocol-wide: governance multisig can pause all vaults

---

## Known Security Assumptions

The protocol's security relies on the following assumptions. Issues that require violating these are generally out of scope:

- **Governance multisig integrity** — the Safe multisig threshold is maintained and no threshold number of signers are compromised
- **Keeper key security** — keeper wallets are not compromised; a compromised keeper can disrupt operations but cannot steal funds
- **Berachain consensus** — the underlying Berachain consensus layer operates correctly; beacon chain proofs used for iBERA deposits/withdrawals are valid
- **Whitelisted token safety** — only tokens approved by governance are whitelisted; malicious tokens added via governance are a governance issue, not a contract bug
- **Oracle integrity** — the EIP-4788 beacon roots precompile returns correct data

---

## Legal

Blockchain is a nascent technology and carries a high level of risk and uncertainty. Infrared Finance makes certain software available under open source licenses, which disclaim all warranties in relation to the project and which limits the liability of Infrared Finance. Subject to any particular licensing terms, your use of the project is governed by the terms found at https://infrared.finance/terms (the "Terms"). As set out in the Terms, you are solely responsible for any use of the project and you assume all risks associated with any such use. This Security Policy in no way evidences or represents an ongoing duty by any contributor, including Infrared Finance, to correct any issues or vulnerabilities or alert you to all or any of the risks of utilizing the project.
