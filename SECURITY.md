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
- `src/periphery/` — RewardDistributor, IRRewardDistributor, IRAuction, MerkleDistributor, CuttingBoardDutchAuction, CuttingBoardManager

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

| Auditor | Scope | Report |
|---------|-------|--------|
| Zellic | Core protocol (initial) | [`audits/Infrared - Zellic Audit Report.pdf`](./audits/Infrared%20-%20Zellic%20Audit%20Report.pdf) |
| Zellic | Berachain core integration | [`audits/Infrared Berachain Core Integration - Zellic Audit Report.pdf`](./audits/Infrared%20Berachain%20Core%20Integration%20-%20Zellic%20Audit%20Report.pdf) |
| Zenith | Full protocol | [`audits/Zenith Audit Report - Infrared Finance.pdf`](./audits/Zenith%20Audit%20Report%20-%20Infrared%20Finance.pdf) |
| Cantina (code review) | Core & staking | [`audits/report-cantinacode-infrared.pdf`](./audits/report-cantinacode-infrared.pdf) |
| Cantina (code review) | Follow-up review | [`audits/report-cantinacode-infrared-1.pdf`](./audits/report-cantinacode-infrared-1.pdf) |
| Cantina (competition) | Full protocol | [`audits/report-competition-infrared-contracts.pdf`](./audits/report-competition-infrared-contracts.pdf) |

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
