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
- ✅ **Governance**: Vote-escrowed NFTs (veNFTs) for protocol governance
- ✅ **Bribes & Incentives**: Sophisticated reward distribution and bribe collection system

## Documentation

| Resource | Description |
|----------|-------------|
| [📚 Documentation](https://docs.infrared.finance) | Complete protocol documentation |
| [🏗️ Architecture](https://docs.infrared.finance/developers/architecture) | Technical architecture overview |
| [📍 Deployments](https://docs.infrared.finance/testnet/deployments) | Contract addresses by network |
| [🔍 Audits](https://docs.infrared.finance/developers/audits) | Security audit reports |
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

#### 🟣 Voting Contracts - veTokenomics & Governance
[Full documentation →](https://github.com/infrared-dao/infrared-contracts/blob/develop/src/voting/README.md)

The voting module implements a voting escrow (ve) system for allocating IBGT rewards and validator resources through community governance.

| Contract | Purpose | Key Features |
|----------|---------|--------------|
| **`VotingEscrow.sol`** | veNFT token locking | • Issues veNFTs for locked tokens<br>• Voting power based on lock duration<br>• Power decay over time mechanism |
| **`Voter.sol`** | Allocation voting system | • Manages cutting board distribution votes<br>• Whitelisted token bribe system<br>• Epoch-based voting windows<br>• Weight tallying and updates |
| **`VelodromeTimeLibrary`** | Time management | • Weekly epoch calculations<br>• Voting window enforcement<br>• Synchronized voting cycles |

**Key Concepts**:
- **Voting Power**: Proportional to tokens locked and duration (with decay)
- **Cutting Board**: Validator resource allocation across vaults
- **Bribes**: Whitelisted tokens used to incentivize specific votes
- **Epochs**: Weekly voting periods with defined windows

**Key Flows**: Lock tokens → Receive veNFT → Vote on allocations → Influence rewards → Claim bribes

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) toolkit
- Git
- Make (optional, for using Makefile commands)

### Installation

```bash
# Clone the repository
git clone https://github.com/infrared-dao/infrared-contracts.git
cd infrared-contracts

# Install dependencies
forge install

# Setup environment variables
cp .env.example .env
# Edit .env with your configuration

# Build contracts
forge build
```

## Development

### Build & Compile

```bash
# Build contracts
forge build

# Build with optimization
forge build --optimize --optimizer-runs 200

# Clean build artifacts
forge clean
```

### Code Quality

```bash
# Format code
forge fmt

# Check formatting
forge fmt --check

# Run static analysis
slither .
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
"@infrared/=lib/infrared-contracts/contracts/"
```

### Basic Integration Example

```solidity
pragma solidity ^0.8.19;

import {IInfrared} from '@infrared/interfaces/IInfrared.sol';
import {IInfraredVault} from '@infrared/interfaces/IInfraredVault.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyIntegration {
    IInfrared public immutable infrared;
    
    constructor(address _infrared) {
        infrared = IInfrared(_infrared);
    }
    
    function stakeAssets(address asset, uint256 amount) external {
        // Get the vault for this asset
        IInfraredVault vault = IInfrared(infrared).vaultRegistry(asset);
        require(address(vault) != address(0), "Vault not found");
        
        // Approve and stake
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(vault), amount);
        vault.stake(amount);
    }
    
    function checkRewards(address user, address asset) external view 
        returns (IInfraredVault.RewardData[] memory) {
        IInfraredVault vault = IInfrared(infrared).vaultRegistry(asset);
        return vault.getUserRewardsEarned(user);
    }
    
    function harvestRewards(address asset) external {
        IInfraredVault vault = IInfrared(infrared).vaultRegistry(asset);
        vault.getReward();
    }
    
    function exitPosition(address asset) external {
        IInfraredVault vault = IInfrared(infrared).vaultRegistry(asset);
        vault.exit(); // Withdraws all + harvests rewards
    }
}
```

## Testing

### Run Tests

```bash
# Run all tests
forge test

# Run with gas reporting
forge test --gas-report

# Run specific test file
forge test --match-path test/InfraredVault.t.sol

# Run specific test function
forge test --match-test testStakeFunction

# Run with verbosity (1-5)
forge test -vvv

# Run fork tests
forge test --fork-url $RPC_URL --fork-block-number 12345678
```

### Test Coverage

```bash
# Generate coverage report
forge coverage

# Generate detailed coverage report
forge coverage --report lcov

# Generate HTML coverage report
forge coverage --report lcov && genhtml lcov.info -o coverage
```

## Security

### Audits

All audit reports are available in the [audits directory](./audits/) and on our [documentation site](https://docs.infrared.finance/developers/audits).


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

## Community & Support

- 📱 [Twitter](https://twitter.com/infrared_dao)
- 💬 [Discord](https://discord.gg/infrared)
- 📰 [Blog](https://blog.infrared.finance)
- 📧 [Email](mailto:support@infrared.finance)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ by the Infrared team**

[Website](https://infrared.finance) • [Documentation](https://docs.infrared.finance) • [Twitter](https://twitter.com/infrared_dao)

</div>
