# Infrared Protocol Operations Guide

## Table of Contents

1. [Production Services Architecture](#1-production-services-architecture)
2. [Automated Operations](#2-automated-operations)
3. [Governance Operations](#3-governance-operations)
4. [State Monitoring](#4-state-monitoring)
5. [Emergency Procedures](#5-emergency-procedures)
6. [Manual Makefile Operations](#6-manual-makefile-operations)
   - [6.1 Manual Harvest](#manual-harvest-emergency-only)
   - [6.2 Manual Boost Management](#manual-boost-management-emergency-only)
   - [6.3 Manual Cutting Board Management](#manual-cutting-board-management)
   - [6.4 Manual Bribe & Auction Claiming](#manual-bribe--auction-claiming)
   - [6.5 Manual iBERA Keeper Operations](#manual-ibera-keeper-operations)
7. [Reference](#7-reference)

---

## 1. Production Services Architecture

In production, most protocol operations are handled by dedicated off-chain services. The Makefile commands in this repo are for development, debugging, and emergency manual intervention.

### Core Operation Services

| Service | Repository | Responsibility |
|---------|-----------|---------------|
| **backend** | [infrared-dao/backend](https://github.com/infrared-dao/backend) | Go service handling reward harvesting for all vaults |
| **ibera-keeper** | [infrared-dao/ibera-keeper](https://github.com/infrared-dao/ibera-keeper) | iBERA CL deposit queue processing and withdrawal orchestration |
| **infrared-strategy** | [infrared-dao/infrared-strategy](https://github.com/infrared-dao/infrared-strategy) | Validator cutting board management and BGT boost optimization |
| **auction-bot** | [infrared-dao/auction-bot](https://github.com/infrared-dao/auction-bot) | Automated bribe collection and auction lifecycle management |

### Supporting Services

| Service | Repository | Responsibility |
|---------|-----------|---------------|
| **bera-proofs** | [infrared-dao/bera-proofs](https://github.com/infrared-dao/bera-proofs) | Berachain consensus layer proof generation |
| **uniswap-optimizer** | [infrared-dao/uniswap-optimizer](https://github.com/infrared-dao/uniswap-optimizer) | IR/iBGT market liquidity optimization |
| **merkle-claims** | [infrared-dao/merkle-claims](https://github.com/infrared-dao/merkle-claims) | IR token airdrop merkle proof generation and claim processing |

### Service Interaction Diagram

```
                    ┌───────────────────────────────┐
                    │      infrared-strategy        │
                    │  • Cutting board updates      │
                    │  • BGT boost queue/activate   │
                    └──────────────┬────────────────┘
                                   │ KEEPER_ROLE
                    ┌──────────────▼────────────────┐
                    │         Infrared.sol          │
                    │    (Core Protocol Contract)   │
                    └──┬───────────────────┬────────┘
                       │                   │
          ┌────────────▼────┐     ┌────────▼──────────────┐
          │    backend      │     │      auction-bot      │
          │  • harvestBase  │     │  • claimFees()        │
          │  • harvestVault │     │  • Auction lifecycle  │
          │  • harvestBoost │     └───────────────────────┘
          │  • harvestBribes│
          └─────────────────┘
                    ┌───────────────────────────────┐
                    │        ibera-keeper           │
                    │  • processDeposits()          │
                    │  • queueWithdrawals()         │
                    │  • Beacon chain proofs        │
                    └──────────────┬────────────────┘
                                   │
                    ┌──────────────▼────────────────┐
                    │       InfraredBERA.sol        │
                    │    (iBERA Liquid Staking)     │
                    └───────────────────────────────┘
```

---

## 2. Automated Operations

These operations are handled by backend services. See each service's repository for deployment and configuration instructions.

### 2.1 Reward Harvesting — `backend`

**Service:** [infrared-dao/backend](https://github.com/infrared-dao/backend)

The backend Go service runs the full harvest cycle for all registered InfraredVaults. It calls the harvest functions on Infrared.sol with `KEEPER_ROLE`.

**Harvest functions called:**
- `harvestBase()` — BGT from BerachainRewardsVault, converts to iBGT and distributes
- `harvestVault(asset)` — Per-vault reward harvesting
- `harvestBoostRewards()` — BGT delegation boost rewards to iBGT holders
- `harvestOperatorRewards()` — Operator commission distribution

**Frequency:** Every 24 hours (configurable)

**Fee split on each harvest:**
```
Protocol Fee = Reward * HarvestFeeRate / 1e6
User Reward = Reward - Protocol Fee
```

### 2.2 iBERA Deposits & Withdrawals — `ibera-keeper`

**Service:** [infrared-dao/ibera-keeper](https://github.com/infrared-dao/ibera-keeper)

Manages the full lifecycle of BERA → iBERA liquid staking at the consensus layer:

- **Deposits**: Monitors deposit queue; when ≥ 32 BERA is queued, processes deposits to validator via Berachain deposit precompile
- **Withdrawals**: Generates EIP-7002 withdrawal credentials, queues and monitors CL withdrawal completion
- **Proofs**: Works with [bera-proofs](https://github.com/infrared-dao/bera-proofs) for consensus layer state verification

**Timelines:**
- Deposit queue processing: up to 1 hour
- Withdrawal processing: ~27 hours (EIP-7002)

### 2.3 Validator Strategy — `infrared-strategy`

**Service:** [infrared-dao/infrared-strategy](https://github.com/infrared-dao/infrared-strategy)

Manages BGT emission allocation and boost strategy across all Infrared validators:

- **Cutting boards**: Queues and activates validator reward allocations (`queueNewCuttingBoard`)
- **BGT boosts**: Optimizes BGT delegation across validators (queue/activate/drop)
- **Auction integration**: Respects active `ValidatorControlAuction` NFT holders — does not override controlled validators during their allocation period

Holds `KEEPER_ROLE` on Infrared.sol.

### 2.4 Bribe Auctions — `auction-bot`

**Service:** [infrared-dao/auction-bot](https://github.com/infrared-dao/auction-bot)

Automates the bribe collection lifecycle:

1. Calls `infrared.harvestBribes(tokens)` to collect accumulated bribes to BribeCollector
2. Monitors BribeCollector and starts new auctions when conditions are met
3. Calls `collector.claimFees()` to distribute auction proceeds back to protocol

**See also:** `docs/CUTTING_BOARD_AUCTIONS.md` for the separate Validator Control Auction system.

### 2.5 Supporting Services

**bera-proofs** — [infrared-dao/bera-proofs](https://github.com/infrared-dao/bera-proofs)
Generates Berachain consensus layer state proofs used by ibera-keeper for deposit/withdrawal verification.

**uniswap-optimizer** — [infrared-dao/uniswap-optimizer](https://github.com/infrared-dao/uniswap-optimizer)
Maintains healthy IR and iBGT liquidity on Berachain DEXes by rebalancing and optimizing LP positions.

**merkle-claims** — [infrared-dao/merkle-claims](https://github.com/infrared-dao/merkle-claims)
Handles IR token airdrop distribution: generates merkle trees from snapshot data and serves proofs for the claim contract.

---

## 3. Governance Operations

**Role:** `DEFAULT_ADMIN_ROLE` (Safe multisig)
**Process:** All governance operations create Safe transactions requiring threshold signatures.

### 3.1 Validator Management

#### Onboard Validator

```bash
make gov-onboard-validator \
  PUBKEY=0x... \
  OPERATOR=0x... \
  SIGNATURE=0x... \
  NETWORK=mainnet
```

**Prerequisites:** [Validator signed deposit message, Validator public key, EVM address that will collect fees and rewards.](https://infrared.finance/docs/developers/validators)

**Post-deployment steps:**
1. Add to ibera-keeper config.
2. Set validator commission.

**⚠️ Important:** Always run `harvestBase()` and `harvestOperatorRewards()` before adding validators to avoid reward accounting issues. The backend service handles this; if adding manually, harvest first.

#### Remove Validator

```bash
make gov-remove-validator PUBKEY=0x... NETWORK=mainnet
```

Initiates EIP-7002 withdrawal (~27 hours for full exit). Harvest all rewards before removal.

### 3.2 Vault & Reward Management

#### Whitelist Reward Token

```bash
make gov-whitelist-token TOKEN=0x... NETWORK=mainnet
```

Script auto-checks ERC20 compliance and proxy detection. Manual review required:
- Contract verified on Berascan
- No fee-on-transfer or rebasing mechanism
- Trusted token issuer

#### Add Reward to Vault

```bash
make gov-add-reward \
  STAKING_TOKEN=0x... \
  REWARD_TOKEN=0x... \
  DURATION=604800 \
  NETWORK=mainnet
```

Duration in seconds: 1 week = 604800, 1 day = 86400.

#### Register New Vault

```bash
# Vault is auto-created on first staking token registration
# via infrared.registerVault(stakingToken)
make gov-register-vault ASSET=0x... NETWORK=mainnet
```

### 3.3 Fee Configuration

```bash
make gov-update-fee FEE_TYPE=<n> FEE=<amount> NETWORK=mainnet
```

**Always harvest all rewards before changing fees.**

| FeeType | Constant | Description |
|---------|----------|-------------|
| 0 | `HarvestOperatorFeeRate` | Keeper fee on operator harvests |
| 1 | `HarvestOperatorProtocolRate` | Protocol fee on operator harvests |
| 2 | `HarvestVaultFeeRate` | Keeper fee on vault harvests |
| 3 | `HarvestVaultProtocolRate` | Protocol fee on vault harvests |
| 4 | `HarvestBribesFeeRate` | Keeper fee on bribe harvests |
| 5 | `HarvestBribesProtocolRate` | Protocol fee on bribe harvests |
| 6 | `HarvestBoostFeeRate` | Keeper fee on boost harvests |
| 7 | `HarvestBoostProtocolRate` | Protocol fee on boost harvests |

**Fee format:** Units of 1e6 (1e6 = 100%). Examples: 5% = 50000, 10% = 100000.

### 3.4 Access Control

```bash
# Grant KEEPER_ROLE (applies to Infrared + InfraredBERA)
make gov-grant-keeper KEEPER=0x... NETWORK=mainnet

# Revoke KEEPER_ROLE
make gov-revoke-keeper KEEPER=0x... NETWORK=mainnet
```

### 3.5 Asset Recovery

```bash
make gov-recover-erc20 \
  TOKEN=0x... \
  RECIPIENT=0x... \
  AMOUNT=<wei> \
  NETWORK=mainnet
```

Cannot recover active staking tokens (would break accounting).

### 3.6 Bribe Collector Configuration

```bash
# Set payout token (currently iBGT)
make gov-set-bribe-payout TOKEN=0x... NETWORK=mainnet
```

---

## 4. State Monitoring

### Health Check

```bash
make health-check NETWORK=mainnet
```

### Key State Queries

```bash
make check-deposits NETWORK=mainnet        # Total iBERA deposits
make check-pending NETWORK=mainnet         # Pending validator stakes
make check-confirmed NETWORK=mainnet       # Confirmed CL stakes
make check-bgt NETWORK=mainnet             # BGT balance
make check-ibgt-supply NETWORK=mainnet     # iBGT total supply
make check-exchange-rate NETWORK=mainnet   # iBERA/BERA rate
make check-validator PUBKEY=0x... NETWORK=mainnet
make check-vault ASSET=0x... NETWORK=mainnet
make check-rewards USER=0x... NETWORK=mainnet
```

### Alert Thresholds

**Critical — immediate response required:**
- Exchange rate deviation > 10%
- Withdrawal queue > 75% of deposits
- Validator slashing detected
- Failed harvest > 36 hours
- Abnormal BGT balance drop

**Warning — review within 1 hour:**
- Exchange rate deviation > 5%
- Withdrawal queue > 50% of deposits
- Harvest missed > 26 hours
- Backend service offline > 2 hours
- Pending deposits > 100 BERA

### Cron Monitoring (supplemental to backend services)

```bash
# Daily health snapshot
0 8 * * * cd /path/to/repo && make health-check NETWORK=mainnet

# Exchange rate check
0 */6 * * * cd /path/to/repo && make check-exchange-rate NETWORK=mainnet
```

---

## 5. Emergency Procedures

### Pause Vault Staking

```bash
# Pause a single vault (PAUSER_ROLE or governance)
make gov-pause-vault ASSET=0x... NETWORK=mainnet

# Pause all vaults (requires confirmation)
make emergency-pause-all NETWORK=mainnet

# Unpause (governance only)
make gov-unpause-vault ASSET=0x... NETWORK=mainnet
```

**When to pause:**
- Vault contract vulnerability discovered
- Asset contract compromised
- Active protocol attack

### Safe Multisig Best Practices

1. **Simulate before signing** — Use Safe Transaction Builder; verify all parameters
2. **Verify addresses** — Double-check target contract, function signature, all parameters
3. **Batch transaction review** — Understand each operation, verify dependency order
4. **Quorum availability** — Keep threshold signers reachable 24/7

### Keeper Security

- Use dedicated wallet with only gas funds
- Monitor backend service logs for failed transactions
- Rotate keeper keys if compromise suspected: revoke old key, grant new key, update service config

### Escalation

1. **Protocol emergency:** Contact governance multisig signers immediately
2. **Backend service failure:** Check service logs, restart, alert DevOps
3. **Security incident:** Pause affected contracts, notify auditors, follow incident response
4. **Contract bugs:** Open issue at https://github.com/infrared-dao/infrared-contracts/issues

---

## 6. Manual Makefile Operations

These commands are for development, debugging, and emergency manual intervention. **In production, use the backend services.**

### Setup

```bash
cp .env.example .env      # Configure environment
make config-show          # Show current config
make config-validate      # Validate contract addresses
```

### Manual Harvest (emergency only)

```bash
make keeper-harvest NETWORK=mainnet               # All harvests
make keeper-harvest-base NETWORK=mainnet
make keeper-harvest-vault ASSET=0x... NETWORK=mainnet
make keeper-harvest-boost NETWORK=mainnet
make keeper-harvest-operator NETWORK=mainnet
make keeper-harvest-bribes NETWORK=mainnet
```

### Manual Boost Management (emergency only)

```bash
make keeper-queue-boost PUBKEY=0x... AMOUNT=<wei> NETWORK=mainnet
make keeper-activate-boost NETWORK=mainnet
make keeper-drop-boost PUBKEY=0x... AMOUNT=<wei> NETWORK=mainnet
```

### Manual Cutting Board Management

In production, `infrared-strategy` manages cutting board queuing and activation automatically, respecting active `ValidatorControlAuction` NFT holders. Use the steps below for manual intervention when `infrared-strategy` is unavailable or a specific validator requires immediate correction.

**Queue a new cutting board (KEEPER_ROLE required):**

`queueNewCuttingBoard` is called directly via forge script. The `startBlock` must be a future block. Weights must be valid vault addresses with basis points summing to 10000.

```bash
forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
  --sig "queueNewCuttingBoard(bytes,uint64,(address,uint96)[])" \
  $PUBKEY $START_BLOCK "[($VAULT_ADDR,$WEIGHT)]" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Activate a queued cutting board (after 1 epoch):**

```bash
make keeper-activate-cutting-board PUBKEY=0x... NETWORK=mainnet
```

To activate cutting boards for multiple validators in a single transaction, use the shell script directly:

```bash
# Edit PUBKEYS array in the script, then run:
bash shell/keeper/keeper_activate_queued_cutting_board.sh
```

**Check current cutting board state:**

```bash
# View queued cutting board for a validator
cast call $INFRARED_PROXY "queuedCuttingBoard(bytes)((uint64,(address,uint96)[]))" $PUBKEY \
  --rpc-url $RPC_URL
```

> **Note:** Do not manually queue cutting boards for validators that are currently under `ValidatorControlAuction` NFT control — the NFT holder has priority until their allocation period expires. Check `docs/CUTTING_BOARD_AUCTIONS.md` for details.

---

### Manual Bribe & Auction Claiming

In production, `auction-bot` manages the full bribe lifecycle. The steps below replicate it manually.

**Step 1 — Harvest bribes from vaults to BribeCollector:**

Specify the whitelisted bribe tokens that have accumulated in the PoL vaults. WBERA and HONEY are always included; add any additional whitelisted tokens.

```bash
make keeper-harvest-bribes NETWORK=mainnet
```

Or via shell script (edit the token list for the current epoch):

```bash
# Edit INCENTIVE_TOKENS array in the script, then run:
bash shell/keeper/keeper_harvest_bribes.sh
```

**Step 2 — Claim incentives from BribeCollector to the multisig:**

After bribes are in the collector, claim them with expected minimum amounts (set to 0 for any-amount):

```bash
make keeper-claim-incentives TOKENS=0x...,0x... NETWORK=mainnet
```

Or via shell script (edit recipient, tokens, and amounts):

```bash
bash shell/keeper/keeper_claim_incentives.sh
```

**Step 3 — Sweep accumulated payout token (iBGT) to sIR vault:**

If using `IRAuction`, sweep any accumulated IR/iBGT payout into the staked IR vault:

```bash
bash shell/keeper/keeper_sweep_payout_token.sh
```

**Base reward auction claiming:**

The `BaseCollector` (if deployed) follows the same pattern as BribeCollector. Check `DEPLOYMENTS.md` for the BaseCollector address and use `claimFees()` directly via cast:

```bash
cast send $BASE_COLLECTOR "claimFees()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

---

### Manual iBERA Keeper Operations

In production, `ibera-keeper` handles all consensus layer deposit and withdrawal proof submissions. The steps below are for manual intervention. Proof data is generated by the [bera-proofs](https://github.com/infrared-dao/bera-proofs) service, which requires access to a beacon RPC endpoint.

#### Prerequisites

Ensure `bera-proofs` is running and accessible:

```bash
# bera-proofs requires a beacon RPC endpoint
# Set BEACON_RPC_URL in your environment (e.g. https://beacon.berachain.com)
# The service exposes proof data as JSON files consumed by the keeper scripts
```

#### Execute Deposit Proofs

Used after BERA has been queued in `InfraredBERADepositor` and the corresponding validators have been activated on the consensus layer. The `AMOUNT` is the total BERA (in wei) being confirmed, and `PROOFS_PATH` is the proof JSON from bera-proofs.

```bash
forge script script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper \
  --sig "executeDepositProofs(address,uint256,string)" \
  $DEPOSITOR $AMOUNT $PROOFS_PATH \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv
```

Or via shell script (edit `AMOUNT` and `PROOFS_PATH`):

```bash
bash shell/keeper/keeper_execute_proofs_iberadepositor.sh
```

#### Execute Withdrawal Proofs

Used after an EIP-7002 voluntary exit has completed (~27 hours) and the withdrawn BERA is available. `AMOUNT` is the total BERA withdrawn and `PROOFS_PATH` is the corresponding proof JSON.

```bash
forge script script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper \
  --sig "executeWithdrawProofs(address,uint256,string)" \
  $WITHDRAWOR $AMOUNT $PROOFS_PATH \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast -vvvv
```

Or via shell script (edit `AMOUNT` and `PROOFS_PATH`):

```bash
bash shell/keeper/keeper_execute_proofs_iberawithdrawor.sh
```

#### Queue Validator Rebalance

Used to shift stake from one validator depositor to the withdrawor queue, triggering a rebalance between validators. `AMOUNT` is the BERA (in wei) to move.

```bash
cast send $WITHDRAWOR "queue(address,uint256)" $DEPOSITOR $AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

Or via shell script (edit `WITHDRAWOR`, `DEPOSITOR`, and `AMOUNT`, then uncomment the live `cast send`):

```bash
bash shell/keeper/keeper_queue_rebalance.sh
```

#### iBERA State Checks

```bash
make check-deposits NETWORK=mainnet               # Total tracked BERA
make check-pending NETWORK=mainnet                # BERA in queues (not yet on CL)
make check-confirmed NETWORK=mainnet              # BERA confirmed on CL
make check-exchange-rate NETWORK=mainnet          # iBERA/BERA rate
make check-ibera-withdrawal-queue NETWORK=mainnet # Queued withdrawal amount
```

---

### Build & Test

```bash
make build                    # Development build
make build-production         # Optimizer: 50 runs
make test                     # All tests
make test-unit                # Unit tests
make test-integration         # Integration tests
make test-coverage            # Coverage report
make format && make lint       # Code quality
```

**See `MAKEFILE_REFERENCE.md` for the complete command reference.**
**See `shell/README.md` for a full index of shell scripts.**

---

## 7. Reference

### Expected Timelines

| Operation | Duration |
|-----------|----------|
| User deposit → receive iBERA | Instant |
| Deposit queue processing | Up to 1 hour |
| Validator activation | Up to 27 hours |
| Reward harvest cycle | Every 24 hours |
| iBERA withdrawal | ~27 hours (EIP-7002) |
| BGT boost activation | 1 epoch after queuing |

### iBERA Exchange Rate

```
Exchange Rate = deposits / totalSupply

Mint:  shares = (totalSupply × amount) / deposits
Burn:  amount = (deposits × shares) / totalSupply
```

### Fee Calculation

```
Protocol Fee = Reward × HarvestFeeRate / 1e6
User Reward  = Reward − Protocol Fee
```

### Related Documentation

| Document | Purpose |
|----------|---------|
| `MAKEFILE_REFERENCE.md` | Quick command reference |
| `DEPLOYMENTS.md` | Contract addresses |
| `docs/UPGRADE_GUIDE.md` | Safe upgrade procedures for all upgradeable contracts |
| `docs/IR_BRIDGE.md` | IR token LayerZero bridge (Berachain ↔ BSC) |
| `docs/CUTTING_BOARD_AUCTIONS.md` | Cutting board Dutch auctions and validator control auctions |
| `src/staking/README.md` | iBERA staking architecture |
| `src/core/README.md` | Core protocol architecture |
| `CLAUDE.md` | Full codebase guide for developers |
| `SECURITY.md` | Bug bounty and responsible disclosure |

---

**Maintained By:** Infrared Protocol Team
**Review Schedule:** After major upgrades or service changes
