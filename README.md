# Infrared Protocol 🔴

[![pipeline](https://github.com/infrared-dao/infrared-contracts/actions/workflows/pipeline.yml/badge.svg)](https://github.com/infrared-dao/infrared-contracts/actions/workflows/pipeline.yml)
[![Slither analysis](https://github.com/infrared-dao/infrared-contracts/actions/workflows/slither.yml/badge.svg)](https://github.com/infrared-dao/infrared-contracts/actions/workflows/slither.yml)
[![Deploy Natspec docs to Pages](https://github.com/infrared-dao/infrared-contracts/actions/workflows/docs-deploy.yml/badge.svg)](https://github.com/infrared-dao/infrared-contracts/actions/workflows/docs-deploy.yml)

> **Liquid Staking Infrastructure for Berachain's Proof-of-Liquidity**

Infrared Protocol revolutionizes staking on Berachain by providing liquid staking derivatives (LSDs) that unlock the full potential of BGT and BERA while maintaining exposure to Proof-of-Liquidity rewards.

## 📋 Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Documentation](#documentation)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Development](#development)
- [Integration Guide](#integration-guide)
- [Testing](#testing)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

## Overview

The Infrared Protocol addresses critical limitations in Berachain's native staking system:

### The Problem
- BGT (Berachain Governance Token) lacks transferability and liquidity
- Validator staking requires technical expertise and significant capital
- Staked assets are locked, reducing capital efficiency

### Our Solution
- **IBGT**: A liquid staked representation of BGT that's fully transferable
- **IBERA**: Democratized validator staking through liquid staking tokens
- **Seamless Integration**: Tight coupling with Berachain's Proof-of-Liquidity system

## Key Features

- ✅ **Liquid Staking**: Convert BGT to IBGT and BERA to IBERA without lockups
- ✅ **POL Rewards**: Continue earning Proof-of-Liquidity inflation while staked
- ✅ **Validator Democratization**: Access validator rewards without running infrastructure
- ✅ **Composability**: Use liquid staking tokens across DeFi protocols
- ✅ **Bribes & Incentives**: Sophisticated reward distribution and bribe collection system

## Documentation

| Resource | Description |
|----------|-------------|
| [📚 Documentation](https://docs.infrared.finance) | Complete protocol documentation |
| [📍 Deployments](https://infrared.finance/docs/developers/contract-deployments) | Contract addresses by network |
| [🔍 Audits](https://infrared.finance/docs/audits) | Security audit reports |
| [📖 NatSpec Docs](https://infrared-dao.github.io/infrared-contracts) | Auto-generated contract documentation |

## Architecture

<details>
<summary>View Architecture Diagram</summary>

![Architecture](Architecture.png)

[Interactive Diagram →](https://link.excalidraw.com/l/1Tuu8vTTCh1/1f3jMvwGuuS)

</details>

### Contract Modules

#### 🔵 Core Contracts - POL Integration & BGT Management
[Full documentation →](https://github.com/infrared-dao/infrared-contracts/blob/develop/src/core/README.md)

The core module facilitates interaction with Berachain's Proof-of-Liquidity reward system, managing BGT accumulation, iBGT issuance, and reward distribution.

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **`Infrared.sol`** | Main coordination contract | • Validator registration & RewardAllocation configuration<br>• Centralized BGT claiming and iBGT conversion<br>• Manages `harvestBase` and `harvestBoostRewards` functions |
| **`InfraredVault.sol`** | User staking management | • Stakes assets into BerachainRewardsVaults<br>• Accumulates BGT rewards for conversion to iBGT<br>• Extends MultiRewards for diverse token support |
| **`InfraredDistributor.sol`** | Validator reward distribution | • Distributes iBGT rewards to Infrared validators<br>• Tracks rewards via snapshots for easy claiming<br>• Manages cumulative reward totals per validator |
| **`BribeCollector.sol`** | POL bribe management | • Collects bribes from BerachainRewardsVaults<br>• Auctions bribes with proceeds to validators & iBGT holders<br>• Governance-configurable parameters |
| **`MultiRewards.sol`** | Multi-token rewards base | • Supports up to 10 reward tokens per vault<br>• Enables varied incentive structures |

**Key Flows**: Users deposit → InfraredVaults stake into BerachainRewardsVaults → BGT rewards accumulate → Infrared claims & converts to iBGT → Distribution to stakers

#### 🟢 Staking Contracts - BERA Liquid Staking
[Full documentation →](https://github.com/infrared-dao/infrared-contracts/blob/develop/src/staking/README.md)

The staking module enables liquid staking of BERA (native gas token) through iBERA tokens, maintaining liquidity while participating in consensus.

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **`IBERA.sol`** | Liquid staking coordinator | • Mints/burns iBERA tokens representing staked BERA<br>• Manages validator stakes and autocompounding<br>• Configures protocol fee parameters |
| **`IBERADepositor.sol`** | Deposit queue management | • Queues and executes BERA deposits<br>• Interacts with Berachain's deposit precompile<br>• Distributes deposits across validators |
| **`IBERAWithdrawor.sol`** | Withdrawal processing | • Manages withdrawal queue and requests<br>• Handles validator stake rebalancing<br>• Coordinates with IBERAClaimor for claims |
| **`IBERAClaimor.sol`** | Secure claim mechanism | • Tracks user claim records<br>• Enables safe BERA transfers to users<br>• Supports batch processing |
| **`IBERAFeeReceivor.sol`** | Fee & MEV collection | • Receives priority fees and MEV from validators<br>• Splits between treasury and autocompounding<br>• Periodic fee sweeping into protocol |

**Key Flows**: 
- **Deposit**: BERA → IBERA contract → Queue → Validator staking → Receive iBERA
- **Withdraw**: Burn iBERA → Queue withdrawal → Process from validators → Claim BERA
- **Fees**: Validator rewards → IBERAFeeReceivor → Treasury/Autocompound split


## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) toolkit
- Git
- Make (recommended for streamlined operations)

### Installation

```bash
# Clone the repository
git clone https://github.com/infrared-dao/infrared-contracts.git
cd infrared-contracts

# Setup development environment (installs dependencies and creates .env)
make dev-setup

# Or manually:
forge install
cp .env.example .env
# Edit .env with your configuration

# Build contracts
make build
```

## Development

### Quick Start with Makefile

The repository includes a comprehensive Makefile that streamlines all operations. View all available commands:

```bash
make help
```

### Build & Compile

```bash
# Build contracts
make build

# Build with production optimization (50 runs)
make build-production

# Clean build artifacts
make clean

# Development cycle: build + test
make dev-test

# Full quality check: format + lint + test
make dev-check
```

### Code Quality

```bash
# Format Solidity files
make format

# Check formatting without modifying
make format-check

# Run static analysis (Slither)
make lint

# Create gas snapshot
make snapshot
```

## Integration Guide

### Installation for External Projects

Add Infrared to your Foundry project:

```bash
forge install infrared-dao/infrared-contracts
```

Update `foundry.toml`:

```toml
[dependencies]
infrared-contracts = { version = "1.0.0" }

[remappings]
"@infrared/=lib/infrared-contracts/src/"
```

---

### 1. iBERA Liquid Staking Integration

Integrate iBERA to enable users to stake BERA and maintain liquidity through the iBERA liquid staking token.

```solidity
pragma solidity ^0.8.19;

import {IInfraredBERAV2} from '@infrared/interfaces/IInfraredBERAV2.sol';
import {IInfraredBERAWithdrawor} from '@infrared/interfaces/IInfraredBERAWithdrawor.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title iBERA Staking Integration Example
 * @notice Demonstrates how to integrate iBERA liquid staking into your protocol
 */
contract IBERAIntegration {
    IInfraredBERAV2 public immutable ibera;
    IInfraredBERAWithdrawor public immutable withdrawor;

    /// @notice Emitted when a withdrawal is initiated
    event WithdrawalQueued(address indexed user, uint256 indexed nonce, uint256 amount);

    /// @notice Emitted when BERA is claimed from a withdrawal ticket
    event WithdrawalClaimed(address indexed user, uint256 indexed nonce, uint256 amount);

    constructor(address _ibera, address _withdrawor) {
        ibera = IInfraredBERAV2(_ibera);
        withdrawor = IInfraredBERAWithdrawor(_withdrawor);
    }

    /**
     * @notice Stake BERA and receive iBERA liquid staking tokens
     * @param receiver Address to receive the iBERA tokens
     * @return shares Amount of iBERA tokens minted
     */
    function stakeBERA(address receiver) external payable returns (uint256 shares) {
        // Preview how many shares will be minted
        uint256 expectedShares = ibera.previewMint(msg.value);
        require(expectedShares > 0, "Invalid mint amount");

        // Mint iBERA by sending BERA
        shares = ibera.mint{value: msg.value}(receiver);

        // The iBERA tokens are now in receiver's balance
        // They represent staked BERA + accrued staking rewards
    }

    /**
     * @notice Burn iBERA to queue BERA withdrawal
     * @param receiver Address to receive BERA after withdrawal is processed
     * @param shares Amount of iBERA to burn
     * @return nonce Withdrawal queue nonce for tracking
     * @return amount Amount of BERA to be received (after fees)
     */
    function unstakeBERA(address receiver, uint256 shares)
        external
        returns (uint256 nonce, uint256 amount)
    {
        // Preview the withdrawal
        (uint256 expectedBERA, uint256 fee) = ibera.previewBurn(shares);
        require(expectedBERA > 0, "Invalid burn amount");

        // Transfer iBERA from user to this contract
        IERC20(address(ibera)).transferFrom(msg.sender, address(this), shares);

        // Burn iBERA and queue withdrawal
        (nonce, amount) = ibera.burn(receiver, shares);

        emit WithdrawalQueued(receiver, nonce, amount);

        // Note: User must wait for withdrawal to be processed by keepers
        // Monitor ticket status using getWithdrawalStatus()
        // Claim using claimWithdrawal() when status is PROCESSED
    }

    /**
     * @notice Check the status of a withdrawal ticket
     * @param requestId The withdrawal ticket nonce/ID
     * @return state Current state (0=QUEUED, 1=PROCESSED, 2=CLAIMED)
     * @return timestamp When the withdrawal was queued
     * @return receiver Address that will receive the BERA
     * @return amount Amount of BERA to be claimed
     * @return isClaimable Whether the ticket can be claimed now
     */
    function getWithdrawalStatus(uint256 requestId)
        external
        view
        returns (
            IInfraredBERAWithdrawor.RequestState state,
            uint88 timestamp,
            address receiver,
            uint128 amount,
            bool isClaimable
        )
    {
        // Get withdrawal request details
        (state, timestamp, receiver, amount,) = withdrawor.requests(requestId);

        // A ticket is claimable if:
        // 1. It's in PROCESSED state (finalized but not yet claimed)
        // 2. The requestId has been processed (requestId <= requestsFinalisedUntil)
        isClaimable = (state == IInfraredBERAWithdrawor.RequestState.PROCESSED);
    }

    /**
     * @notice Claim BERA from a processed withdrawal ticket
     * @param requestId The withdrawal ticket nonce to claim
     * @dev Reverts if ticket is not in PROCESSED state
     */
    function claimWithdrawal(uint256 requestId) external {
        // Get ticket details to verify receiver
        (
            IInfraredBERAWithdrawor.RequestState state,
            ,
            address receiver,
            uint128 amount,
        ) = withdrawor.requests(requestId);

        require(
            state == IInfraredBERAWithdrawor.RequestState.PROCESSED,
            "Ticket not claimable yet"
        );

        // Claim the withdrawal
        // Note: withdrawor will verify msg.sender is receiver or keeper
        withdrawor.claim(requestId);

        emit WithdrawalClaimed(receiver, requestId, amount);

        // BERA is now transferred to the receiver address
    }

    /**
     * @notice Claim multiple withdrawal tickets in a single transaction
     * @param requestIds Array of withdrawal ticket nonces to claim
     * @param receiver Address that should receive all withdrawals
     * @dev All tickets must have the same receiver and be in PROCESSED state
     */
    function claimWithdrawalBatch(uint256[] calldata requestIds, address receiver)
        external
    {
        // Claim all tickets in one transaction
        withdrawor.claimBatch(requestIds, receiver);

        // Calculate total amount claimed (for event emission)
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < requestIds.length; i++) {
            (,,, uint128 amount,) = withdrawor.requests(requestIds[i]);
            totalAmount += amount;
            emit WithdrawalClaimed(receiver, requestIds[i], amount);
        }

        // Total BERA is now transferred to the receiver address
    }

    /**
     * @notice Check multiple withdrawal tickets and return which ones are claimable
     * @param requestIds Array of ticket IDs to check
     * @return claimable Array of booleans indicating which tickets are claimable
     */
    function getClaimableTickets(uint256[] calldata requestIds)
        external
        view
        returns (bool[] memory claimable)
    {
        claimable = new bool[](requestIds.length);

        for (uint256 i = 0; i < requestIds.length; i++) {
            (IInfraredBERAWithdrawor.RequestState state,,,,) =
                withdrawor.requests(requestIds[i]);

            claimable[i] =
                (state == IInfraredBERAWithdrawor.RequestState.PROCESSED);
        }
    }

    /**
     * @notice Get current iBERA/BERA exchange rate
     * @dev Rate increases over time as staking rewards accrue
     */
    function getExchangeRate() external view returns (uint256) {
        uint256 totalSupply = ibera.totalSupply();
        if (totalSupply == 0) return 1e18;

        uint256 totalAssets = ibera.deposits();
        return (totalAssets * 1e18) / totalSupply;
    }

    /**
     * @notice Check if withdrawals are currently enabled
     */
    function canWithdraw() external view returns (bool) {
        return ibera.withdrawalsEnabled();
    }
}
```

**Key Points:**
- iBERA is an ERC20 token representing staked BERA
- Exchange rate increases as validator rewards accrue
- Withdrawals are queue-based, not instant - follow the lifecycle: **QUEUED** → **PROCESSED** → **CLAIMED**
- `compound()` is called internally during mint/burn to ensure accurate accounting
- Monitor withdrawal status using `getWithdrawalStatus()` to know when to claim
- Use `claimWithdrawalBatch()` for gas-efficient claiming of multiple tickets
- Keepers process withdrawal tickets when sufficient reserves are available

**Withdrawal Flow Example:**

```solidity
// Step 1: User initiates withdrawal
uint256 iberaAmount = 100 ether;
(uint256 nonce, uint256 expectedBERA) = integration.unstakeBERA(userAddress, iberaAmount);
// Returns: nonce = 42, expectedBERA = 105 ether (assuming 5% accrued rewards)

// Step 2: Monitor withdrawal status (can be called by frontend/indexer)
(
    IInfraredBERAWithdrawor.RequestState state,
    uint88 timestamp,
    address receiver,
    uint128 amount,
    bool isClaimable
) = integration.getWithdrawalStatus(nonce);
// Initially: state = QUEUED (0), isClaimable = false

// Step 3: Wait for keeper to process the withdrawal queue
// Keepers call withdrawor.process() when enough BERA reserves are available
// This transitions tickets from QUEUED → PROCESSED

// Step 4: Check status again after processing
(state,,,, isClaimable) = integration.getWithdrawalStatus(nonce);
// After processing: state = PROCESSED (1), isClaimable = true

// Step 5: Claim the BERA
integration.claimWithdrawal(nonce);
// BERA is transferred to receiver address

// Optional: Claim multiple tickets at once
uint256[] memory nonces = new uint256[](3);
nonces[0] = 42;
nonces[1] = 43;
nonces[2] = 44;
integration.claimWithdrawalBatch(nonces, userAddress);
```

---

### 2. InfraredVault Integration

For advanced use cases requiring direct vault interaction and multi-reward token support.

```solidity
pragma solidity ^0.8.19;

import {IInfrared} from '@infrared/interfaces/IInfrared.sol';
import {IInfraredVault} from '@infrared/interfaces/IInfraredVault.sol';
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/**
 * @title Infrared Vault Integration Example
 * @notice Advanced integration with InfraredVault for multi-reward support
 */
contract InfraredVaultIntegration is Owned {
    IInfrared public immutable infrared;

    constructor(address _infrared, address _gov) Owned(_gov) {
        infrared = IInfrared(_infrared);
    }

    /**
     * @notice Stake assets into an InfraredVault
     * @param asset The staking token address (e.g., LP token)
     * @param amount Amount to stake
     */
    function stakeAssets(address asset, uint256 amount) external {
        IInfraredVault vault = infrared.vaultRegistry(asset);
        require(address(vault) != address(0), "Vault not registered");

        // Transfer from user and stake
        ERC20(asset).transferFrom(msg.sender, address(this), amount);
        ERC20(asset).approve(address(vault), amount);
        vault.stake(amount);

        // Contract now earns:
        // 1. iBGT (from BGT rewards)
        // 2. Additional incentive tokens (up to 10 per vault)
    }

    /**
     * @notice Harvest all rewards for a user
     * @return rewards Array of all rewards earned
     */
    function harvestAllRewards()
        external
        returns (IInfraredVault.UserReward[] memory rewards)
    {
        IInfraredVault vault = infrared.vaultRegistry(asset);

        // Claim all rewards - transfers tokens to msg.sender
        vault.getReward();

        // Retrieve all reward tokens
        address[] memory _tokens = iVault.getAllRewardTokens();
        uint256 len = _tokens.length;
        // Loop through reward tokens and transfer them to the reward distributor
        for (uint256 i; i < len; ++i) {
            ERC20 _token = ERC20(_tokens[i]);
            uint256 bal = _token.balanceOf(address(this));
            if (bal == 0) continue;
            (bool success, bytes memory data) = address(_token).call(
                abi.encodeWithSelector(
                    ERC20.transfer.selector, owner, bal
                )
            );
            if (success && (data.length == 0 || abi.decode(data, (bool)))) {
                emit RewardClaimed(address(_token), bal);
            } else {
                continue;
            }
        }
    }



    /**
     * @notice Withdraw staked assets
     * @param asset The staking token address
     * @param amount Amount to withdraw
     */
    function withdrawAssets(address asset, uint256 amount) external onlyOwner {
        IInfraredVault vault = infrared.vaultRegistry(asset);
        vault.withdraw(amount);

        // Transfer assets back to user
        ERC20(asset).transfer(msg.sender, amount);
    }

    /**
     * @notice Exit position completely (withdraw all + claim rewards)
     * @param asset The staking token address
     */
    function exitPosition(address asset) external onlyOwner {
        IInfraredVault vault = infrared.vaultRegistry(asset);

        uint256 stakedBalance = vault.balanceOf(address(this));

        // Exit withdraws all staked assets AND claims all rewards
        vault.exit();

        // Transfer assets back to user
        ERC20(asset).transfer(msg.sender, stakedBalance);
    }

    /**
     * @notice Get all reward tokens for a vault
     */
    function getVaultRewardTokens(address asset)
        external
        view
        returns (address[] memory)
    {
        IInfraredVault vault = infrared.vaultRegistry(asset);
        return vault.getAllRewardTokens();
    }
}
```

**Key Points:**
- InfraredVaults support up to 10 reward tokens simultaneously
- Rewards accumulate continuously based on staking duration
- `getReward()` claims all pending rewards at once
- `exit()` combines withdrawal + reward claiming in one transaction

---


### 3. DeFi Protocol Integration Examples

#### Using iBERA as Collateral

```solidity
/**
 * @notice Example: Accept iBERA as collateral in lending protocol
 */
contract LendingProtocol {
    IInfraredBERAV2 public ibera;

    function depositCollateral(uint256 iberaAmount) external {
        IERC20(address(ibera)).transferFrom(
            msg.sender,
            address(this),
            iberaAmount
        );

        // Calculate collateral value using exchange rate
        uint256 totalSupply = ibera.totalSupply();
        uint256 totalDeposits = ibera.deposits();
        uint256 beraValue = (iberaAmount * totalDeposits) / totalSupply;

        // Set user's collateral (worth more over time as rewards accrue)
        // Apply appropriate LTV ratio for risk management
    }
}
```

#### Creating iBERA/BERA Liquidity Pool

```solidity
/**
 * @notice Example: Create iBERA/BERA liquidity pool
 */
contract LiquidityPool {
    IInfraredBERAV2 public ibera;

    function addLiquidity(uint256 iberaAmount) external payable {
        // Transfer iBERA from user
        IERC20(address(ibera)).transferFrom(
            msg.sender,
            address(this),
            iberaAmount
        );

        // BERA received via msg.value
        // Create LP position with iBERA + BERA
        // Note: Exchange rate naturally appreciates over time
        //       Pool becomes imbalanced as iBERA value increases
    }
}
```

---

## Testing

### Run Tests

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run integration tests
make test-integration

# Run invariant tests
make test-invariant

# Run fork tests (requires RPC)
make test-fork NETWORK=mainnet

# Run with gas reporting
make test-gas

# Run specific test
make test-specific TEST=testFunctionName
```

**Advanced Forge Commands:**
```bash
# Run with increased verbosity
forge test -vvv

# Run specific test file
forge test --match-path tests/unit/core/Infrared/InfraredTest.t.sol

# Run fork tests with specific block
forge test --fork-url $RPC_URL --fork-block-number 12345678
```

### Test Coverage

```bash
# Generate coverage report (opens in browser)
make test-coverage

# Or manually:
forge coverage --report lcov --exclude-tests --no-match-coverage "(script)"
genhtml lcov.info --output-directory coverage
```

## Operations

The Makefile provides comprehensive commands for managing the protocol. All operations support the `NETWORK` parameter (local, devnet, testnet, mainnet).

### State Monitoring

```bash
# Complete protocol health check
make health-check NETWORK=mainnet

# View all state information
make check-all NETWORK=mainnet

# Check specific metrics
make check-deposits NETWORK=mainnet      # Total iBERA deposits
make check-exchange-rate NETWORK=mainnet # iBERA/BERA exchange rate
make check-bgt NETWORK=mainnet           # BGT balance
make util-get-total-assets NETWORK=mainnet # Total protocol assets
```

### Keeper Operations

**Prerequisites:** KEEPER_ROLE required

```bash
# Run all harvest operations
make keeper-harvest NETWORK=mainnet

# Individual harvest operations
make keeper-harvest-base NETWORK=mainnet     # Base rewards
make keeper-harvest-boost NETWORK=mainnet    # Boost rewards
make keeper-harvest-bribes NETWORK=mainnet   # Bribe rewards
make keeper-harvest-operator NETWORK=mainnet # Operator rewards

# Validator operations
make keeper-deposit-validator NETWORK=mainnet
make keeper-activate-commissions NETWORK=mainnet
make keeper-queue-boost PUBKEY=0x... AMOUNT=1000 NETWORK=mainnet
make keeper-activate-boost NETWORK=mainnet

# iBERA staking operations
make keeper-execute-depositor NETWORK=mainnet
make keeper-sweep-withdrawor NETWORK=mainnet
```

**See all keeper commands:** `make help | grep keeper`

### Governance Operations

**Prerequisites:** Executed through Safe multisig

```bash
# Validator management
make gov-add-validator PUBKEY=0x... OPERATOR=0x... NETWORK=mainnet
make gov-remove-validator PUBKEY=0x... NETWORK=mainnet
make gov-onboard-validator PUBKEY=0x... OPERATOR=0x...

# Token & vault management
make gov-whitelist-token TOKEN=0x... NETWORK=mainnet
make gov-add-reward STAKING_TOKEN=0x... REWARD_TOKEN=0x... DURATION=604800
make gov-migrate-vault VAULT=0x...

# Fee & parameter updates
make gov-update-fee FEE_TYPE=0 FEE=50000 NETWORK=mainnet
make gov-set-commission VALIDATOR=0x... COMMISSION=10000
make gov-claim-fees NETWORK=mainnet

# Access control
make gov-grant-keeper KEEPER=0x... NETWORK=mainnet
make gov-revoke-keeper KEEPER=0x... NETWORK=mainnet

# Emergency operations
make gov-pause-vault ASSET=0x... NETWORK=mainnet
make gov-unpause-vault ASSET=0x... NETWORK=mainnet
```

**See all governance commands:** `make help | grep gov`

### Utility Commands

```bash
# Display configuration
make config-show

# Validate contract addresses
make config-validate

# Show role information
make info-roles NETWORK=mainnet

# Show fee type enum values
make info-fee-types

# Show available networks
make info-networks
```

**Full Operations Guide:** See [OPERATIONS.md](OPERATIONS.md) for detailed procedures and best practices.

## Security

### Audits

All audit reports are available in the [audits directory](./audits/) and on our [documentation site](https://infrared.finance/docs/audits).


### Bug Bounty

We have an active bug bounty program. Please review our [security policy](./SECURITY.md) for details on:
- Scope and rewards
- Responsible disclosure process
- Out-of-scope vulnerabilities

### Security Contact

For security concerns, please email: security@infrared.finance

**DO NOT** open public issues for security vulnerabilities.

## Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details on:

- Code of Conduct
- Development process
- Pull request process
- Coding standards

### Quick Contribution Guide

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the Business Source License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ by the Infrared team**

[Website](https://infrared.finance) • [Documentation](https://docs.infrared.finance) • [Twitter](https://twitter.com/infrared_dao)

</div>
