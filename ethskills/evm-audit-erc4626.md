# EVM Audit — ERC4626 Vault Standard Security

## Overview
This audit skill focuses on ERC4626 vault standard vulnerabilities including inflation attacks, rounding direction, share price manipulation, first depositor attacks, compliance checks, and cross-chain vault issues.

**Use Case**: Audit any ERC4626 vault implementation or protocols integrating with ERC4626-compliant vaults like Infrared Protocol's vault system.

---

# ERC4626 Vault Security Audit Checklist

## Core Vulnerability Categories

### 1. First Depositor & Inflation Attacks
- **Classic inflation vector**: Attacker deposits minimal amount (1 wei), receives 1 share, then donates substantial assets directly to vault. Subsequent depositors suffer rounding losses and receive zero shares.
- **Mitigation strategies**: virtual shares/assets offsets, minimum deposit requirements, protocol seed deposits, or dead share mechanisms (Uniswap V2 pattern)
- **Detection focus**: identify vaults accepting first deposits without safeguards

- **Inconsistent first-deposit formulas**: vault may apply different conversion math in `previewDeposit` versus `previewMint` when supply equals zero
- **Detection focus**: compare code paths between deposit and mint functions when `totalSupply == 0`

- **Virtual offset asymmetry**: "virtual shares must equal virtual assets" to prevent rounding exploitation causing share deflation

---

### 2. Rounding Direction Compliance (EIP-4626 Standard)

All rounding must systematically favor the protocol:

| Function | Direction | Rationale |
|----------|-----------|-----------|
| `convertToAssets` / `convertToShares` | DOWN | informational, always protocol-favorable |
| `previewDeposit` | DOWN | yields fewer shares to depositor |
| `previewMint` | UP | requires more assets from depositor |
| `previewWithdraw` | UP | burns additional shares |
| `previewRedeem` | DOWN | distributes fewer assets |

**Risk**: "dust extraction via deposit/withdraw cycling" if any preview rounds user-favorably

---

### 3. Share Price Manipulation

- **Direct transfer exploitation**: vaults relying on `balanceOf(address(this))` in `totalAssets()` allow external token transfers to artificially inflate conversion rates
- **Solution**: track assets through internal accounting rather than balance queries

- **Unrealized yield miscounting**: "totalAssets should be pessimistically calculated" excluding unconfirmed gains

- **External dependency risk**: oracles and strategy contracts called within `totalAssets()` introduce manipulation vectors

- **Profit-lock misrepresentation**: if vault implements drip/lock mechanisms, the "share price must reflect the locked amount, not the full amount"

---

### 4. Cross-Chain Complications

- **Burn/mint distortion**: LayerZero-style burns reduce source-chain supply while destination mints, temporarily inflating remaining holders' share value
- **Exploitation window**: users can withdraw at inflated rates during transit
- **Alternative**: implement lock/unlock approach instead

---

### 5. Edge Case Math Failures

| Edge Case | Vulnerability |
|-----------|---|
| `totalSupply == 0` and `totalAssets == 0` | division by zero errors |
| `totalAssets == 0` but `totalSupply > 0` | bad debt state |
| 1 wei vault remainder | rounding precision collapse |
| Single share from large deposit | minimal share redeemable for variable amounts |

---

### 6. Underlying Token Risks

- **Fee-on-transfer tokens**: deposit functions don't measure actual received amounts; vault receives fewer tokens than recorded
- **Rebase tokens**: vault accounting drifts without tracking rebases
- **ERC777 hooks**: enables reentrancy during transfers
- **Approval constraints**: USDT-style zero-approval requirements may cause standard `approve` calls to fail

---

### 7. Inheritance & Consistency Issues

- **Function override gaps**: modifying deposit logic without overriding `previewDeposit` creates divergence
- **Storage collisions**: inherited contract storage may corrupt vault storage layout

---

### 8. Permission & Admin Risks

- **Unbounded fee setting**: admin-adjustable fees without caps enable vault drainage
- **Direct fund extraction**: trusted roles with unauthorized withdrawal access
- **Pause/shutdown traps**: users cannot withdraw when vault is paused
- **Strategy liquidation**: emergency exit capability for all positions

---

### 9. Standard Compliance - Informational Functions

- **`convertToAssets`/`convertToShares` caller-invariance**: "must NOT vary by caller" and "must return the same value regardless of who calls them"
- **No slippage inclusion**: these functions show theoretical conversions only
- **Detection**: search for `msg.sender` references within these functions

---

### 10. Standard Compliance - Operational Constraints

- **`maxDeposit`/`maxMint` semantics**: represent protocol capacity, NOT token balance availability
- **Return values**: 0 when disabled, `type(uint256).max` when unlimited
- **Non-reversion requirement**: these must return 0 instead of reverting
- **Misaligned `previewDeposit`/`previewMint`**: verify both include vault fees but only preview functions include slippage

---

### 11. Fee Inversion Mathematics

When vaults charge deposit fees, fee-adjusted conversions require proper inversion:
- Forward: `shares = assets × (1 - fee) / pricePerShare`
- Reverse: `assets = shares × pricePerShare / (1 - fee)`

Inverted fee logic breaks deposit/withdrawal round-trip correctness.

---

### 12. Withdrawal Slippage Constraints

High-slippage illiquid strategies reduce withdrawal amounts below expected values. Risk mitigation requires "TVL limits so liquidation slippage stays manageable."

---

## Audit Methodology

1. **Trace mathematical flows**: verify rounding direction in all conversions
2. **Inspect `totalAssets()` logic**: confirm it includes yield, fees, and avoids balance-only calculations
3. **Check inheritance chains**: ensure all overridden functions maintain consistency
4. **Test edge states**: zero balances, single-unit holdings, pause conditions
5. **Examine token interactions**: verify compatibility with fee/rebase/hook-bearing assets
6. **Validate permissions**: confirm admin actions include appropriate bounds and safeguards

---

## Infrared Protocol Specific Checks

Given Infrared Protocol's vault architecture:

### InfraredVault Analysis
- Verify MultiRewards integration doesn't break ERC4626 compliance
- Check reward distribution doesn't affect share price calculations
- Ensure BGT reward harvesting properly updates vault accounting
- Validate vault pausing doesn't trap user funds

### Upgrade Safety
- Verify storage layout preservation across vault upgrades
- Check that upgrade functions don't break vault state
- Ensure proper initialization of new vault versions

### Integration Points
- Verify BerachainRewardsVault integration maintains accurate accounting
- Check that external reward token additions don't break internal logic
- Ensure bribe collection doesn't interfere with vault operations

Apply this checklist systematically to all vault-related contracts in the Infrared Protocol ecosystem.