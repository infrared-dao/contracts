# EVM Audit — DeFi Staking & Liquid Staking Derivative (LSD) Security

## Overview
This audit skill focuses on examining vulnerabilities in staking-related protocols, particularly liquid staking derivatives and restaking mechanisms.

**Use Case**: Audit liquid staking protocols like Lido, Rocket Pool, Frax, EigenLayer, and similar systems like Infrared Protocol.

---

## Staking/LSD Audit Checklist for Infrared Protocol

### Liquid Staking Derivative (LSD) Integration Risks

#### stETH (Lido)
- **Rebasing token accounting drift**: stETH balances change daily via oracle reports. Protocols must use wstETH wrapper instead to maintain consistent internal accounting.
- **Rebase handling during conversions**: Wrapping/unwrapping between stETH and wstETH requires accounting for rebases that occur between operations.
- **Withdrawal queue and delays**: Lido withdrawals involve multi-day/week queues, NFT receipts, and amount limits—not instant liquidity.

#### rETH (Rocket Pool)
- **Burn reverts on empty deposit pool**: "rETH.burn() reverts if RocketDepositPool is empty" requiring graceful error handling.
- **Non-monotonic rate decreases**: "rETH/ETH rate can decrease due to validator slashing"—don't assume value only appreciates.
- **Consensus attack risk**: RPL node operators submitting exchange rate data without sanity bounds enables manipulation.

#### cbETH (Coinbase)
- **Blacklisting freezes funds**: "Blacklist applies to transfers, approvals, mints, and burns"—shared vaults risk total asset freeze.
- **Oracle-controlled rate changes**: A small set of addresses can alter exchange rates instantly, creating manipulation vectors.
- **Rate decreases possible**: Unlike stETH, cbETH explicitly supports value depreciation.

#### sfrxETH (Frax)
- **Temporary rate detachment**: "sfrxETH can temporarily detach from frxETH" during Frax multisig reward operations, enabling MEV exploitation.

---

### LSD Protocol Design Vulnerabilities

#### Validator & Deposit Risks
- **WithdrawCredentials front-running**: "Malicious validator can front-run deposit transaction to set their own WithdrawCredentials, stealing all future withdrawals."
- **Deposit loop gas exhaustion**: Batch depositing to multiple validators via loops can exceed block gas limits.
- **Validator iteration gas limits**: Iterating all validators for rewards/slashing calculations hits gas limits as validator count grows.

#### Slashing & Operator Risks
- **Operator collateral withdrawal during validation**: Operators withdrawing bonded collateral while validators remain active eliminates slashing penalties.
- **Slashing penalty exceeds operator balance**: When penalties exceed operator stakes, user funds cover the shortfall.
- **Derivative price oracle sandwiching**: Price update transactions can be sandwiched for attacker profit.

#### Token & Pool Risks
- **Derivative burn/rate decrease handling**: Protocols must support burning proportional tokens or rate adjustments during slashing.
- **Inflation attack on empty pools**: New staking pools without initial deposits or virtual shares enable share price manipulation.

---

### Staking Rewards Mechanisms

- **Reward rate dilution**: Calling `notifyRewardAmount(0)` extends reward periods, compounding dilution ~20% per call.
- **Expired token rewards**: Worthless vault tokens continue earning rewards when staking contracts ignore token expiry.
- **Missing totalSupply sync**: Reward miscalculations occur when fee mints happen between integral updates and claims.
- **Disabled receiver token loss**: Disabled reward receivers blocking emissions cause allocated tokens to become permanently lost.

---

### Staking Lock Mechanisms

- **Stake-for-others lock reduction**: "Staking on behalf of another user resets or extends lock timing unintentionally."
- **Liquid wrapper lock bypass**: Smart contracts wrapping locked positions with liquid receipts completely defeat time-locks.
- **Improper vesting enforcement**: Rewards claimed before vesting or delayed beyond schedules indicate missing validation.
- **Stuck/blocked withdrawals**: External dependencies in withdrawal functions can permanently trap assets.
- **Internal reward token manipulation**: Protocol-minted reward tokens lack external price anchoring, enabling value manipulation.

---

### Vault Strategy Risks

- **Flash deposit-harvest-withdraw**: Attackers capturing yield by depositing before harvests require time-weighted accounting protections.
- **Strategy loss handling failure**: Strategies without loss support cause withdrawal reverts or incorrect return amounts.
- **Black swan protocol exploits**: Strategies depositing into external protocols must handle total loss via emergency withdrawal mechanisms.
- **Locked strategy funds**: Strategies unable to return funds (e.g., lending markets at 100% utilization) block vault withdrawals.

---

### Advanced Protocol-Level Risks

#### Accounting & Verification
- **stakedButUnverifiedNativeETH accounting error**: Subtracting `effectiveBalance` instead of 32 ETH leaves phantom balance, overstating TVL and inflating token price.
- **BeaconChainProofs height mismatch post-Deneb**: Upgrade added blob fields, increasing tree height to 5; old proofs fail, second pre-images enable fabricated proofs.

#### Operational Vulnerabilities
- **Infinite loop from missing strategy params**: Strategies not in `_strategyParams` cause `continue` statements without loop counter increments, creating DoS.
- **Cooldown period slashing evasion**: Deposits reducible after validation without invalidating nodes enables collateral drainage.
- **Double rounding in mint calculations**: Sequential multiply-divide operations compound precision loss; restructure into single calculation.

#### Advanced Attack Vectors
- **Deterministic address breaks from metadata changes**: Compiler version/settings updates change `create2()` addresses, making funds inaccessible.
- **TVL manipulation via forced delegation errors**: Share tracking flaws after forced undelegations enable exchange rate manipulation and flash loan drains.

---

## Infrared Protocol Specific Checks

Given Infrared Protocol's architecture:

### iBERA Liquid Staking
- Verify deposit queue mechanisms prevent gas exhaustion
- Check validator selection algorithms for fair distribution
- Ensure withdrawal queue handles multiple validator unstaking
- Validate exchange rate calculations during validator slashing events

### iBGT Governance Token
- Check BGT accumulation and distribution logic
- Verify reward harvesting doesn't create precision loss
- Ensure boost delegation mechanisms prevent manipulation
- Validate cutting board auction systems

### Upgrade Safety
- Ensure harvest operations complete before upgrades
- Verify storage layout preservation across versions
- Check initialization functions prevent re-initialization attacks

### Access Control
- Validate GOVERNANCE_ROLE, KEEPER_ROLE, PAUSER_ROLE separation
- Ensure emergency pause functions work correctly
- Check fee update mechanisms have proper bounds

---

This checklist should be applied systematically to all staking-related contracts in the Infrared Protocol ecosystem.