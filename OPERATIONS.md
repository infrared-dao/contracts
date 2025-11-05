# Infrared Protocol - Operations Guide

**Last Updated:** October 14, 2025
**Deployed Contract:** `0x2114079132C56827237f581eF1a0625680d29576`

---

## Overview

This guide documents operational procedures for the Infrared Protocol, including:
- Keeper bot operations (automated maintenance)
- Governance operations (multisig-controlled)
- State monitoring and health checks
- Emergency procedures

All operations are streamlined through the `Makefile` for consistent execution.

---

## Quick Start

### 1. Setup Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
# Required variables:
# - PRIVATE_KEY (for keeper operations)
# - BERASCAN_API_KEY (for verification)
```

### 2. Configure Contract Addresses

Edit the `Makefile` or export environment variables:

```bash
export INFRARED_PROXY=0x2114079132C56827237f581eF1a0625680d29576
export IBERA_PROXY=<your-ibera-address>
export IBGT_PROXY=<your-ibgt-address>
export BRIBE_COLLECTOR=<your-bribe-collector-address>
export SAFE_ADDRESS=<your-safe-multisig-address>
```

### 3. Verify Setup

```bash
# Show current configuration
make config-show

# Validate contract addresses
make config-validate

# Run health check
make health-check NETWORK=mainnet
```

---

## Keeper Operations

**Role:** KEEPER_ROLE
**Frequency:** Automated via cron or monitoring service
**Security:** Requires KEEPER_ROLE grant from governance

### Daily Operations

#### 1. Harvest All Rewards (Every 24 hours)

```bash
# Run complete harvest cycle
make keeper-harvest NETWORK=mainnet

# Or run individually:
make keeper-harvest-base NETWORK=mainnet
make keeper-harvest-vault ASSET=0x... NETWORK=mainnet
make keeper-harvest-boost NETWORK=mainnet
make keeper-harvest-operator NETWORK=mainnet
```

**Gas Estimates:**
- `harvestBase()`: ~300k gas
- `harvestVault()`: ~250k gas per vault
- `harvestBoostRewards()`: ~200k gas
- `harvestOperatorRewards()`: ~200k gas

**Monitoring:**
- Track last harvest timestamp per vault
- Alert if not harvested within 26-28 hours
- Monitor gas prices to optimize timing

#### 2. Harvest Bribes (Every 24 hours)

```bash
make keeper-harvest-bribes NETWORK=mainnet
```

**Purpose:** Collects bribe rewards from voting positions

**Gas Estimate:** ~150k-300k gas (varies by number of tokens)

### Hourly Operations

#### 3. Process Validator Deposits (Every hour)

```bash
make keeper-deposit-validator NETWORK=mainnet
```

**Triggers when:**
- Pending deposit queue > 32 BERA (minimum validator deposit)
- Available validator has deposit signature set

**Monitoring:**
- Alert if queue > 100 BERA for > 2 hours
- Track validator activation success rate

#### 4. Activate Validator Commissions (As needed)

```bash
make keeper-activate-commissions NETWORK=mainnet
```

**Purpose:** Activates queued validator commission changes

**Frequency:** Check every 12 hours, execute when block height reached

### Boost Management (As needed)

```bash
# Queue boost for validator
make keeper-queue-boost PUBKEY=0x... AMOUNT=1000000000000000000 NETWORK=mainnet

# Activate queued boosts
make keeper-activate-boost NETWORK=mainnet

# Drop boost from validator
make keeper-drop-boost PUBKEY=0x... AMOUNT=1000000000000000000 NETWORK=mainnet
```

**Note:** Boosts are measured in wei (1e18 = 1 BGT)

---

## State Monitoring

### Comprehensive Health Check

```bash
make health-check NETWORK=mainnet
```

**Output includes:**
- Total deposits (iBERA)
- Pending stakes (awaiting validator activation)
- Confirmed stakes (active validators)
- BGT balance
- Exchange rate (deposits / totalSupply)

### Individual State Checks

```bash
# Check total iBERA deposits
make check-deposits NETWORK=mainnet

# Check pending validator stakes
make check-pending NETWORK=mainnet

# Check confirmed validator stakes
make check-confirmed NETWORK=mainnet

# Check BGT balance
make check-bgt NETWORK=mainnet

# Check iBGT total supply
make check-ibgt-supply NETWORK=mainnet

# Check specific validator stake
make check-validator PUBKEY=0x... NETWORK=mainnet

# Check vault registry
make check-vault ASSET=0x... NETWORK=mainnet

# Check user rewards
make check-rewards USER=0x... NETWORK=mainnet

