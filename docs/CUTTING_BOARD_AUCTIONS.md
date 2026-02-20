# Cutting Board Auctions

Infrared runs a Dutch auction system for monetizing BGT emission allocation rights.

---

## System Overview

| System | Contract | What's auctioned | Winner receives |
|--------|----------|-----------------|-----------------|
| **Control Auction** | `ValidatorControlAuction` | Full cutting board control rights for a validator | NFT granting ability to update allocations repeatedly for a set period |

Dutch auction price mechanism: prices start high and decay linearly to a base price over the auction duration. Winners pay the current price at claim time.

**Bribe auctions** (harvesting PoL bribes from BerachainRewardsVaults) are handled separately by the [auction-bot](https://github.com/infrared-dao/auction-bot) service — not described here.

---

## Control Auction (`ValidatorControlAuction`)

### Overview

Winners receive an ERC-721 NFT granting temporary full control over a specific validator's cutting board. They can update the reward allocation multiple times during the control period. NFTs are tradeable on secondary markets.

**Revenue:** Protocol earns auction proceeds.
**Control scope:** Cutting board allocations only — protocol retains operator rewards, commissions, and BGT boost control.

### Architecture

```
┌──────────────────────────────────────────┐
│         ValidatorControlAuction          │
│  • Dutch auction mechanism               │
│  • Mints NFT on claim                    │
│  • Tracks validator availability         │
└──────────────────┬───────────────────────┘
                   │ mints
                   ▼
┌──────────────────────────────────────────┐
│          ValidatorControlNFT             │
│  • ERC-721 with expiry timestamp         │
│  • Tradeable on secondary markets        │
│  • Stores validator pubkey & auction ID  │
└──────────────────┬───────────────────────┘
                   │ validates ownership
                   ▼
┌──────────────────────────────────────────┐
│         ValidatorControlManager          │
│  • Holds KEEPER_ROLE on Infrared         │
│  • Validates NFT ownership & weights     │
│  • Rate-limits updates                   │
│  • Proxies to queueNewCuttingBoard()     │
└──────────────────────────────────────────┘
```

### Configuration Parameters

| Parameter | Recommended | Description |
|-----------|-------------|-------------|
| `AUCTION_DURATION` | 36 hours | Price decay period |
| `ALLOCATION_DURATION` | 7 days | NFT control period |
| `MAX_AUCTIONS` | 52 | ~1 year of weekly auctions |
| `STARTING_PRICE_MULTIPLIER` | 2e18 | 2× last price |
| `BASE_PRICE_DIVISOR` | 2e18 | 0.5× last price (floor) |
| `MINIMUM_PRICE` | 100e18 | Absolute price floor |
| `MIN_UPDATE_DELAY` | 100 blocks | ~8 minutes between updates |

### Deployment

```bash
# Create environment file
cat > .env.validator-auction << 'EOF'
PRIVATE_KEY=0x...
RPC_URL_TESTNET=https://...
PAYMENT_TOKEN=0x...
TREASURY_ADDRESS=0x...
OWNER_ADDRESS=0x...
KEEPER_ADDRESS=0x...
CHEF_ADDRESS=0x...
INFRARED_ADDRESS=0x...
AUCTION_DURATION=129600
ALLOCATION_DURATION=604800
MAX_AUCTIONS=52
STARTING_PRICE_MULTIPLIER=2000000000000000000
BASE_PRICE_DIVISOR=2000000000000000000
MINIMUM_PRICE=100000000000000000000
MIN_UPDATE_DELAY=100
EOF

source .env.validator-auction

forge script script/deploy/DeployValidatorControlAuction.s.sol \
    --rpc-url $RPC_URL_TESTNET --broadcast --verify
```

**Deployment order matters** (circular dependency between NFT and Auction):
1. Deploy `ValidatorControlNFT` — needs auction address (use CREATE2 or deploy auction first)
2. Deploy `ValidatorControlManager`
3. Deploy `ValidatorControlAuction` — needs NFT and Manager addresses
4. Call `ValidatorControlNFT.setManager(managerAddress)`
5. Grant `KEEPER_ROLE` to Manager on Infrared contract

**Post-deployment:**
```solidity
// On Infrared contract (governance)
infrared.grantRole(KEEPER_ROLE, managerAddress);

// Set initial price (governance)
auction.setInitialPrice(1000e18);
```

### Auction Operations (Protocol / Keeper)

**Start an auction for a specific validator:**
```solidity
auction.startCuttingBoardAuction(validatorPubkey);
```
Requirements: validator not in active auction or control period; previous auction must be claimed.

**Monitor:**
```solidity
(uint256 auctionId, bool isActive) = auction.getActiveAuction();
uint256 price = auction.getCurrentPrice(auctionId);
bool available = auction.isValidatorAvailable(validatorPubkey);
```

### Claiming (Bidder)

```solidity
// Prepare initial cutting board weights (must sum to 10000)
IBeraChef.Weight[] memory weights = new IBeraChef.Weight[](2);
weights[0] = IBeraChef.Weight({ receiver: vaultA, percentageNumerator: 7000 });
weights[1] = IBeraChef.Weight({ receiver: vaultB, percentageNumerator: 3000 });

// Approve payment
uint256 price = auction.getCurrentPrice(auctionId);
paymentToken.approve(address(auction), price);

// Claim — mints NFT
auction.claimCuttingBoardControl(auctionId, weights);
// Receives NFT with control over validatorPubkey
```

Requirements: all vaults must be whitelisted in BeraChef; weights must sum to exactly 10000.

### Updating Cutting Board (NFT Holder)

```solidity
// Create new weights
IBeraChef.Weight[] memory newWeights = new IBeraChef.Weight[](1);
newWeights[0] = IBeraChef.Weight({ receiver: vault, percentageNumerator: 10000 });

// Update (subject to rate limit)
uint64 startBlock = uint64(block.number + 100);
manager.updateCuttingBoard(tokenId, startBlock, newWeights);
```

**Check eligibility:**
```solidity
bool canUpdate = manager.canUpdateNow(tokenId);
uint256 nextBlock = manager.getLastUpdateBlock(tokenId) + manager.minUpdateDelay();
```

**Transfer NFT (transfers control):**
```solidity
nft.transferFrom(currentOwner, newOwner, tokenId);
// New owner can now update the cutting board
```

### Emergency Controls (Governance)

```solidity
manager.revokeControl(tokenId);   // Invalidate specific NFT
manager.pause();                   // Pause all updates
manager.unpause();
```

### Gas Estimates

| Operation | Gas |
|-----------|-----|
| `startCuttingBoardAuction` | ~150k |
| `claimCuttingBoardControl` | ~300k |
| `updateCuttingBoard` | ~200k |
| NFT transfer | ~50k |

---

## Complete Lifecycle Example (Control Auction)

```solidity
// 1. Keeper starts auction
auction.startCuttingBoardAuction(validatorPubkey);

// 2. Bidder waits for favorable price, then claims
auction.claimCuttingBoardControl(0, initialWeights);  // Receives NFT #1

// 3. NFT holder updates cutting board (after MIN_UPDATE_DELAY)
manager.updateCuttingBoard(1, block.number + 100, newWeights);

// 4. NFT holder sells control on secondary market
nft.transferFrom(holder1, holder2, 1);

// 5. New holder continues updating
manager.updateCuttingBoard(1, block.number + 100, differentWeights);

// 6. Allocation period expires — NFT becomes invalid
// nft.isValid(1) == false

// 7. Validator returns to infrared-strategy control
auction.startCuttingBoardAuction(validatorPubkey);  // Re-auctionable
```

---

## Security Notes

### For Protocol
- `ValidatorControlManager` must hold `KEEPER_ROLE` on Infrared
- `infrared-strategy` must skip controlled validators during active allocation periods
- Owner can pause Manager or revoke individual NFTs in emergencies
- Keeper can update price parameters (`minimumPrice`, `basePriceDivisor`, `startingPriceMultiplier`) — consider time-locks for production

### For Bidders
- NFTs expire after `ALLOCATION_DURATION` — check `nft.isValid(tokenId)` before purchase
- Initial cutting board weights are submitted on claim and take effect immediately
- Rate limit enforced: `MIN_UPDATE_DELAY` blocks between updates (~8 min at 5s block time)
- Governance can revoke NFTs in emergency — factor into pricing

---

## Testing

```bash
# Emissions auction tests
forge test --match-path tests/unit/periphery/CuttingBoardDutchAuction.t.sol

# Control auction tests
forge test --match-contract ValidatorControl
forge test --match-path tests/unit/periphery/ValidatorControlNFT.t.sol
forge test --match-path tests/unit/periphery/ValidatorControlManager.t.sol
forge test --match-path tests/unit/periphery/ValidatorControlAuction.t.sol

# Gas report
forge test --match-contract ValidatorControl --gas-report
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `SetInitialPriceFirst` | `setInitialPrice()` not called | Call `setInitialPrice()` before first auction |
| `PreviousAuctionNotClaimed` | Previous auction still open | Wait for claim or existing auction to expire |
| `ValidatorNotAvailable` | Validator in active auction or control period | Wait for period to end |
| `InvalidWeightSum` | Weights don't sum to 10000 | Check `percentageNumerator` values |
| `VaultNotWhitelisted` | Vault not in BeraChef whitelist | Verify vault address |
| `UpdateTooSoon` | Rate limit not met | Check `manager.canUpdateNow(tokenId)` |
| `NFTExpired` | Allocation period ended | Auction the validator again |
| `Unauthorized` | Wrong caller for keeper functions | Verify keeper address |

---

## Resources

- [Infrared Protocol Docs](https://docs.infrared.finance)
- [BeraChef / PoL Documentation](https://docs.berachain.com/pol)
- Contract deployment: `script/deploy/DeployCuttingBoardDutchAuction.s.sol`
- Contract deployment: `script/deploy/DeployValidatorControlAuction.s.sol`
- GitHub Issues: https://github.com/infrared-dao/infrared-contracts/issues
