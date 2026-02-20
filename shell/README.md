# Shell Scripts

Operational shell scripts for deployment, governance, keeper operations, and upgrades. These are the low-level counterparts to the Makefile targets — use them when you need finer control than the Makefile provides (e.g. multi-validator batches, custom amounts, or operations not exposed as Makefile targets).

All scripts `source .env` or `source ./shell/keeper/keeper_common.sh` for RPC and key configuration. See `.env.example` for required variables.

> **Production note:** Keeper and governance operations in production are handled by backend services. These scripts are for manual intervention, testing, and one-off operations.

---

## `beacon/`

Utilities for querying the Berachain consensus layer via the Beacon API.

| Script | Description |
|--------|-------------|
| `get_beacon_block.sh` | Fetch latest beacon block header and extract slot/proposer data |
| `get_latest_beacon_state.sh` | Fetch latest beacon state root and download SSZ-encoded beacon state |

---

## `beraswap/`

Pool deployment and liquidity provisioning for Beraswap (Balancer-based DEX).

| Script | Description |
|--------|-------------|
| `deploy-beraswap-pool.sh` | Deploy a weighted 50/50 WBERA/iBERA pool |
| `deploy-beraswap-pool-stable.sh` | Deploy a stable pool for WBERA/iBERA with the `InfraredBERARateProvider` |
| `join-beraswap-pool.sh` | Supply iBGT and WBERA liquidity to a weighted pool |
| `join-beraswap-pool-stable.sh` | Supply WBERA and iBERA liquidity to a stable pool |

---

## `deploy/`

Initial deployment scripts for individual contracts. For full-protocol deployment see `deploy-mainnet.sh` / `deploy-bepolia.sh`.

| Script | Description |
|--------|-------------|
| `deploy-mainnet.sh` | Deploy full Infrared protocol on Berachain mainnet |
| `deploy-bepolia.sh` | Deploy full Infrared protocol on Bepolia testnet |
| `deploy-ir.sh` | Deploy IR governance token on mainnet |
| `deploy-ir-bepolia.sh` | Deploy IR governance token on Bepolia testnet |
| `deploy-staked-ir.sh` | Deploy StakedIR (sIR) contract (dry run — uncomment `cast send` to execute) |
| `deploy-cutting-board-dutch-auction.sh` | Deploy `CuttingBoardDutchAuction` on mainnet with IR token as payment |
| `deploy-cutting-board-dutch-auction-bepolia.sh` | Deploy `CuttingBoardDutchAuction` on testnet with test parameters |
| `deploy-merkle-distributor.sh` | Deploy `MerkleDistributor` for IR token airdrop on mainnet |
| `deploy-merkle-distributor-bepolia.sh` | Deploy `MerkleDistributor` for IR token airdrop on testnet |
| `deploy-reward-distributor.sh` | Deploy `RewardDistributor` for a staking vault |
| `deploy-byusd-reward-distributor.sh` | Deploy `BYUSDRewardDistributor` for BYUSD vault rewards |
| `deploy-ir-reward-distributor.sh` | Deploy `IRRewardDistributor` for IR emissions to vaults |
| `deploy-rate-provider.sh` | Deploy `InfraredBERARateProvider` for Beraswap pool pricing |
| `deploy-redeemer.sh` | Deploy `Redeemer` contract for permissionless iBGT → BERA redemption |
| `deploy-wrapped-reward-token.sh` | Deploy `WrappedRewardToken` for decimal-normalizing reward tokens |

---

## `gov/`

Governance operations requiring `GOVERNANCE_ROLE` (Safe multisig). Scripts submit transactions via the multisig or broadcast directly depending on the operation.

### Validator Management

| Script | Description |
|--------|-------------|
| `add-validator-mainnet.sh` | Add a new validator with BLS public key and operator address |
| `remove-validator-mainnet.sh` | Remove a validator by BLS public key |
| `onboard-validator.sh` | Full validator onboarding with BLS key and signature verification |
| `set-deposit-sig-mainnet.sh` | Set BLS deposit signature for validator registration |
| `set-commission.sh` | Queue commission activation for multiple validators |

### Vault & Reward Management