# Check exchange rate
make check-exchange-rate NETWORK=mainnet
```

### Continuous Monitoring

```bash
# Monitor withdrawal queue (runs continuously)
make monitor-queue NETWORK=mainnet
```

**Alert Thresholds:**
- Pending withdrawals > 50% of deposits: WARNING
- Pending withdrawals > 75% of deposits: CRITICAL
- Queue time > 30 hours: WARNING
- Queue time > 36 hours: CRITICAL

---

## Governance Operations

**Role:** DEFAULT_ADMIN_ROLE (Multisig Safe)
**Security:** Requires threshold signatures from Safe multisig
**Process:** All governance operations create Safe transactions for approval

### Validator Management

#### Add Validator

```bash
make gov-add-validator \
  PUBKEY=0x... \
  OPERATOR=0x... \
  NETWORK=mainnet
```

**Pre-requisites:**
- Validator public key (48 bytes, BLS12-381)
- Operator address (receives commissions)
- Safe multisig approval

**Post-deployment:**
1. Set deposit signature: `make gov-set-deposit-sig PUBKEY=0x... SIGNATURE=0x...`
2. Queue commission (optional): `make gov-queue-commissions PUBKEY=0x...`
3. Monitor for first 32 BERA deposit

#### Remove Validator

```bash
make gov-remove-validator \
  PUBKEY=0x... \
  NETWORK=mainnet
```

**⚠️ WARNING:** This will:
1. Harvest all pending rewards
2. Remove validator from active set
3. Initiate withdrawal process (EIP-7002)

**Expected Duration:** 27 hours for full withdrawal

### Vault & Reward Management

#### Whitelist Reward Token

```bash
make gov-whitelist-token \
  TOKEN=0x... \
  NETWORK=mainnet
```

**Automatic Checks (in script):**
- ✅ ERC20 compliance (totalSupply, balanceOf, allowance)
- ✅ Proxy detection (EIP-1967)
- ✅ Not already whitelisted

**Manual Review Required:**
- Token contract verified on Berascan
- No fee-on-transfer mechanism
- No rebasing mechanism
- Trusted token issuer
- Liquidity depth acceptable

#### Add Reward to Vault

```bash
make gov-add-reward \
  STAKING_TOKEN=0x... \
  REWARD_TOKEN=0x... \
  DURATION=604800 \
  NETWORK=mainnet
```

**Duration Examples:**
- 1 week: 604800 seconds
- 1 day: 86400 seconds
- 2 weeks: 1209600 seconds

**Post-deployment:**
- Verify reward token whitelisted
- Confirm reward duration set correctly
- Test with small incentive amount

#### Update Fee

```bash
make gov-update-fee \
  FEE_TYPE=0 \
  FEE=50000 \
  NETWORK=mainnet
```

**Fee Types (see `make info-fee-types`):**
```
0: HarvestVaultFeeRate       (keeper fee for vault harvests)
1: HarvestBribesFeeRate      (keeper fee for bribe harvests)
2: HarvestOperatorFeeRate    (keeper fee for operator harvests)
3: HarvestBoostFeeRate       (keeper fee for boost harvests)
4: HarvestVaultProtocolRate  (protocol fee for vault harvests)
5: HarvestBribesProtocolRate (protocol fee for bribe harvests)
6: HarvestOperatorProtocolRate (protocol fee for operator harvests)
7: HarvestBoostProtocolRate  (protocol fee for boost harvests)
```

**Fee Format:** Basis points (1e6 = 100%)
- 5%: 50000
- 10%: 100000
- 0.5%: 5000

**⚠️ Safety Check:** Should add max fee validation (10% cap) in next upgrade

### Emergency Operations

#### Pause Vault Staking

```bash
make gov-pause-vault \
  ASSET=0x... \
  NETWORK=mainnet
```

**Effect:**
- Disables new deposits to vault
- Withdrawals still enabled
- Existing stakes unaffected

**When to use:**
- Vault contract vulnerability discovered
- Asset contract compromised
- Abnormal vault behavior

#### Unpause Vault Staking

```bash
make gov-unpause-vault \
  ASSET=0x... \
  NETWORK=mainnet
```

**Pre-requisites:**
- Issue resolved and verified
- Team consensus on safety
- Monitoring in place

#### Emergency Pause All Vaults

```bash
make emergency-pause-all NETWORK=mainnet
```

**⚠️ CRITICAL:** This pauses ALL vaults

**When to use:**
- Protocol-wide vulnerability
- Core contract exploit
- Under active attack

**Requires:** Interactive confirmation

### Access Control

#### Grant Keeper Role

```bash
make gov-grant-keeper \
  KEEPER=0x... \
  NETWORK=mainnet
```

**Grants KEEPER_ROLE on:**
- Infrared contract
- InfraredBERA contract

**Before granting:**
- Verify keeper address correct
- Review keeper bot security
- Test on testnet first

#### Revoke Keeper Role

```bash
make gov-revoke-keeper \
  KEEPER=0x... \
  NETWORK=mainnet
