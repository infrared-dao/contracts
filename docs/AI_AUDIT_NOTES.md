# Apex Report - Infrared-contracts / Infrared-Pilot

## Table of contents

- [High](#high)
  - [INFR-6 — Harvest sniping steals accrued PoL rewards by distributing harvested BGT->iBGT based on post-harvest stake](#finding-infr-6)
- [Medium](#medium)
  - [INFR-9 — Approved cutting board updates can activate after control-NFT expiry (timestamp/block mismatch)](#finding-infr-9)
  - [INFR-8 — StakedIR CREATE2 pre-fund forces 0-share initialization and permanently bricks the vault](#finding-infr-8)
  - [INFR-4 — BYUSDRewardDistributor.depositUnderlying is permissionless, enabling vest-spam gas griefing that can halt APR distributions](#finding-infr-4)
- [Informational](#informational)
  - [INFR-7 — IRRewardDistributor uninitialized proxy takeover allows attacker to steal all IR incentive funds and redirect epoch distributions](#finding-infr-7)
  - [INFR-5 — Emergency pause is ineffective: InfraredBERAV2_1 mint/burn/compound remain callable while paused](#finding-infr-5)
  - [INFR-3 — StakedIR uses a non-ERC-7201 storage namespace slot (wrong derivation), risking storage corruption on upgrade](#finding-infr-3)
  - [INFR-2 — InfraredDeployer mainnet flow deploys iBERA stack behind uninitialized proxies, enabling attacker initialization front-run to steal all BERA deposits and fee flows](#finding-infr-2)
  - [INFR-1 — CUTTING_BOARD_AUCTIONS.md deploy instructions reference non-existent ValidatorControl* contracts/scripts](#finding-infr-1)

---

<a id="high"></a>
## High

<a id="finding-infr-6"></a>
### INFR-6 — Harvest sniping steals accrued PoL rewards by distributing harvested BGT->iBGT based on post-harvest stake

#### Finding

InfraredVault harvests Berachain PoL rewards lazily during user reward claims: `MultiRewards.getRewardForUser()` calls the vault hook `onReward()`, which calls `Infrared.harvestVault(stakingToken)`. `harvestVault()` then claims the vault's accumulated BGT from the Berachain `RewardVault`, mints iBGT, and notifies the vault to distribute iBGT over `rewardsDuration` starting at the harvest timestamp.

Because BGT accrues continuously in the Berachain `RewardVault` to the *vault contract address* (based on the vault's aggregate stake), but Infrared only converts and accounts for it inside MultiRewards *when harvested*, the entire "backlog" of already-earned BGT becomes a new forward-looking iBGT distribution period. A remote, unprivileged attacker can stake a large amount immediately before calling `getReward()`/`harvestVault()`, capturing most of the already-earned backlog despite not being staked during the accrual window.

**Code path:**
When anyone calls `getReward()` on a vault, the reward claim flow unconditionally harvests external PoL rewards first:

```solidity
function getRewardForUser(address _user)
    public
    nonReentrant
    updateReward(_user)
{
    onReward();
    // ... transfers already-accounted rewards
}
```

```solidity
function onReward() internal override {
    IInfrared(infrared).harvestVault(address(stakingToken));
}
```

The Infrared coordinator's harvest converts accumulated Berachain BGT into iBGT and *starts/extends* a MultiRewards distribution period from "now":

```solidity
rewardsVault.getReward(address(vault), address(this));
bgtAmt = IBerachainBGT(bgt).balanceOf(address(this)) - balanceBefore;
IInfraredBGT(ibgt).mint(address(this), bgtAmt);
vault.notifyRewardAmount(ibgt, _amt);
```

Meanwhile, stake/withdraw hooks only move LP collateral in/out of the Berachain `RewardVault` and do not harvest/checkpoint external rewards:

```solidity
function onStake(uint256 amount) internal override {
    stakingToken.safeApprove(address(rewardsVault), amount);
    rewardsVault.stake(amount);
}

function onWithdraw(uint256 amount) internal override {
    rewardsVault.withdraw(amount);
}
```

**Root cause:** The system treats already-earned external rewards (BGT accrued inside Berachain's `RewardVault`) as newly-starting internal rewards (iBGT distributed by MultiRewards), without any mechanism to ensure the internal distribution reflects the stake composition over the accrual window.

**References:**
1. [contracts/src/core/MultiRewards.sol#L239-L282]
2. [contracts/src/core/InfraredVault.sol#L90-L112]
3. [contracts/src/core/InfraredV1_10.sol#L596-L603]
4. [contracts/src/core/libraries/RewardsLib.sol#L302-L341]

#### Response — Not viable in production

The theoretical unfairness exists (this is inherent to the Synthetix/Curve MultiRewards design used everywhere in DeFi), but with our operational parameters it is economically irrelevant.

**Production parameters:**

| Parameter | Value |
|---|---|
| Total staked | 8M iBGT |
| APR | ~40% |
| Harvest frequency | every 15 min |
| rewardsDuration | 24 hours (86,400s) |

**Per-harvest BGT accrual:**
- Annual rewards = 8M × 0.40 = 3.2M iBGT/year
- Per 15-min harvest = 3.2M / 35,040 ≈ 91.3 iBGT

In steady state, `_notifyRewardAmount` is called every 15 min. It combines the new ~91.3 iBGT with the leftover from the existing stream and resets `periodFinish`. The rate barely changes — the system is effectively a continuous stream.

**Attack economics (attacker stakes 8M, doubling the pool):**

| Metric | Value |
|---|---|
| Capital required | 8M staking tokens |
| Unfair capture (one harvest) | 50% × 91.3 = ~45.6 iBGT |
| Streamed over | 24 hours |
| But next harvest in | 15 min (resets the math) |

If the attacker stays 24h to fully extract that one batch, they capture ~45.6 iBGT they "didn't earn" — but they also legitimately earned ~4,383 iBGT (their fair 50% of 24h rewards). The "theft" is 45.6 iBGT on 8M capital = 0.00057% return.

If using a flash loan (stake for 1 block ≈ 2s): capture ≈ 0.001 iBGT vs. flash loan fee (0.09%) = 7,200 iBGT. Net: massive loss.

**Sensitivity (what if harvests are delayed):**

| Harvest gap | Backlog | Unfair capture (8M attacker) | Capital efficiency |
|---|---|---|---|
| 15 min (normal) | 91.3 iBGT | 45.6 iBGT | 0.00057% |
| 1 hour | 365 iBGT | 182 iBGT | 0.0023% |
| 6 hours | 2,190 iBGT | 1,095 iBGT | 0.014% |
| 24 hours | 8,767 iBGT | 4,383 iBGT | 0.055% |

Even at a 24-hour gap (worst case), the attacker needs 8M capital to steal ~4,383 iBGT (~$13k at ~$3/iBGT) — and they must stay staked the full 24h to realize it.

**Additionally, user claims also trigger harvests.** The `onReward()` hook calls `harvestVault` on every user claim. With 8M staked across many users, claims happen constantly — not just every 15 min from the keeper. This makes the effective backlog even smaller.

**The `updateReward` checkpoint on `stake()` partially mitigates but does not fully prevent the vector.** When the attacker calls `stake()`, the `updateReward` modifier snapshots `rewardPerTokenStored` into `userRewardPerTokenPaid[attacker]` — this prevents them from claiming any rewards that were already streaming before they staked. However, the attack vector is not about capturing already-streaming rewards. It's about the freshly harvested BGT backlog becoming a *new* stream via `notifyRewardAmount`. The checkpoint blocks double-claiming of pre-existing streams, but the harvested backlog creates a new stream where the attacker's large stake earns proportionally.

**The `updateReward` ordering provides an additional delay.** The `updateReward` modifier runs *before* `onReward()` in `getRewardForUser`, so the harvest that `onReward` triggers updates the reward rate for future accrual, but the current `updateReward` pass already locked in rewards based on the previous rate. The new iBGT from this harvest only starts accruing in the next interaction's `updateReward`. This one-interaction delay between harvesting and reward accounting further reduces extractable value.

**Conclusion:** The combination of frequent harvests (keeper bots + user claims), the `updateReward` checkpoint on `stake()` blocking pre-existing stream claims, and the one-interaction accounting delay make this attack economically irrelevant in production. The theoretical unfairness is inherent to the Synthetix/Curve MultiRewards design used throughout DeFi.

---

<a id="medium"></a>
## Medium

<a id="finding-infr-9"></a>
### INFR-9 — Approved cutting board updates can activate after control-NFT expiry (timestamp/block mismatch)

#### Finding

The cutting board control NFT is intended to grant *temporary* control of a validator's reward allocation. However, `CuttingBoardManager.approveCuttingBoard()` uses an expiry check that mixes timestamp seconds with Berachain's `rewardAllocationBlockDelay` (a delay expressed in **blocks**) and does not account for the fact that queued allocations only become active when the Berachain `Distributor` later calls `BeraChef.activateReadyQueuedRewardAllocation()`.

This allows a bidder who legitimately owns a still-valid control NFT to get a cutting board proposal approved and queued *before* expiry, yet have that allocation become active *after* the NFT has expired. Once active, the reward allocation persists until replaced.

**Vulnerable logic:**

```solidity
// CuttingBoardManager.approveCuttingBoard
uint64 beraBlockDelay = $.chef.rewardAllocationBlockDelay();
(, uint256 expiry,, bool active) = $.controlNFT.getControlRights(tokenId);
if (!active) revert NFTInactive();
if (block.timestamp + (2 * uint256(beraBlockDelay)) > expiry) revert NFTExpired();

uint64 startBlock = uint64(block.number) + beraBlockDelay + 1;
$.infrared.queueNewCuttingBoard(pubkey, startBlock, proposal.weights);
```

**References:**
1. [contracts/src/periphery/CuttingBoardManager.sol#L300-L359]
2. [contracts/src/periphery/CuttingBoardDutchAuction.sol#L470-L507]

#### Response — Incorrect premise; the 2x multiplier is the intentional unit conversion

The finding claims the guard "mixes units" — `block.timestamp` (seconds) + `beraBlockDelay` (blocks). But the `2 *` multiplier *is* the unit conversion: Berachain has 2-second block times, so `2 * blockDelay` = `blockDelay` in seconds.

The check asks: "Is there enough time remaining on the NFT for the queued allocation to activate and run for at least one full delay period?"

- `startBlock = block.number + beraBlockDelay + 1` → activation is ~`beraBlockDelay * 2` seconds from now
- The guard requires `expiry - block.timestamp > 2 * beraBlockDelay` → the NFT must be valid for at least `beraBlockDelay` seconds beyond the activation time

**The "slower blocks" argument doesn't hold.** Berachain's block time is a protocol-level constant of 2 seconds. It's not variable like Ethereum pre-merge. Even if blocks were transiently slower (e.g., 3s due to network issues):

- `rewardAllocationBlockDelay` is 100 blocks in production
- At 2s/block: activation in ~200s
- At 3s/block: activation in ~300s, maximum drift is 100 seconds (~1.6 minutes)
- NFT expiry periods are measured in days to weeks — a 100-second edge case is operationally meaningless

**The 2x buffer is already conservative.** The guard uses `2 * beraBlockDelay`, not `1 *`. This requires the NFT to be valid for twice the activation delay, providing a 100% safety margin.

**Even if activation slipped past expiry — the impact is negligible:**
1. The NFT holder paid for the full period up to expiry — they're not getting free time
2. The keeper can queue a replacement allocation at any time after expiry
3. The `invalidate()` function lets the manager deactivate the NFT, and subsequent proposals revert with `NFTInactive`
4. There's no mechanism for the expired NFT holder to queue *new* allocations — they can only benefit from the tail of an already-approved one

---

<a id="finding-infr-8"></a>
### INFR-8 — StakedIR CREATE2 pre-fund forces 0-share initialization and permanently bricks the vault

#### Finding

StakedIR attempts to prevent ERC-4626 "inflation attacks" by performing an initialization-time `deposit(10 ether, address(this))`. However, OpenZeppelin's ERC-4626 `deposit()` does not revert when `previewDeposit()` returns `0` shares. If an attacker pre-funds the deterministic CREATE2 proxy address with enough IR before deployment/initialization, `previewDeposit(10 ether)` becomes `0`, the initializer then transfers 10 IR into the vault but mints **zero** shares, leaving the vault with a positive IR balance and **`totalSupply == 0`**.

Once in this state, typical deposits mint 0 shares (users donate IR and receive nothing), permanently bricking sIR staking.

**References:**
1. [contracts/src/core/StakedIR.sol#L161-L184]
2. [contracts/src/core/StakedIR.sol#L399-L405]
3. [contracts/script/deploy/DeployStakedIR.s.sol#L16-L152]

#### Response — Deployment atomicity prevents this

The math in the finding is valid in isolation, but the attack requires pre-funding the exact proxy address before atomic deployment — a prerequisite that doesn't exist in any realistic deployment flow.

**The real protection is deployment atomicity.** The deployment script does `deployProxy(implementation, initData)` in one transaction — the proxy is created and `initialize()` is called in the same tx. There is no block between deployment and initialization where an attacker could send IR to the address.

Even if someone pre-funded the address days in advance (knowing the CREATE2 salt), the deployer would observe a non-zero balance and could simply change the salt, or the `deposit(10 ether, ...)` producing 0 shares would be an obvious deployment failure to catch.

The attacker must:
1. Know the exact CREATE2 address before deployment
2. Transfer IR tokens to it before `initialize` is called
3. The deployer would need to have approved the proxy for 10 IR already

In practice, atomic proxy deployment eliminates the attack window entirely. StakedIR was deployed without issues because there was no pre-fund, and there couldn't have been one in the atomic deploy tx.

---

<a id="finding-infr-4"></a>
### INFR-4 — BYUSDRewardDistributor.depositUnderlying is permissionless, enabling vest-spam gas griefing that can halt APR distributions

#### Finding

`BYUSDRewardDistributor.depositUnderlying(uint256 amount, uint256 duration)` is permissionless and appends to an unbounded `vests[]` array. Both `unlockableUnderlying()` and the keeper `distribute()` path iterate over `vests[]`, so a remote unprivileged attacker can spam many tiny deposits to make `_unlock()`/`distribute()` exceed the block gas limit.

```solidity
function depositUnderlying(uint256 amount, uint256 duration) external {
    ...
    underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
    vests.push(
        Vest(uint128(amount), uint64(block.timestamp), uint64(duration))
    );
    ...
}
```

**References:**
1. [contracts/src/periphery/BYUSDRewardDistributor.sol#L436-L449]
2. [contracts/src/periphery/BYUSDRewardDistributor.sol#L457-L480]
3. [contracts/src/periphery/BYUSDRewardDistributor.sol#L486-L525]

#### Response — Already sunset; known limitation accepted

BYUSDRewardDistributor has already been sunset and was used as-is with the known vests vector. The unbounded `vests[]` array was a recognized limitation during its operational lifetime. Since this contract is no longer active in production, no remediation is required.

---

<a id="informational"></a>
## Informational

<a id="finding-infr-7"></a>
### INFR-7 — IRRewardDistributor uninitialized proxy takeover allows attacker to steal all IR incentive funds and redirect epoch distributions

#### Finding

`IRRewardDistributor` is an upgradeable contract that holds IR tokens and periodically distributes them to Infrared vaults. If the proxy is deployed without atomic initialization, any unprivileged attacker can front-run `initialize(...)`, grant themselves admin privileges, and then steal all IR held by the distributor via `recoverERC20` (after setting `totalRewardsPerEpoch = 0`), and/or manipulate weight configuration to redirect future epoch distributions.

```solidity
_grantRole(DEFAULT_ADMIN_ROLE, _gov);
_grantRole(GOVERNANCE_ROLE, _gov);
__InfraredUpgradeable_init(_infrared);
```

**References:**
1. [src/periphery/IRRewardDistributor.sol#L117-L147]
2. [src/periphery/IRRewardDistributor.sol#L202-L208]
3. [src/periphery/IRRewardDistributor.sol#L271-L286]

#### Response — Not yet deployed; atomic deployment script pending

IRRewardDistributor has not been deployed yet, nor has an atomic deployment script been made for it. When deployment occurs, it will use an atomic deploy+initialize pattern (proxy constructor with init calldata) to eliminate the front-run window entirely. This finding will be addressed as part of the deployment preparation.

---

<a id="finding-infr-5"></a>
### INFR-5 — Emergency pause is ineffective: InfraredBERAV2_1 mint/burn/compound remain callable while paused

#### Finding

InfraredBERAV2_1 inherits OpenZeppelin pausing via `Upgradeable` (UUPS + `PausableUpgradeable`) and exposes `pause()`/`unpause()`. However, iBERA's core entrypoints (`mint`, `burn`, `compound`, and the receivor-triggered `sweep`) are not protected by `whenNotPaused`. Even after governance pauses the protocol, any unprivileged account can continue minting, compounding, and burning.

Other system components (e.g., `InfraredBERAWithdrawor.queue/process/execute`) are explicitly `whenNotPaused`, reinforcing that pause is intended to be meaningful for the iBERA stack.

```solidity
function mint(address receiver) public payable returns (uint256 shares) {
    compound();
    // ... no whenNotPaused
}

function burn(address receiver, uint256 shares) external returns (uint256 nonce, uint256 amount) {
    // ... no whenNotPaused
}

function compound() public {
    // ... no whenNotPaused
}
```

**References:**
1. [contracts/src/utils/Upgradeable.sol#L78-L90]
2. [contracts/src/staking/InfraredBERAV2_1.sol#L214-L448]

#### Response — Intentional by design

The omission of `whenNotPaused` on `mint`/`burn`/`compound` in InfraredBERAV2_1 is intentional by design. The pause mechanism in the iBERA stack is scoped to the queue/process/execute withdrawal operations in the withdrawor, not to the core mint/burn/compound entrypoints.

---

<a id="finding-infr-3"></a>
### INFR-3 — StakedIR uses a non-ERC-7201 storage namespace slot (wrong derivation), risking storage corruption on upgrade

#### Finding

`StakedIR` claims to store its state in an ERC-7201 namespaced storage struct, but the hardcoded `STAKED_IR_STORAGE_LOCATION` does **not** match the ERC-7201 derivation formula. The contract uses a single-keccak derivation instead of the double-keccak required by ERC-7201.

```solidity
/// @dev keccak256(abi.encode(uint256(keccak256(bytes("infrared.stakedIRStorage"))) - 1)) & ~bytes32(uint256(0xff));
bytes32 private constant STAKED_IR_STORAGE_LOCATION =
    0xe37d8c878a50f0326695af34a6b5c1ac8f3bc817d7b9727cc43175799b685e00;
```

Correct ERC-7201 derivation:
```bash
cast index-erc7201 "infrared.stakedIRStorage"
# 0x3ecf630963480e1990867e20cb734e48d90856cf64a353809b194c02837d6700
```

Confirmed on mainnet that production state is at the non-standard slot (`0xe37d...5e00`) and nothing at the correct ERC-7201 slot.

**References:**
1. [src/core/StakedIR.sol#L69-L87]
2. [tests/unit/core/StakedIRSecurity.t.sol#L55-L75]

#### Response — Not an issue; comments should be updated

The non-standard slot derivation is not an issue — the slot is consistent within StakedIR and production state is already written to the current `0xe37d...5e00` location. Any future upgrade must continue using this same constant to maintain storage continuity. The NatSpec/comments claiming ERC-7201 compliance should be updated to remove that claim and document the actual derivation used.

---

<a id="finding-infr-2"></a>
### INFR-2 — InfraredDeployer mainnet flow deploys iBERA stack behind uninitialized proxies, enabling attacker initialization front-run to steal all BERA deposits and fee flows

#### Finding

The repository's mainnet deployment script deploys the entire iBERA staking stack (`InfraredBERA`, `InfraredBERADepositor`, `InfraredBERAWithdraworLite`, `InfraredBERAFeeReceivor`) behind `ERC1967Proxy` instances constructed with empty initializer calldata. Each proxy is then initialized via a separate on-chain transaction. Under Foundry broadcast, proxy deployments and initializer calls are separate transactions, creating a mempool front-run window.

```solidity
proxy = address(new ERC1967Proxy(implementation, ""));
```

**References:**
1. [contracts/shell/deploy/deploy-mainnet.sh#L25-L30]
2. [contracts/script/deploy/InfraredDeployer.s.sol#L53-L71]
3. [contracts/script/deploy/InfraredDeployer.s.sol#L101-L115]
4. [contracts/script/deploy/InfraredDeployer.s.sol#L120-L125]

#### Response — Not applicable; deployed on private network

The main contracts were deployed on a private network, so the proxy initialization front-run attack was not possible. There was no public mempool where an attacker could observe and race the deployment transactions. The finding correctly identifies the vulnerability in the deployment script pattern, but the actual deployment context eliminated the attack vector.

---

<a id="finding-infr-1"></a>
### INFR-1 — CUTTING_BOARD_AUCTIONS.md deploy instructions reference non-existent ValidatorControl* contracts/scripts

#### Finding

The repository's cutting-board auction documentation describes a `ValidatorControlAuction`/`ValidatorControlNFT`/`ValidatorControlManager` system and instructs operators to deploy using `script/deploy/DeployValidatorControlAuction.s.sol`. In the current codebase, those contract/script names do not exist; the implemented system uses the `CuttingBoard*` contracts and a different deploy script (`script/deploy/DeployCuttingBoardAuction.s.sol`).

**References:**
1. [docs/CUTTING_BOARD_AUCTIONS.md#L9-L110]
2. [src/periphery/CuttingBoardDutchAuction.sol#L1-L120]
3. [script/deploy/DeployCuttingBoardAuction.s.sol#L1-L40]

#### Response — Accepted; docs should be updated

Documentation should be updated to reflect the actual `CuttingBoard*` contract names and the correct deploy script (`script/deploy/DeployCuttingBoardAuction.s.sol`), as recommended in the finding.
