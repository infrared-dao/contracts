# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Infrared Protocol is a liquid staking infrastructure for Berachain's Proof-of-Liquidity (PoL) system. It provides two primary liquid staking derivatives:
- **iBGT**: Liquid staked representation of BGT (Berachain Governance Token)
- **iBERA**: Liquid staked representation of BERA (native gas token)

The protocol enables users to maintain liquidity while earning PoL rewards and participating in validator operations.

## Development Commands

### Using the Makefile (Recommended)

The repository includes a comprehensive Makefile that streamlines common operations:

```bash
# Show all available commands
make help

# Development workflow
make dev-setup           # Setup development environment
make dev-test            # Build and test
make dev-check           # Run all checks (format + lint + test)

# Building and testing
make build               # Build contracts
make build-production    # Build with production settings
make test                # Run all tests
make test-unit           # Run unit tests only
make test-integration    # Run integration tests
make test-coverage       # Generate coverage report

# Code quality
make format              # Format Solidity files
make format-check        # Check formatting
make lint                # Run Slither

# State monitoring
make health-check NETWORK=mainnet        # Complete health check
make check-all NETWORK=mainnet           # Display all state
make check-exchange-rate NETWORK=mainnet # Check iBERA/BERA rate

# Keeper operations (requires KEEPER_ROLE)
make keeper-harvest NETWORK=mainnet      # Run all harvests
make keeper-deposit-validator NETWORK=mainnet

# Governance operations (requires multisig)
make gov-add-validator PUBKEY=0x... OPERATOR=0x... NETWORK=mainnet
make gov-whitelist-token TOKEN=0x... NETWORK=mainnet
make gov-update-fee FEE_TYPE=0 FEE=50000 NETWORK=mainnet
```

**Quick Reference:** See `MAKEFILE_REFERENCE.md` for command quick reference
**Full Guide:** See `OPERATIONS.md` for detailed operational procedures

### Direct Forge Commands

```bash
# Build contracts
forge build

# Build with production optimization
forge build --profile production

# Clean build artifacts
forge clean

# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run tests with increased verbosity (useful for debugging)
forge test -vvv

# Run specific test file
forge test --match-path tests/unit/core/Infrared/InfraredTest.t.sol

# Run specific test function
forge test --match-test testFunctionName

# Run fork tests (requires RPC_URL environment variable)
forge test --fork-url $RPC_URL_TESTNET

# Generate coverage report
forge coverage

# Generate detailed HTML coverage report
forge coverage --report lcov && genhtml lcov.info -o coverage
```

### Code Quality

```bash
# Format code
forge fmt

# Check formatting without modifying files
forge fmt --check

# Run static analysis (requires Slither)
slither .
```

### Deployment and Scripts

Scripts are organized in `script/` directory:
- `script/deploy/` - Initial deployment scripts
- `script/upgrades/` - Upgrade scripts for different contract versions
- `script/keeper/` - Keeper automation scripts
- `script/gov/` - Governance operation scripts

Run scripts with:
```bash
forge script script/path/to/Script.s.sol --rpc-url $RPC_URL --broadcast

# Or use Makefile wrappers:
make keeper-harvest NETWORK=mainnet
make gov-add-validator PUBKEY=0x... OPERATOR=0x... NETWORK=mainnet
```

## Architecture

### Core Module (`src/core/`)

The core module manages BGT accumulation, iBGT issuance, and reward distribution through Berachain's PoL system.

**Key Contracts:**

- **`Infrared.sol`**: Main coordinator contract that manages validators, vaults, and reward distribution. Handles BGT claiming, iBGT conversion, and bribe collection. Uses ERC-7201 storage pattern for upgradeability with three storage locations:
  - `ValidatorStorage` (VALIDATOR_STORAGE_LOCATION): Validator management
  - `VaultStorage` (VAULT_STORAGE_LOCATION): Vault registry and configuration
  - `RewardsStorage` (REWARDS_STORAGE_LOCATION): Reward distribution tracking

- **`InfraredVault.sol`**: Manages user staking into BerachainRewardsVaults. Each vault handles a specific staking token and accumulates BGT rewards. Extends MultiRewards to support up to 10 reward tokens per vault.

- **`BribeCollector.sol`**: Collects and auctions PoL bribes from BerachainRewardsVaults. Auction proceeds are distributed to validators and iBGT holders.

- **`InfraredDistributor.sol`**: Distributes iBGT rewards to Infrared validators using a snapshot-based system for cumulative reward tracking.

- **`MultiRewards.sol`**: Base contract providing multi-token reward distribution logic, supporting diverse incentive structures.

**Key Libraries:**

- `ValidatorManagerLib`: Manages validator registration, boost operations, and validator set operations
- `VaultManagerLib`: Handles vault registration, reward token management, and vault operations
- `RewardsLib`: Implements reward harvesting logic for base rewards, boost rewards, bribes, and operator rewards

