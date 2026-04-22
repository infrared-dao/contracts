# Ethskills audit checklists

Claude-compatible audit skills from [ethskills.com](https://ethskills.com/)
([GitHub source](https://github.com/austintgriffith/evm-audit-skills)),
selected for the parts of EVM-land this repo touches.

## Files

| File | When to load |
|---|---|
| `evm-audit-master.md` | Always — routing table across all skills |
| `evm-audit-general.md` | Always — universal patterns (reentrancy, calls, math) |
| `evm-audit-defi-staking.md` | Reviewing `src/staking/` (iBERA, depositor, withdrawor) |
| `evm-audit-erc4626.md` | Reviewing `InfraredVault`, `MultiRewards`, any `src/core/` vault |
| `evm-audit-proxies.md` | Reviewing any upgradeable contract (ERC-7201 storage, `_authorizeUpgrade`) |

## Usage

- **Manual review:** read `evm-audit-master.md` first, then the
  specific skill for the contract type you're reviewing.
- **Scanner:** `make ai-security-scan` maps each `src/**.sol` file to
  the skills that apply. See `docs/AI_SECURITY.md`.

## Severity conventions (when writing up findings)

- **Critical** — third-party fund loss, no special conditions
- **High** — conditional fund loss or permanent service denial
- **Medium** — incorrect accounting or trust violation
- **Low** — best-practice gap without a direct loss vector
- **Info** — documentation / clarity

## Sources

- [ethskills.com](https://ethskills.com/)
- [austintgriffith/evm-audit-skills](https://github.com/austintgriffith/evm-audit-skills)
- Attribution within each skill file
