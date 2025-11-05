# Makefile Quick Reference

**Quick access guide to the most commonly used Makefile commands**

---

## 📋 Most Common Commands

### Daily Keeper Operations
```bash
# Run all harvests (daily)
make keeper-harvest NETWORK=mainnet

# Deposit to validators (hourly check)
make keeper-deposit-validator NETWORK=mainnet

# Activate validator commissions (as needed)
make keeper-activate-commissions NETWORK=mainnet
```

### State Monitoring
```bash
# Complete health check
make health-check NETWORK=mainnet

# Check all state
make check-all NETWORK=mainnet

# Check exchange rate
make check-exchange-rate NETWORK=mainnet
```

### Development
```bash
# Build and test
make dev-test

# Run all checks
make dev-check

# Format code
make format
```

---

## 🔍 State Checks

| Command | Description |
|---------|-------------|
| `make check-all` | Display all protocol state |
| `make check-deposits` | Total iBERA deposits |
| `make check-pending` | Pending validator stakes |
| `make check-confirmed` | Confirmed validator stakes |
| `make check-bgt` | BGT balance |
| `make check-exchange-rate` | iBERA/BERA exchange rate |
| `make health-check` | Run full health check |

**Add parameters:**
```bash
make check-validator PUBKEY=0x...
make check-vault ASSET=0x...
make check-rewards USER=0x...
```

---

## 🤖 Keeper Operations

### Required Role: KEEPER_ROLE

| Command | Frequency | Description |
|---------|-----------|-------------|
| `make keeper-harvest` | Daily | Run all harvest operations |
| `make keeper-harvest-base` | Daily | Harvest base rewards |
| `make keeper-harvest-vault` | Daily | Harvest vault rewards |
| `make keeper-harvest-bribes` | Daily | Harvest bribe rewards |
| `make keeper-harvest-boost` | Daily | Harvest boost rewards |
| `make keeper-harvest-operator` | Daily | Harvest operator rewards |
| `make keeper-deposit-validator` | Hourly | Process validator deposits |
| `make keeper-activate-commissions` | As needed | Activate queued commissions |

**Parameters:**
```bash
make keeper-harvest-vault ASSET=0x... NETWORK=mainnet
make keeper-queue-boost PUBKEY=0x... AMOUNT=1000000000000000000 NETWORK=mainnet
```

---

## 🏛️ Governance Operations

### Required Role: DEFAULT_ADMIN_ROLE (Multisig)

### Validator Management
```bash
# Add validator
make gov-add-validator PUBKEY=0x... OPERATOR=0x... NETWORK=mainnet

# Remove validator
make gov-remove-validator PUBKEY=0x... NETWORK=mainnet

# Queue commissions (100% to validator)
make gov-queue-commissions PUBKEY=0x... NETWORK=mainnet
```

### Vault & Rewards
```bash
# Whitelist reward token
make gov-whitelist-token TOKEN=0x... NETWORK=mainnet

# Add reward to vault
make gov-add-reward \
  STAKING_TOKEN=0x... \
  REWARD_TOKEN=0x... \
  DURATION=604800 \
  NETWORK=mainnet

# Pause/unpause vault
make gov-pause-vault ASSET=0x... NETWORK=mainnet
make gov-unpause-vault ASSET=0x... NETWORK=mainnet
```

### Fee Management
```bash
# Update fee
make gov-update-fee FEE_TYPE=0 FEE=50000 NETWORK=mainnet

# Show fee types
make info-fee-types
```

**Fee Types:**
- 0: HarvestVaultFeeRate
- 1: HarvestBribesFeeRate
- 2: HarvestOperatorFeeRate
- 3: HarvestBoostFeeRate
- 4-7: Protocol rates

**Fee Format:** Basis points (1e6 = 100%)
- 5% = 50000
- 10% = 100000
- 0.5% = 5000

### Access Control
```bash
# Grant keeper role
make gov-grant-keeper KEEPER=0x... NETWORK=mainnet

# Revoke keeper role
make gov-revoke-keeper KEEPER=0x... NETWORK=mainnet
```

### Emergency
```bash
# Pause all vaults (requires confirmation)
make emergency-pause-all NETWORK=mainnet

# Recover ERC20 tokens
make gov-recover-erc20 \
  TOKEN=0x... \
  RECIPIENT=0x... \
  AMOUNT=1000000000000000000 \
  NETWORK=mainnet
```

---

## 🧪 Testing

| Command | Description |
|---------|-------------|
| `make test` | Run all tests |
| `make test-unit` | Unit tests only |
| `make test-integration` | Integration tests |
| `make test-invariant` | Invariant tests |
| `make test-fork` | Fork tests |
| `make test-coverage` | Generate coverage report |
| `make test-gas` | Gas reporting |
| `make test-specific TEST=testName` | Run specific test |