**Reward Flow:**
1. Users deposit → InfraredVaults stake into BerachainRewardsVaults
2. BGT rewards accumulate → Infrared claims centrally
3. BGT converts to iBGT → Distribution to vault stakers
4. Base rewards split between wiBERA vault and validator distributor
5. Boost rewards from BGT delegation → iBGT holders
6. Bribes auctioned → Proceeds to validators and protocol

### Staking Module (`src/staking/`)

Provides liquid staking for BERA through queue-based operations.

**Key Contracts:**

- **`InfraredBERA.sol`**: Main liquid staking coordinator. Mints/burns iBERA tokens, manages validator stakes, and coordinates with depositor/withdrawor contracts. Uses compound() internally to reinvest EL rewards (priority fees + MEV) before minting/burning.

- **`InfraredBERADepositor.sol`**: Manages deposit queue and executes BERA deposits to Berachain's deposit precompile. Distributes deposits across validators.

- **`InfraredBERAWithdrawor.sol`**: Handles withdrawal queue, coordinates validator unstaking, and manages stake rebalancing between validators.

- **`IBERAFeeReceivor.sol`**: Collects priority fees and MEV from validators. Splits between treasury and autocompounding into the staking pool.

**Key Flows:**
- **Deposit**: BERA → deposit queue → validator staking → mint iBERA
- **Withdraw**: Burn iBERA → withdrawal queue → validator unstaking → claim BERA
- **Fees**: Validator rewards → FeeReceivor → split (treasury/autocompound) → reinvest

**Accounting**:
- `deposits`: Total BERA tracked by the system
- `pending()`: BERA in queues not yet sent to CL
- `confirmed()`: BERA confirmed deposited to CL (deposits - pending)
- Exchange rate: `(deposits * shares) / totalSupply`

### Upgradeable Architecture

The protocol uses UUPS (Universal Upgradeable Proxy Standard) pattern via OpenZeppelin's upgradeable contracts:

- **Storage Layout**: Contracts use ERC-7201 namespaced storage to prevent storage collisions across upgrades
- **Upgrade Safety**: All state variables are stored in namespaced structs accessed via `_validatorStorage()`, `_vaultStorage()`, and `_rewardsStorage()` helper functions
- **Storage Gaps**: 40-slot `__gap` arrays reserve space for future state variables
- **Upgrade Scripts**: Located in `script/upgrades/` organized by contract and version

**Upgrading Contracts:**
1. Harvest all rewards before upgrading to prevent accounting issues
2. Test upgrade on testnet using scripts in `script/upgrades/`
3. Verify storage layout compatibility using `forge inspect --storage-layout`
4. Execute upgrade through governance via Safe multisig

### Libraries and Utilities

- **`ValidatorManagerLib`**: Validator registration, boost management (queue/cancel/activate/drop), and validator operations
- **`VaultManagerLib`**: Vault creation, reward token management, pausing, and recovery functions
- **`RewardsLib`**: Harvest logic for base/boost/bribe/operator rewards with fee calculations
- **`Upgradeable.sol`**: Base contract with role-based access control (GOVERNANCE_ROLE, KEEPER_ROLE, PAUSER_ROLE)
- **`DataTypes.sol`** and **`Errors.sol`**: Centralized type definitions and error messages
- **`BeaconRootsVerify.sol`**: Consensus layer verification utilities

## Important Patterns and Conventions

### Solidity Conventions (from GUIDELINES.md)

- **State Variables**: All state variables must be private with underscore prefix for internal/private
- **Virtual Functions**: Functions should be declared virtual to allow overriding in upgrades
- **Events**: Emitted immediately after state changes, named in past tense (exceptions for ERC standards)
- **Custom Errors**: Follow EIP-6093 rationale with domain prefixes (e.g., "ERC20", "Governor")
- **Interfaces**: Prefixed with capital "I" (e.g., `IInfrared`, `IInfraredVault`)
- **Abstract Contracts**: Mark contracts not intended for standalone use as abstract
- **Unchecked Blocks**: Must include comments explaining why overflow is impossible

### Testing Standards (from GUIDELINES.md)

- Tests are as important as the code itself - write for comprehensiveness and reviewability
- Every addition/change must come with relevant comprehensive tests
- Test coverage must be kept as close to 100% as possible
- Use property-based testing (fuzzing) for math-heavy code
- Unit tests in `tests/unit/`, fork tests in `tests/e2e/`, invariant tests in `tests/invariant/`
- No flaky tests are acceptable

### Access Control

Three primary roles managed via OpenZeppelin AccessControl:

1. **GOVERNANCE_ROLE**: High-level protocol parameters, vault management, validator operations, fee configuration
2. **KEEPER_ROLE**: Operational tasks like validator boost management, cutting board updates, reward distribution
3. **PAUSER_ROLE**: Emergency pause functionality for staking operations

### Fee System

Protocol charges fees on different harvest operations (configured via `updateFee(FeeType, uint256)`):

