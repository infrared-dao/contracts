# EVM Audit — Proxy & Upgradeable Contract Security

## Overview
This audit skill focuses on proxy patterns, upgradeable contracts, and related security concerns including UUPS vulnerabilities, storage collisions, initialization issues, and metamorphic contract risks.

**Use Case**: Audit any upgradeable contract system including UUPS, Transparent Proxy, and Beacon patterns like those used in Infrared Protocol.

---

# Complete Proxy Audit Checklist for Upgradeable Contracts

## UUPS Proxy Security

### Access Control & Authorization
- Verify `_authorizeUpgrade()` enforces access control (e.g., `onlyOwner`). The absence of these checks is the most critical UUPS vulnerability, allowing arbitrary contract upgrades.
- Ensure implementation constructors call `_disableInitializers()` to prevent attackers from directly initializing implementations and gaining ownership.
- Confirm authorization mechanisms (owner, multi-sig, voting) remain functional across upgrades; switching schemas mid-deployment can permanently lock access.

### Dangerous Operations
- Scan for `selfdestruct` in implementation contracts—it executes in the proxy's context, destroying all proxies. Pre-Dencun chains remain vulnerable.
- Prohibit unprotected `delegatecall` in implementations; attackers can route calls to `selfdestruct` contracts indirectly.
- Verify upgrade functions like `upgradeToAndCall()` are not overridden without rigorous review of their access control and UUPS compliance.

### State & Storage Integrity
- Confirm implementations include `proxiableUUID()` and inherit UUPS upgrade logic; upgrading to non-UUPS contracts permanently bricks the proxy.
- Audit storage variable layout: additions, removals, reordering, or type changes corrupt existing data. Only append new variables at the end.
- Add `uint256[50] private __gap` to all parent contracts in inheritance chains to prevent child storage collision when parents evolve.
- Flag `immutable` declarations—their values embed in bytecode and are lost upon upgrades.

## Initialization Patterns

### Correct Initialization Flow
- Prohibit state-setting constructors in proxy implementations; use `initializer`-modified functions instead.
- Transition from non-upgradeable base contracts (`ReentrancyGuard`, `Pausable`, `ERC20`, `Ownable`) to their `Upgradeable` counterparts.
- Verify deployment scripts atomically call `initialize()` in the same transaction as proxy creation to prevent front-running attacks.
- Watch for `_initialized` slot reuse when proxy implementations change type, allowing unintended re-initialization.

## Transparent Proxy Patterns

### Function Selector Conflicts
- Check for 4-byte selector collisions between proxy admin functions and implementation functions, which can lock admins out of upgrades or expose unintended functionality.

## Metamorphic & CREATE2 Risks

### Self-Destruct + Redeployment
- Flag contracts deployed via CREATE2 that include `selfdestruct`. Post-deployment, they can be destroyed and replaced with malicious bytecode at the same address—a rug pull vector.
- Identify systems trusting contract addresses as identity without verifying code hashes, exposing them to bytecode swaps.
- Detect `isContract()` or `extcodesize` checks on addresses that could receive CREATE2 deployments. Pre-deployment addresses have no code, bypassing "no contracts" restrictions.
- Note that `extcodesize` returns 0 during contract constructor execution, allowing attackers to bypass contract-caller access controls.

## Storage Collision Patterns

### Data Layout Errors
- Audit index-based access to packed storage values, especially near 32-byte slot boundaries. Off-by-one errors cause reads from wrong slots.
- Verify paired data (weights + multipliers) packed across slots use aligned index offsets; misalignment maps wrong multipliers to tokens at boundaries.
- Identify state variable shadowing in inheritance hierarchies—Solidity creates distinct storage slots while the code appears to reference the same variable.

## Cross-Chain Considerations

- Account for asymmetric upgradability: contracts may be upgradeable on some chains (e.g., Polygon) but immutable on others (e.g., Ethereum). Multichain protocols must adapt accordingly.

---

## Advanced Upgrade Vulnerabilities

### Storage Layout Evolution
- **ERC-7201 Namespaced Storage**: Verify Infrared Protocol's use of namespaced storage prevents collisions between core storage and upgrade additions
- **Storage Gap Management**: Ensure `__gap` arrays are properly reduced when adding new variables to parent contracts
- **Type Changes**: Flagging any storage variable type changes between versions (e.g., `uint128` to `uint256`)

### Initialization Security
- **Re-initialization Prevention**: Check that upgrade scripts don't accidentally re-initialize already initialized contracts
- **Initialization Race Conditions**: Verify initialization happens atomically with proxy deployment
- **Multiple Initializer Pattern**: Ensure contracts with multiple initialization phases handle state correctly

### Access Control Across Upgrades
- **Role Preservation**: Verify that role-based access control (GOVERNANCE_ROLE, KEEPER_ROLE, etc.) is preserved across upgrades
- **Authorization Function Migration**: Ensure `_authorizeUpgrade()` logic is maintained or properly updated in new implementations
- **Emergency Procedures**: Check that pause/emergency functions remain functional after upgrades

## Implementation-Specific Risks

### UUPS Implementation Details
- **Upgrade Validation**: Verify implementation contracts validate they're being used as intended proxy targets
- **Implementation Protection**: Ensure implementation contracts can't be directly used (via `_disableInitializers()`)
- **Proxy Identity Consistency**: Check that proxy maintains consistent identity across upgrades

### Library and Dependency Management
- **Library Compatibility**: Verify external library versions remain compatible across upgrades
- **Dependency Chain Security**: Audit the entire inheritance chain for upgrade compatibility
- **Interface Consistency**: Ensure external interfaces remain stable across implementation versions

---

## Infrared Protocol Specific Checks

Given Infrared Protocol's UUPS architecture:

### Core Contract Upgrade Safety
- **Infrared.sol**: Verify storage layout preservation for ValidatorStorage, VaultStorage, and RewardsStorage
- **InfraredVault.sol**: Check MultiRewards integration maintains upgrade compatibility
- **InfraredBERA.sol**: Ensure compound() function state is preserved across upgrades

### ERC-7201 Storage Pattern Validation
- Verify `_validatorStorage()`, `_vaultStorage()`, and `_rewardsStorage()` helper functions maintain consistent storage locations
- Check that new storage additions use proper namespaced patterns
- Ensure storage location constants remain unchanged across upgrades

### Upgrade Workflow Security
- **Pre-Upgrade Requirements**: Verify harvest functions are called before upgrades to prevent accounting issues
- **Storage Layout Verification**: Use `forge inspect --storage-layout` comparisons between versions
- **Initialization Sequence**: Check proper initialization of new contract versions

### Access Control Preservation
- **Role Continuity**: Ensure GOVERNANCE_ROLE, KEEPER_ROLE, and PAUSER_ROLE assignments survive upgrades
- **Multisig Integration**: Verify Safe multisig can execute upgrade transactions
- **Emergency Controls**: Ensure pause functionality remains available during and after upgrades

### Integration Point Stability
- **BerachainRewardsVault**: Verify external integrations remain compatible
- **BGT Token Integration**: Check that BGT handling logic upgrades safely
- **Oracle Dependencies**: Ensure price feed integrations remain stable

Apply this checklist systematically to all upgradeable contracts in the Infrared Protocol ecosystem, with special attention to the ERC-7201 storage patterns and multi-contract upgrade coordination.