# Periphery Module

Peripheral contracts that extend the core protocol with reward distribution, auction mechanics, claim aggregation, and cross-chain functionality. These contracts interact with the core `Infrared` contract but are not part of its upgrade surface.

## Contracts

### Reward Distribution

#### `RewardDistributor`

Maintains a target APR for a specific vault by computing and executing periodic keeper-driven reward distributions.

**How it works:**
1. A governance-authorized keeper calls `distribute(maxTotalSupply)` after the `distributionInterval` has elapsed
2. The contract computes how many `rewardsToken` are needed to hit `targetAPR` based on current vault total supply
3. It calls `infrared.addIncentives(stakingToken, rewardsToken, amount)` to deposit the rewards into the vault
4. `maxTotalSupply` is checked against actual supply to guard against sandwich attacks (`maxSupplyDeviation`)

**Key parameters:**
| Parameter | Description |
|-----------|-------------|
| `targetAPR` | Desired annual yield in basis points |
| `distributionInterval` | Minimum seconds between distributions |
| `maxSupplyDeviation` | Max allowed supply change (sandwich protection) |

**Admin functions:** `setTargetAPR()`, `setDistributionInterval()`, `setMaxSupplyDeviation()`, `updateKeeper()`, `withdrawRewards()`, `recoverERC20()`

---

#### `BYUSDRewardDistributor`

Advanced reward distributor for BYUSD rewards. Accepts an underlying token (e.g., raw BYUSD) and wraps it into a vault-compatible reward token on a linear vesting schedule before distributing.

**Key difference from `RewardDistributor`:** Tokens are deposited with a `duration` unlock schedule, preventing sudden APR spikes from large one-time deposits. A forward-unlock mechanism allows distributing up to one full reward period ahead of the schedule.

**Flow:**
1. Admin calls `depositUnderlying(amount, start, duration)` to add tokens with a vesting schedule
2. Keeper calls `distribute(maxTotalSupply)`:
   - Unlocks available underlying tokens (`_unlock()`)
   - Wraps them into `rewardsToken` via `WrappedRewardToken`
   - Checks APR won't decrease
   - Calls `infrared.addIncentives()`

**Additional events:** `UnderlyingDeposited`, `UnlockedAndWrapped`

---

#### `WrappedRewardToken`

ERC-4626-style wrapper for low-decimal tokens (e.g., 6-decimal USDC/BYUSD) that normalizes them to 18-decimal vault reward tokens.

- `scaling = 1e18 / asset.decimals()` — conversion factor applied on deposit/withdraw
- Used by `BYUSDRewardDistributor` to create a `rewardsToken` compatible with `InfraredVault`

---

#### `IRRewardDistributor`

Distributes IR token emissions to multiple vaults on a configurable epoch schedule with weighted allocation.

**Allocation logic:**
- A mandatory minimum percentage (`minIBGTAllocation`) always goes to the iBGT vault
- Remaining rewards go to eligible vaults proportional to their configured weights
- Failed distributions (e.g., vault not accepting rewards) accumulate in `carryOverRewards` and are retried next epoch

**Key parameters:**
| Parameter | Description |
|-----------|-------------|
| `totalRewardsPerEpoch` | Total IR emitted per epoch |
| `epochDuration` | Seconds per epoch |
| `minIBGTAllocation` | Basis points (max 5000) reserved for iBGT vault |
| `defaultVaultWeights` | Per-vault basis point weights (must sum to 10000) |

**Vault management:** `excludeVault()`, `includeVault()`, `addEligibleVault()`, `removeEligibleVault()`

**View helpers:** `getVaultAllocation(vault)`, `getNextEpochRewards(vault)`, `timeUntilNextEpoch()`

---

### Auction Contracts

See [`docs/CUTTING_BOARD_AUCTIONS.md`](../../docs/CUTTING_BOARD_AUCTIONS.md) for detailed documentation on the cutting board auction system.

#### `CuttingBoardDutchAuction`

Runs Dutch auctions granting temporary control of a validator's PoL cutting board allocation. Price decays linearly from `startingPrice` to a minimum over `auctionDuration`. Winners receive a `CuttingBoardNFT` and set the initial cutting board weights at claim time.

**Price formula:** `startingPrice → basePrice` (linear decay over auction duration), then constant at `minimumPrice`.

**Key state:**
- `auctionValidators` — pubkey for each auction ID
- `activeValidatorAuctions` — current active auction per validator
- `validatorControlTokenId` — current NFT token ID per validator