```

**When to use:**
- Keeper bot compromised
- Rotating keeper addresses
- Deprecating old keeper

### Asset Recovery

#### Recover ERC20 from Protocol

```bash
make gov-recover-erc20 \
  TOKEN=0x... \
  RECIPIENT=0x... \
  AMOUNT=1000000000000000000 \
  NETWORK=mainnet
```

**Use cases:**
- Accidentally sent tokens
- Deprecated reward tokens
- Protocol fee collection

**⚠️ WARNING:** Cannot recover:
- Staking tokens (would break accounting)
- Active reward tokens

### Bribe Collector Management

#### Set Payout Token

```bash
make gov-set-bribe-payout \
  TOKEN=0x... \
  NETWORK=mainnet
```

**Current:** iBGT (per V1.8 upgrade)

**Before changing:**
- Ensure token whitelisted
- Verify sufficient liquidity
- Test conversion paths

#### Queue Validator Commissions

```bash
make gov-queue-commissions \
  PUBKEY=0x... \
  NETWORK=mainnet
```

**Purpose:** Queue 100% commission rate for validator

**Activation:** Requires keeper to call `activateValCommissions()` after block height

---

## Expected Timelines

### Deposits
- **User submits:** Instant (receives iBERA shares)
- **Queue wait:** Up to 1 hour (depends on keeper frequency)
- **Validator activation:** Up to 27 hours (depends on Beacon chain)
- **First rewards:** Next epoch after activation

### Withdrawals
- **User submits:** Instant (burns iBERA shares)
- **Queue wait:** Exactly 27 hours (target)
- **Withdrawal available:** After EIP-7002 processing
- **Claim:** User calls `claim()` on withdrawor

### Harvests
- **Frequency:** Every 24 hours (keeper bot)
- **Distribution:** Immediate after harvest
- **User claims:** Any time after distribution

---

## Monitoring & Alerts

### Critical Alerts

**Immediate Response Required:**
1. Exchange rate deviation > 10%
2. Withdrawal queue > 75% of deposits
3. Validator slashing detected
4. Abnormal BGT balance drop
5. Failed harvest > 36 hours

### Warning Alerts

**Review Within 1 Hour:**
1. Exchange rate deviation > 5%
2. Withdrawal queue > 50% of deposits
3. Harvest missed (> 26 hours)
4. Keeper bot offline > 2 hours
5. Pending deposits > 100 BERA

### Monitoring Commands

```bash
# Continuous queue monitoring
make monitor-queue NETWORK=mainnet

# Daily health check (add to cron)
0 8 * * * cd /path/to/repo && make health-check NETWORK=mainnet

# Exchange rate monitoring (every 6 hours)
0 */6 * * * cd /path/to/repo && make state-exchange-rate NETWORK=mainnet
```

---

## Development Workflow

### Setup Development Environment

```bash
make dev-setup
```

**Creates:**
- `.env` from template
- Installs dependencies via Forge

### Development Test Cycle

```bash
# Quick test cycle
make dev-test

# Comprehensive checks
make dev-check
```

### Run Specific Tests

```bash
# All tests
make test

# Unit tests only
make test-unit

# Integration tests
make test-integration

# Invariant tests
make test-invariant

# Fork tests (requires RPC)
make test-fork NETWORK=mainnet

# Specific test function
make test-specific TEST=testMintBurn

# Gas reporting
make test-gas

# Coverage report
make test-coverage
```

---

## Build & Deploy

### Build Contracts

```bash
# Development build
make build

# Production build (optimizer runs: 50)
make build-production

# Clean artifacts
make clean
```

### Deploy Contracts

**⚠️ MAINNET DEPLOYMENT:** Only via governance multisig

```bash
# Deploy Infrared (use with extreme caution)
make deploy-infrared NETWORK=mainnet

# Deploy InfraredBERA (use with extreme caution)
make deploy-ibera NETWORK=mainnet
```

**Pre-deployment Checklist:**
- [ ] Contracts audited
- [ ] Tests passing (100% coverage)
- [ ] Governance approval obtained
- [ ] Deployment plan reviewed
- [ ] Rollback plan documented
- [ ] Testnet deployment successful
- [ ] Safe multisig ready

---

## Utility Commands

### Code Quality

```bash
# Format Solidity files
make format

# Check formatting
make format-check

# Run Slither static analysis
make lint

# Create gas snapshot
make snapshot
```

### Documentation

```bash
# Generate documentation
make docs

# Serve docs locally
make docs-serve
```

### Dependencies

```bash
# Install dependencies
make install