- Fee rates in units of 1e6 (hundredths of 1 bip)
- `chargedFeesOnRewards()` splits rewards between recipient, voter vault, and protocol
- Always harvest all associated rewards before updating fee rates to prevent accounting issues
- Accumulated protocol fees tracked in `protocolFeeAmounts` mapping, claimable via `claimProtocolFees()`

### Reward Token Whitelisting

- Central whitelist managed in `Infrared.sol` via `updateWhiteListedRewardTokens()`
- Only whitelisted tokens can be added as vault rewards or accepted as bribes
- Prevents interaction with malicious tokens that could break reward distribution
- WBERA and HONEY whitelisted by default at initialization

## Development Workflow

### Adding New Validators

```solidity
// 1. Harvest existing rewards first
infrared.harvestBase();
infrared.harvestOperatorRewards();

// 2. Add validators (governance)
ValidatorTypes.Validator[] memory validators = ...;
infrared.addValidators(validators);

// 3. Configure cutting board for validator (keeper)
IBeraChef.Weight[] memory weights = ...;
infrared.queueNewCuttingBoard(pubkey, startBlock, weights);
```

### Registering New Vaults

```solidity
// 1. Register vault for staking token
IInfraredVault vault = infrared.registerVault(stakingTokenAddress);

// 2. Add additional reward tokens (optional, governance)
infrared.addReward(stakingTokenAddress, rewardTokenAddress, rewardsDuration);

// 3. Add incentives to vault (anyone)
infrared.addIncentives(stakingTokenAddress, rewardTokenAddress, amount);
```

### Harvesting Rewards

Order matters for bribe collection:

```solidity
// 1. Harvest bribes to Infrared contract
address[] memory tokens = [wbera, honey];
infrared.harvestBribes(tokens);

// 2. Collector auctions bribes and calls back
collector.claimFees();

// 3. Infrared distributes auction proceeds (called by collector)
// infrared.collectBribes() - called automatically by collector
```

### Emergency Procedures

```bash
# Pause staking on specific vault (pauser role)
infrared.pauseStaking(assetAddress);

# Unpause staking (governance role)
infrared.unpauseStaking(assetAddress);

# Remove malicious reward token (WARNING: loses unclaimed rewards)
infrared.removeReward(stakingToken, maliciousRewardToken);

# Recover stuck ERC20 tokens
infrared.recoverERC20(recipient, tokenAddress, amount);
infrared.recoverERC20FromVault(stakingToken, recipient, tokenAddress, amount);
```

## Common Pitfalls

1. **Harvest Before Validator Changes**: Always call `harvestBase()` and `harvestOperatorRewards()` before adding/removing validators to prevent reward accounting issues

2. **Fee Updates**: Harvest all associated rewards before updating fees to avoid accounting discrepancies

3. **Storage Gaps**: When adding new state variables to upgradeable contracts, reduce `__gap` array size accordingly

4. **Reward Token Limits**: InfraredVaults support maximum 10 reward tokens. Attempting to add more will revert.

5. **BGT Conversion**: BGT must be converted to iBGT through Infrared.sol using `harvestVault()`. Direct transfers may not be properly tracked.

6. **Withdrawal Queue**: iBERA withdrawals are queue-based and not instant. Users must wait for validator unstaking and then claim.

7. **Compound Before Mint/Burn**: `InfraredBERA.mint()` and `burn()` call `compound()` internally to ensure accurate share calculations

8. **ERC-7201 Storage**: Access storage only via helper functions (`_validatorStorage()`, `_vaultStorage()`, `_rewardsStorage()`) to maintain upgrade safety

## Key Integration Points

### Berachain Protocol Interfaces

- **`IBerachainBGT`**: BGT token with boost/delegation functionality
- **`IBeraChef`**: Manages validator RewardAllocations (cutting boards)
- **`IBerachainRewardsVault`**: PoL reward vaults where users stake LP tokens
- **`IBerachainRewardsVaultFactory`**: Creates new reward vaults

### External Dependencies

- OpenZeppelin Upgradeable contracts (v5.0.2)
- Solmate for optimized ERC20 operations
- Berachain contracts from `@berachain` package
- Forge Standard Library for testing

## Resources

- Architecture Diagrams: `Architecture.png` and Excalidraw link in README
- Module Documentation: `src/core/README.md`, `src/staking/README.md`
- Deployment Addresses: `DEPLOYMENTS.md`, `deployments-bepolia.md`
- Security: `SECURITY.md` for bug bounty and responsible disclosure
- Contributing: `CONTRIBUTING.md` for contribution guidelines
- Auto-generated Docs: https://infrared-dao.github.io/infrared-contracts

## Notes

- Solidity version: 0.8.26 with Cancun EVM
- Optimizer: Enabled (1 run for default, 50 runs for production profile)
- Test directory: `tests/` (not standard `test/`)
- iBGT vault (ibgtVault) is special: created automatically when `setIBGT()` is called
- Voting/veTokenomics contracts in `src/voting/` are excluded from linting