---

#### `CuttingBoardNFT`

ERC-721 NFT representing cutting board control rights for a specific validator and auction period.

Each token tracks:
- `validatorPubkey` — the validator being controlled
- `expiryTimestamp` — when the control period ends
- `auctionId` — the originating auction
- `active` — whether the token has been revoked

**Minting:** Only callable by `CuttingBoardDutchAuction`
**Invalidation:** Callable by the `manager` address (`CuttingBoardManager`)

---

#### `CuttingBoardManager`

Rate-limited contract for NFT holders to update a validator's cutting board. Implements a two-step propose/approve flow.

**Flow:**
1. NFT holder calls `proposeCuttingBoard(tokenId, startBlock, weights[])`
2. Keeper calls `approveCuttingBoard(tokenId)` after validating the proposal
3. Manager calls `infrared.queueNewCuttingBoard()` on approval

**Rate limiting:** `MIN_UPDATE_DELAY` blocks (~8 minutes) must elapse between updates per token.

**Governance:** `revokeControl(tokenId)` invalidates an NFT early. `setProposalValidityDuration()` adjusts how long proposals stay valid.

---

#### `IRAuction`

Auction mechanism for iBGT vault rewards. Pays out IR tokens in exchange for reward tokens, then auto-compounds the accumulated IR into the sIR staking vault.

- `claimFees()` — keeper pays `payoutAmount` IR, receives all available reward tokens
- `sweepPayoutToken()` — compounds accumulated IR into `SIR_VAULT`
- `setPayoutAmount()` — governance updates IR price per claim

---

### Claim Aggregation

#### `BatchClaimerV2_2`

Aggregates reward claims from multiple `InfraredVault` positions into a single transaction.

**`batchClaim(user, stakingAssets[])`:**
1. For each staking asset, locates the `InfraredVault` and calls `getRewardForUser(user)`
2. If the vault's operator is Infrared, also claims from the underlying `BerachainRewardsVault`
3. Auto-unwraps `wBYUSD` and `wiBGT` tokens if the user has approved the contract

**Current hardcoded constants:**
- `infrared` = InfraredV1_9 address
- `wBYUSD` = wBYUSD token address

---

#### `MerkleDistributor`

Token distribution contract using a Merkle tree for proof-based claims. Suitable for one-time airdrops or reward snapshots.

**Parameters set at deploy time (immutable):**
- `token` — ERC-20 to distribute
- `merkleRoot` — root of the claim tree
- `claimDeadline` — timestamp after which unclaimed tokens can be recovered

**Operations:**
- `claim(index, account, amount, proof)` / `claimFor(...)` — claim with merkle proof
- `pause()` / `unpause()` — emergency pause (governance)
- `withdrawUnclaimed(recipient)` — recover tokens after deadline
- `recoverERC20(token, amount, recipient)` — recover non-distributed tokens

---

#### `Redeemer`

Permissionless contract allowing any holder to redeem iBGT for BERA, provided Infrared has sufficient unboosted BGT on hand.

- `redeemIbgtForBera(amount)` — burns `amount` iBGT, calls Infrared to send BERA, reverts if `unboostedBGT < amount`
- Only redeems from the unboosted portion to avoid disrupting active boost delegations

---

### Cross-Chain

#### `IROFT`

LayerZero OFT (Omnichain Fungible Token) implementation for the IR token on non-native chains. Deployed fresh on destination chains where no existing IR token exists.

#### `IROFTAdapter`

LayerZero OFT adapter wrapping an existing IR token contract. Deployed on the source chain (Berachain mainnet) to enable cross-chain transfers of the canonical IR token.

> See [`docs/IR_BRIDGE.md`](../../docs/IR_BRIDGE.md) for full cross-chain bridge documentation.

## Integration Points

| Contract | Calls into |
|----------|-----------|
| `RewardDistributor` | `Infrared.addIncentives()` |
| `BYUSDRewardDistributor` | `Infrared.addIncentives()` |
| `IRRewardDistributor` | `Infrared.addIncentives()` |
| `IRAuction` | `IStakedIR.deposit()` |
| `CuttingBoardManager` | `Infrared.queueNewCuttingBoard()` |
| `BatchClaimerV2_2` | `InfraredVault.getRewardForUser()`, `BerachainRewardsVault.getReward()` |
| `Redeemer` | `Infrared` (ETH transfer callback) |