# Update dependencies
make update
```

---

## Information Commands

### Show Fee Types

```bash
make info-fee-types
```

### Show Role Hashes

```bash
make info-roles NETWORK=mainnet
```

### Show Available Networks

```bash
make info-networks
```

### Show Current Configuration

```bash
make config-show
```

---

## Troubleshooting

### Issue: Harvest Fails with "Too Early"

**Cause:** Trying to harvest before 24-hour window

**Solution:** Wait until `block.timestamp >= periodFinish`

```bash
# Check period finish for vault
cast call <VAULT_ADDRESS> "rewardData(address)(uint256,uint256,uint256,uint256,uint256,uint256,uint256)" <REWARD_TOKEN> --rpc-url <RPC_URL>
```

### Issue: Keeper Transaction Reverts

**Common causes:**
1. Insufficient KEEPER_ROLE
2. Gas price too low
3. Nonce mismatch

**Check role:**
```bash
cast call $(INFRARED_PROXY) "hasRole(bytes32,address)(bool)" <KEEPER_ROLE_HASH> <KEEPER_ADDRESS> --rpc-url <RPC_URL>
```

### Issue: Governance Transaction Won't Execute

**Common causes:**
1. Insufficient Safe signatures
2. Transaction expired
3. Nonce incorrect

**Verify Safe threshold:**
- Check Safe UI for pending transactions
- Ensure threshold signatures collected
- Verify transaction nonce matches

### Issue: State Check Returns Zero

**Possible causes:**
1. Wrong contract address
2. Wrong network
3. Contract not initialized

**Verify:**
```bash
make config-validate
make config-show
```

---

## Security Considerations

### Private Key Management

**NEVER commit private keys to repository**

```bash
# Use environment variables
export PRIVATE_KEY=0x...

# Or use hardware wallet (Ledger/Trezor)
# See Foundry docs: https://book.getfoundry.sh/reference/cast/cast-send
```

### Safe Multisig Best Practices

1. **Simulate Before Signing**
   - Use Safe Transaction Builder
   - Verify all parameters
   - Check gas limits

2. **Verify Contract Addresses**
   - Double-check target contract
   - Confirm function signature
   - Validate all parameters

3. **Review Batch Transactions**
   - Understand each operation
   - Verify order of operations
   - Check for dependencies

4. **Emergency Procedures**
   - Keep quorum available 24/7
   - Document emergency contacts
   - Test emergency pause process

### Keeper Bot Security

1. **Access Control**
   - Use dedicated wallet for keeper
   - Limit wallet balance (only gas funds)
   - Monitor for unauthorized access

2. **Operational Security**
   - Run keeper bot in secure environment
   - Monitor logs for anomalies
   - Alert on failed transactions

3. **Rate Limiting**
   - Prevent DOS from excessive calls
   - Implement exponential backoff
   - Cap gas prices

---

## Reference: Fee Calculations

### Harvest Fees

```
Total Reward = R
Keeper Fee = R * HarvestVaultFeeRate / 1e6
Protocol Fee = R * HarvestVaultProtocolRate / 1e6
User Reward = R - Keeper Fee - Protocol Fee
```

**Example:** 1000 BGT harvested, 5% keeper fee, 5% protocol fee
```
Keeper Fee = 1000 * 50000 / 1000000 = 50 BGT
Protocol Fee = 1000 * 50000 / 1000000 = 50 BGT
User Reward = 1000 - 50 - 50 = 900 BGT
```

### iBERA Exchange Rate

```
Exchange Rate = deposits / totalSupply

Mint:  shares = (totalSupply * amount) / deposits
Burn:  amount = (deposits * shares) / totalSupply
```

**Example:** 10000 deposits, 9000 totalSupply
```
Exchange Rate = 10000 / 9000 = 1.111 BERA per iBERA

User deposits 100 BERA:
shares = (9000 * 100) / 10000 = 90 iBERA

User burns 90 iBERA:
amount = (10000 * 90) / 9000 = 100 BERA
```

---

## Support & Escalation

### Documentation

- **Architecture:** See `CLAUDE.md`
- **Contract Versions:** See `CONTRACT_VERSIONS.md`
- **Cleanup Plan:** See `REPO_CLEANUP_PLAN.md`
- **Security Analysis:** See `SECURITY_ANALYSIS.md`

### Emergency Contacts

1. **Protocol Emergency:** Contact governance multisig signers
2. **Keeper Issues:** Contact DevOps team
3. **Security Incident:** Follow incident response plan
4. **Contract Bugs:** Pause affected contracts, notify auditors

### Reporting Issues

```bash
# Create issue with details:
# - Network (mainnet/testnet)
# - Transaction hash (if applicable)
# - Expected vs actual behavior
# - Steps to reproduce
```

---

**Last Updated:** October 14, 2025
**Maintained By:** Infrared Protocol Team
**Review Schedule:** Monthly or after major upgrades