| Script | Description |
|--------|-------------|
| `add-reward.sh` | Add a reward token to an InfraredVault |
| `remove-reward.sh` | Remove a reward token from an InfraredVault |
| `whitelist-token.sh` | Whitelist a single token for vault rewards |
| `whitelist-tokens.sh` | Whitelist multiple tokens for vault rewards in batch |
| `update-vault-reward-duration.sh` | Update the reward distribution duration for a vault |
| `migrate-vault.sh` | Migrate a single InfraredVault to a new implementation |
| `migrate-multiple-vaults.sh` | Migrate ~71 InfraredVaults to a new implementation in batch |
| `pause-multiple-vaults-staking.sh` | Pause staking on multiple vaults |

### Fee Configuration

| Script | Description |
|--------|-------------|
| `update-fee.sh` | Update a single fee type by index (see fee types in `OPERATIONS.md §3.3`) |
| `multisig-set-fees.sh` | Set multiple fee rates in one multisig batch |
| `update-ibera-ibgtvault-bribe-split.sh` | Adjust the iBERA/iBGT vault bribe split ratio |

### Collector Configuration

| Script | Description |
|--------|-------------|
| `set-collector-payout-token.sh` | Set the BribeCollector payout token |
| `set-collector-payout-amount.sh` | Set the BribeCollector payout amount per claim |
| `set-base-collector-payout-amount.sh` | Set the BaseCollector payout amount |
| `claim-fees.sh` | Claim accumulated protocol fees (iBGT, wiBGT, iBERA, HONEY, WBERA) |

### Access Control

| Script | Description |
|--------|-------------|
| `grant_keeper_role.sh` | Grant `KEEPER_ROLE` on both Infrared and InfraredBERA |
| `grant_keeper_role_only_infrared.sh` | Grant `KEEPER_ROLE` on Infrared only |
| `grant_keeper_role_only_ibera.sh` | Grant `KEEPER_ROLE` on InfraredBERA only |
| `grant_keeper_role_base-collector.sh` | Grant `KEEPER_ROLE` on BaseCollector |
| `grant_keeper_role_byusd-dist.sh` | Grant `KEEPER_ROLE` on BYUSDRewardDistributor |
| `add-redeemer.sh` | Grant redeemer role on Infrared to the Redeemer contract |

### Asset Recovery

| Script | Description |
|--------|-------------|
| `recoverERC20.sh` | Recover stuck ERC20 tokens from the Infrared contract |
| `recover-erc20-vault.sh` | Recover stuck ERC20 tokens from a current-version InfraredVault |
| `recover-erc20-old-vault.sh` | Recover stuck ERC20 tokens from a deprecated InfraredVault |
| `withdraw-unclaimed.sh` | Withdraw unclaimed tokens from a MerkleDistributor after deadline |

### Utilities

| Script | Description |
|--------|-------------|
| `multisend.sh` | Batch distribute iBGT tokens to ~870 addresses via Safe multisend |
| `tmp.sh` | Scratch / temporary script (not for production use) |

---

## `keeper/`

Operational scripts requiring `KEEPER_ROLE`. Most source `keeper_common.sh` for shared config.

### Shared Config

| Script | Description |
|--------|-------------|
| `keeper_common.sh` | Shared variables: `RPC_URL`, `SCRIPT`, `SAFE` address |

### Harvesting

| Script | Description |
|--------|-------------|
| `keeper_harvest.sh` | Harvest rewards from a set of InfraredVaults (specify staking tokens) |
| `keeper_harvest_bribes.sh` | Harvest accumulated bribes from PoL vaults to BribeCollector |
| `keeper_harvest_old_vault.sh` | Harvest rewards from deprecated vault implementations (~69 vaults) |
| `keeper_claim_incentives.sh` | Claim bribe incentives from BribeCollector to the multisig |
| `keeper_sweep_payout_token.sh` | Sweep accumulated IR payout tokens from IRAuction into the sIR vault |

### BGT Boost Management

| Script | Description |
|--------|-------------|
| `keeper_queue_boosts.sh` | Queue BGT boost delegation for validators (pending activation) |
| `keeper_activate_boosts.sh` | Activate queued BGT boosts for specified validators |
| `keeper_activate_and_boost.sh` | Activate boost and queue new delegation in a single operation |
| `keeper_activate_and_boost_max.sh` | Activate boost and delegate maximum available BGT |
| `keeper_activate_and_boost_max_eoa.sh` | `activate_and_boost_max` variant for EOA-operated validators |
| `keeper_activate_boost_eoa.sh` | Activate boost for an EOA-operated validator |
| `keeper_cancel_queue_boosts.sh` | Cancel a pending queued boost before it activates |
| `keeper_cancel_queue_boosts_eoa.sh` | Cancel queued boost for an EOA-operated validator |
| `keeper_queue_drop_boosts.sh` | Queue a boost removal (takes effect after delay) |
| `keeper_queue_drop_boost_eoa.sh` | Queue boost removal for an EOA-operated validator |
| `keeper_cancel_drop_boosts.sh` | Cancel a pending boost removal |
| `keeper_drop_boosts.sh` | Drop active boosts immediately |
| `keeper_activate_commissions.sh` | Activate queued commission payouts for validators |

