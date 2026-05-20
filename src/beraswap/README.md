# BeraSwap Integration

Rate provider contracts that expose Infrared liquid staking token prices to BeraSwap (Berachain's native DEX, based on Balancer v2).

## Overview

BeraSwap pools containing iBERA require an on-chain price source to correctly compute swap rates. Rate providers implement the `IRateProvider` interface and are registered with the pool at deployment time.

## Contracts

### `IRateProvider`

Minimal interface that BeraSwap pools use for price discovery:

```solidity
interface IRateProvider {
    function getRate() external view returns (uint256);
}
```

Returns the price of the wrapped asset relative to its underlying, scaled to 18 decimals (i.e., `1e18` = 1:1 parity).

---

### `InfraredBERARateProvider`

Rate provider for iBERA/BERA pools.

```solidity
function getRate() external view returns (uint256)
```

Returns the current iBERA → BERA exchange rate by calling `ibera.previewBurn(1 ether)`. This reflects the accumulated BERA in the staking system (including compounded EL rewards) divided by the total iBERA supply.

As validators accumulate execution layer rewards (priority fees, MEV) and they are compounded back into the pool via `IBERAFeeReceivor`, this rate increases over time — meaning iBERA appreciates against BERA.

**Constructor parameter:** `IInfraredBERAV2 ibera` — the iBERA staking contract address.

## Usage

When creating a BeraSwap iBERA/BERA pool, pass the `InfraredBERARateProvider` address as the rate provider for the iBERA token. The pool uses `getRate()` to determine the invariant during swaps, ensuring prices stay in sync with the actual staking exchange rate.

## Related

- `InfraredBERA.sol` (`src/staking/`) — the staking contract whose exchange rate is reported here
- `IBERAFeeReceivor.sol` (`src/staking/`) — compounds EL rewards, causing rate growth over time