---

## 🔨 Build & Deploy

| Command | Description |
|---------|-------------|
| `make build` | Build contracts |
| `make build-production` | Build with production settings |
| `make clean` | Clean artifacts |
| `make format` | Format Solidity files |
| `make format-check` | Check formatting |
| `make lint` | Run Slither |

---

## 📊 Information

| Command | Description |
|---------|-------------|
| `make help` | Show all commands |
| `make config-show` | Show configuration |
| `make config-validate` | Validate addresses |
| `make info-fee-types` | Show fee enum values |
| `make info-roles` | Show role hashes |
| `make info-networks` | Show available networks |

---

## 🌐 Networks

Set with `NETWORK=<name>`:

- **local** - Local development node
- **devnet** - Berachain devnet
- **testnet** - Berachain testnet
- **mainnet** - Berachain mainnet

**Example:**
```bash
make check-all NETWORK=mainnet
```

---

## ⚙️ Configuration

### Environment Variables

Create `.env` file:
```bash
PRIVATE_KEY=0x...
BERASCAN_API_KEY=...
```

### Contract Addresses

Set in `Makefile` or export:
```bash
export INFRARED_PROXY=0x2114079132C56827237f581eF1a0625680d29576
export IBERA_PROXY=0x...
export IBGT_PROXY=0x...
export BRIBE_COLLECTOR=0x...
export SAFE_ADDRESS=0x...
```

Or pass directly:
```bash
make check-deposits \
  IBERA_PROXY=0x... \
  NETWORK=mainnet
```

---

## 🚀 Quick Start Workflows

### Setup New Environment
```bash
make dev-setup
# Edit .env with your config
make config-validate
```

### Daily Keeper Routine
```bash
# 1. Health check
make health-check NETWORK=mainnet

# 2. Run harvests
make keeper-harvest NETWORK=mainnet

# 3. Process deposits (if > 32 BERA queued)
make keeper-deposit-validator NETWORK=mainnet

# 4. Monitor queue
make monitor-queue NETWORK=mainnet
```

### Development Workflow
```bash
# 1. Make changes to contracts
# 2. Format and check
make format
make dev-check

# 3. Run tests
make test-unit
make test-integration

# 4. Check coverage
make test-coverage

# 5. Build production
make build-production
```

### Governance Workflow
```bash
# 1. Validate configuration
make config-show

# 2. Create Safe transaction (example: whitelist token)
make gov-whitelist-token TOKEN=0x... NETWORK=mainnet

# 3. Review in Safe UI
# 4. Collect signatures
# 5. Execute transaction
```

---

## 📈 Monitoring Best Practices

### Set up cron jobs:

```bash
# Daily health check (8 AM)
0 8 * * * cd /path/to/repo && make health-check NETWORK=mainnet

# Exchange rate monitoring (every 6 hours)
0 */6 * * * cd /path/to/repo && make check-exchange-rate NETWORK=mainnet

# Daily harvest (midnight)
0 0 * * * cd /path/to/repo && make keeper-harvest NETWORK=mainnet

# Hourly deposit processing
0 * * * * cd /path/to/repo && make keeper-deposit-validator NETWORK=mainnet
```

### Alert Thresholds

**Critical (immediate action):**
- Exchange rate deviation > 10%
- Withdrawal queue > 75% deposits
- Failed harvest > 36 hours

**Warning (review within 1 hour):**
- Exchange rate deviation > 5%
- Withdrawal queue > 50% deposits
- Harvest missed > 26 hours
- Pending deposits > 100 BERA

---

## 🔗 Related Documentation

- **Full Operations Guide:** `OPERATIONS.md`
- **Architecture:** `CLAUDE.md`
- **Contract Versions:** `CONTRACT_VERSIONS.md`
- **Cleanup Plan:** `REPO_CLEANUP_PLAN.md`
- **Security Analysis:** `SECURITY_ANALYSIS.md`

---

## ⚡ Common Issues

### "RPC URL not found"
```bash
# Check network in foundry.toml
grep "mainnet" foundry.toml

# Or specify RPC directly
RPC_URL=https://... make check-all
```

### "Insufficient permissions"
```bash
# Check if address has KEEPER_ROLE
make info-roles NETWORK=mainnet
cast call <INFRARED> "hasRole(bytes32,address)(bool)" <ROLE> <ADDRESS> --rpc-url <RPC>
```

### "Transaction reverted"
```bash
# Check gas price
# Check nonce
# Verify contract address
make config-validate
```

---

**For detailed information, see:** `OPERATIONS.md`

**Last Updated:** October 14, 2025
