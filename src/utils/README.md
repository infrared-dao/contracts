# Utils Module

Shared libraries, base contracts, and helper utilities used throughout the Infrared protocol. These are not standalone deployable contracts — they are imported by core, staking, and periphery contracts.

## Contents

### `Upgradeable.sol`

Abstract base contract inherited by all upgradeable contracts in the protocol.

**Extends:** `UUPSUpgradeable`, `PausableUpgradeable`, `AccessControlUpgradeable` (OpenZeppelin v5)

**Roles:**

| Constant | Description |
|----------|-------------|
| `GOVERNANCE_ROLE` | Protocol configuration, vault/validator management, fee updates |
| `KEEPER_ROLE` | Operational tasks: boost management, reward distribution, cutting board updates |
| `PAUSER_ROLE` | Emergency pause of staking operations |

**Modifiers:** `onlyKeeper`, `onlyGovernor`, `onlyPauser`, `whenInitialized`

**Upgrade authorization:** `_authorizeUpgrade()` is restricted to `GOVERNANCE_ROLE`, ensuring only governance can push contract upgrades.

**Initialization:** All inheritors call `__Upgradeable_init(governance, keeper)` which grants roles and enables upgrade safety.

---

### `Errors.sol`

Centralized library of all custom errors used across the protocol. Grouping all errors here provides a single reference point and avoids selector collisions.

**Error domains:**

| Domain | Examples |
|--------|---------|
| General | `ZeroAddress`, `ZeroAmount`, `UnderFlow`, `InvalidArrayLength`, `AlreadySet` |
| Access | `NotPauser`, `Unauthorized` |
| ValidatorSet | `ValidatorAlreadyExists`, `ValidatorDoesNotExist`, `FailedToAddValidator` |
| InfraredVault | `MaxNumberOfRewards`, `IBGTNotRewardToken`, `StakedInRewardsVault`, `RewardRateDecreased` |
| Infrared | `VaultNotSupported`, `VaultNotStaked`, `InvalidFee`, `BGTBalanceMismatch`, `BoostExceedsSupply` |
| iBERA | `InvalidAmount`, `WithdrawalsNotEnabled`, `ExceedsMaxEffectiveBalance`, `AlreadyFinalised`, `StaleProof` |

See the file directly for the full list.

---

### `DataTypes.sol`

Minimal shared type definitions.

```solidity
struct Token {
    address tokenAddress;
    uint256 amount;
}

address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
```

`NATIVE_ASSET` is used as a sentinel address to represent native BERA (ETH equivalent) in contexts where both ERC-20 and native asset handling is needed.

---

### `BeaconRootsVerify.sol`

Library for verifying Ethereum consensus layer (beacon chain) state on-chain using the EIP-4788 Beacon Roots precompile (`0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02`).

Used by `InfraredBERA` to verify validator state (registration, effective balance, withdrawal credentials) without trusting off-chain data.

**Key structs:**

| Struct | Fields |
|--------|--------|
| `BeaconBlockHeader` | `slot`, `proposerIndex`, `parentRoot`, `stateRoot`, `bodyRoot` |
| `Validator` | `pubkey`, `withdrawalCredentials`, `effectiveBalance`, `slashed`, activation/exit epochs |

**Merkle tree constants:**
- `VALIDATORS_INDEX = 9` — beacon state generalized index for the validators list
- `BALANCES_INDEX = 10` — beacon state generalized index for the balances list
- `VALIDATOR_PROOF_DEPTH = 41` — proof depth for validator inclusion
- `BALANCE_PROOF_DEPTH = 39` — proof depth for balance inclusion

**Key functions:**

| Function | Description |
|----------|-------------|
| `getParentBeaconBlockRoot(slot)` | Fetch beacon root from EIP-4788 precompile |
| `verifyBeaconHeaderMerkleRoot(...)` | Verify a beacon block header against a known root |
| `verifyStateRoot(...)` | Verify the beacon state root from a header |
| `verifyValidator(...)` | Prove validator inclusion in the validators tree |
| `verifyValidatorBalance(...)` | Prove validator balance inclusion |
| `verifyValidatorPublicKey(...)` | Verify a validator's pubkey matches |
| `verifyValidatorEffectiveBalance(...)` | Verify effective balance for a validator index |
| `verifyValidatorWithdrawalAddress(...)` | Verify withdrawal credentials for a validator |

---

### `MerkleTree.sol`

Pure library for Merkle tree construction and proof verification. Uses `sha256` (required for Ethereum beacon chain compatibility).

```solidity
// Build a Merkle root from an array of leaves
function calculateMerkleRoot(bytes32[] memory leaves) returns (bytes32 root)

// Verify a single leaf is included in a tree
function verifyMerkleLeaf(bytes32 root, bytes32 leaf, bytes32[] memory proof) returns (bool)

// Reconstruct root from a leaf + proof path (for on-chain verification)
function calculateMerkleRootFromProof(bytes32 leaf, bytes32[] memory proof, uint256 index) returns (bytes32)
```

**Note:** `calculateMerkleRoot` requires an even-length leaf array. Callers must pad with a zero leaf if needed.

---

### `EndianHelper.sol`

Little-endian conversion helpers for compatibility with the Ethereum consensus layer, which encodes many values (deposits, balances) in little-endian byte order.

```solidity
// Convert uint256 to 32-byte little-endian representation
function toLittleEndian(uint256 value) returns (bytes32)

// Encode bool as 32-byte little-endian
function toLittleEndian(bool value) returns (bytes32)

// Reverse byte order of a uint64 (LE → BE or BE → LE)
function reverseBytes64(uint64 value) returns (uint64)
```

Used primarily in `InfraredBERADepositor` when constructing deposit data for the Berachain deposit precompile.

---

### `InfraredVaultDeployer.sol`

Library that encapsulates the `CREATE` deployment of new `InfraredVault` contracts. Isolated into a library so the deployment logic can be tested and audited independently from vault management.

```solidity
function deploy(address stakingToken, uint256 rewardsDuration) returns (address vault)
```

Called by `VaultManagerLib` when `Infrared.registerVault()` creates a new vault.

## Usage Notes

- Import `Upgradeable.sol` as the base for any new upgradeable contract in the protocol
- Add new errors to `Errors.sol` — do not define inline custom errors in individual contracts
- Use `DataTypes.Token` when returning multiple token/amount pairs from view functions
- `BeaconRootsVerify` functions are gas-intensive due to merkle proof verification; avoid calling them in non-critical paths