### Cutting Boards

| Script | Description |
|--------|-------------|
| `keeper_activate_queued_cutting_board.sh` | Activate queued cutting boards for multiple validators in one transaction |

### iBERA Keeper Operations

| Script | Description |
|--------|-------------|
| `keeper_execute_iberadepositor.sh` | Execute a BERA deposit to a specific validator via the deposit precompile |
| `keeper_execute_proofs_iberadepositor.sh` | Submit beacon proof confirming a validator deposit to `InfraredBERADepositor` |
| `keeper_execute_proofs_iberawithdrawor.sh` | Submit beacon proof confirming a validator withdrawal to `InfraredBERAWithdrawor` |
| `keeper_sweep_iberawithdrawor.sh` | Sweep pending processed withdrawals from the withdrawor queue |
| `keeper_queue_rebalance.sh` | Queue stake rebalance — moves BERA from a depositor to the withdrawor |
| `keeper_queue_withdraw_eoa.sh` | Queue a validator withdrawal for an EOA-operated validator |
| `keeper_register_via_proofs_eoa.sh` | Register an EOA validator using beacon chain state proofs |

---

## `misc/`

One-off utility scripts.

| Script | Description |
|--------|-------------|
| `add-multisig-delegate.sh` | Register a delegate address with the Safe transaction service |
| `get-all-berachain-whitelist-incentives.sh` | Query all active PoL incentive programs and their current reward rates |
| `get-total-assets.sh` | Display total TVL across all active InfraredVaults |

---

## `tests/`

Fork-test scripts for validating contract behaviour against live state.

| Script | Description |
|--------|-------------|
| `test-fork-reward-distributor.sh` | Test `RewardDistributor` on a forked mainnet with impersonated keeper |
| `test-ibera-upgrade-bepolia.sh` | Test iBERA v2.1 upgrade on a forked Bepolia testnet including withdrawal scenarios |

---

## `upgrades/`

Scripts for deploying new implementations and executing Safe-batched upgrades. Each contract has versioned subdirectories. The pattern within each version is:

| Filename pattern | Purpose |
|-----------------|---------|
| `deploy-*.sh` | Deploy new implementation contract(s) only (no proxy change) |
| `upgrade-*.sh` | Submit upgrade batch to Safe multisig |
| `upgrade-*-bepolia.sh` | Execute upgrade directly on testnet (no multisig) |
| `test-*-upgrade.sh` | Fork test validating the upgrade before execution |

### BribeCollector

| Version | Scripts |
|---------|---------|
| `bribe-collector/v1.2/` | Deploy + upgrade for v1.2 on mainnet and testnet |
| `bribe-collector/v1.3/` | Deploy + upgrade for v1.3 on mainnet and testnet |

### BaseCollector

| Version | Scripts |
|---------|---------|
| `base-collector/` | Upgrade BaseCollector to latest implementation |

### Infrared (Core)

| Version | Scripts |
|---------|---------|
| `infrared/v1.2/` | Infrared V1.2 — deploy, upgrade, test |
| `infrared/v1.3/` | Infrared V1.3 — deploy, upgrade, test |
| `infrared/v1.4/` | Infrared V1.4 — deploy, upgrade, test |
| `infrared/v1.5/` | Infrared V1.5 — deploy, upgrade, test |
| `infrared/v1.7/` | Infrared V1.7 — upgrade + fork test |
| `infrared/v1.8/` | Infrared V1.8 — upgrade + testnet upgrade |
| `infrared/v1.9/` | Infrared V1.9 — upgrade |
| `infrared/v1.10/` | Infrared V1.10 — upgrade (adds IR token + StakedIR + IRAuction) |

### Staking (InfraredBERA)

| Version | Scripts |
|---------|---------|
| `staking/v2.0/` | InfraredBERA V2.0 — deploy implementations, upgrade proxies (depositor + withdrawor + ibera), validator onboarding |
| `staking/v2.1/` | InfraredBERA V2.1 — upgrade proxies with improved withdrawal handling |

> See `docs/UPGRADE_GUIDE.md` for the full step-by-step upgrade procedure.
