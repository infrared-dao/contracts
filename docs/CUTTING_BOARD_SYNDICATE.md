# Cutting Board Syndicate

The **CuttingBoardSyndicate** enables multiple partners to collectively win a cutting board Dutch auction. Partners bid on weight slices (basis points) of a validator's 10 000 bps board; the syndicate coordinates payment, allocation, and on-chain proposal submission on their behalf.

## Overview

A single validator cutting board auction is expensive. The syndicate lets multiple projects share the cost: each partner bids for a portion of the board (e.g. 3 000 bps), and the syndicate assembles eligible bids into a single winning claim.

External parties can still bid directly on the underlying Dutch auction — the syndicate is opt-in, not exclusive.

## Pricing Model

Partners specify a **per-basis-point price** (`maxPricePerBps`) when registering:

| Term | Meaning |
|------|---------|
| `maxPricePerBps` | Maximum price the partner will pay **per bps** |
| `weight` | Number of basis points requested (e.g. 5 000 = 50 %) |
| `deposit` | `maxPricePerBps × weight` — collected upfront |
| Whole-board price | What the Dutch auction charges (`getCurrentPrice()`) |
| Per-bps cost | `currentPrice / 10 000` at trigger time |

**Eligibility**: a partner is eligible when `maxPricePerBps × 10 000 ≥ currentPrice`.

**Minimum**: `maxPricePerBps` must be ≥ `minimumPricePerBps()` (= `dutchAuction.minimumPrice() / 10 000`).

**Cost at trigger**: each partner pays `floor(currentPrice × allocatedWeight / 10 000)`. Any excess deposit is credited as a pending refund.

## Round Lifecycle

```
(new auctionId)
     │
Idle ──openRound()──► Open ──triggerClaim()──► Active (terminal)
                        │   (conditions met)     NFT held until allocation expires
                  expireRound()
                 (auction lapsed)
                        │
                      Expired (terminal; all deposits refunded)
```

### Idle → Open (`openRound`)
Permissionless. Links a syndicate round to a specific `auctionId` (and therefore a specific validator). The auction must be active.

### Open state
Partners can:
- **`registerSlot`** — bid for bps with a vault, weight, and max per-bps price.
- **`updateSlotVault`** — change their vault choice.
- **`increaseMaxPrice`** — raise their per-bps ceiling (tops up deposit).

### Open → Active (`triggerClaim`)
Permissionless. Runs the fill algorithm, pays the auction, and mints the control NFT to the syndicate. Conditions:
1. At least one partner is eligible.
2. Total entries (partners + buffer) ≤ BeraChef's `maxNumWeightsPerRewardAllocation`.
3. Buffer vault's share ≤ BeraChef's `maxWeightPerVault`.
4. `bufferDeposit` covers the buffer vault's cost + rounding dust.

### Open → Expired (`expireRound`)
If the auction window closes without a claim (or an external party claims first), any address can call `expireRound`. All partner deposits are credited to `pendingRefunds`.

### Active → Complete (`completeRound`)
Once the control NFT expires, any address can call `completeRound` to move the round into its terminal state. This prevents stale Active rounds from persisting after the control period ends.

### Active state
- **`updateSlotVault` (3-param)** — SlotNFT holders can redirect their vault; automatically submits an updated cutting board proposal to `CuttingBoardManager`.
- **`claimRefund` / `claimAllRefunds`** — withdraw excess deposits.

## Fill Algorithm

1. **Filter**: only partners with `maxPricePerBps × 10 000 ≥ price` are eligible.
2. **Sort**: eligible partners ordered by bid value (`weight × maxPricePerBps`) descending. Ties break by registration order (insertion sort is stable).
3. **Greedy fill**: allocate up to 10 000 bps. The last included partner may receive a partial fill.
4. **Buffer**: any remaining bps go to the protocol's buffer vault.
5. **Cost**: `bufferRequired = price − Σ floor(price × alloc_i / 10 000)`. This covers the buffer's bps cost plus rounding dust (≤ `count − 1` wei).

## Buffer Vault

A protocol-owned fallback vault that absorbs small remainders when partners nearly but not exactly fill the board. It bridges gaps of roughly 5–10 % of the board.

- `depositBuffer(amount)` — permissionless funding.
- `setBufferVault(vault)` / `withdrawBuffer(to, amount)` — governance-only.
- `bufferDeposit` rolls over between rounds and is never refunded on expiry.
- Even when the buffer vault receives zero bps, `bufferDeposit` must cover rounding dust.

## Slot NFTs

When `triggerClaim` succeeds, a **CuttingBoardSlotNFT** is minted for each included partner. The SlotNFT:

- Records allocated weight, requested weight, clearing price, vault, and expiry.
- Is transferable — secondary market holders can redirect the vault via `updateSlotVault`.
- Expires when the control NFT expires (end of `allocationDuration`).

SlotNFT minting is mandatory — `triggerClaim` reverts if `slotNFT` is not configured.

## Access Control

| Role | Functions |
|------|-----------|
| `GOVERNANCE_ROLE` | `setBufferVault`, `withdrawBuffer`, `setMinSlotWeight`, `setSlotNFT`, `recoverERC20`, `unpause` |
| `PAUSER_ROLE` | `pause` |
| Permissionless | `openRound`, `registerSlot`, `updateSlotVault`, `increaseMaxPrice`, `triggerClaim`, `expireRound`, `completeRound`, `depositBuffer`, `claimRefund`, `claimAllRefunds` |

**Not gated by `whenNotPaused`**: `expireRound`, `completeRound`, `claimRefund`, `claimAllRefunds` — partners can always recover their funds and rounds can always be cleaned up.

## Token Recovery

`recoverERC20(token, to, amount)` allows governance to recover accidentally sent ERC-20 tokens. It reverts if `token` is the payment token (preventing drainage of user deposits and buffer funds).

## Key Views

| Function | Returns |
|----------|---------|
| `minimumPricePerBps()` | Floor per-bps price (`dutchAuction.minimumPrice() / 10 000`) |
| `canTrigger(auctionId)` | Whether `triggerClaim` would succeed now (uses same fill + validation as `triggerClaim`) |
| `previewFillAt(auctionId, price)` | Fill outcome at a hypothetical price |
| `getPendingRefund(user)` / `getPendingRefunds()` | Refund balances |
