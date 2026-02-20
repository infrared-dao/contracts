# Contract Upgrade Guide

This guide covers the safe upgrade process for Infrared Protocol's upgradeable contracts. All upgradeable contracts use the **UUPS (ERC-1967)** pattern via OpenZeppelin's upgradeable library. Upgrades require `GOVERNANCE_ROLE` and are executed through the Infrared Safe multisig.

## Upgradeable Contracts

| Contract | Proxy Address | Script Directory |
|----------|--------------|-----------------|
| `Infrared` | See `DEPLOYMENTS.md` | `script/upgrades/infrared/` |
| `BribeCollector` | See `DEPLOYMENTS.md` | `script/upgrades/bribe-collector/` |
| `InfraredBERA` | See `DEPLOYMENTS.md` | `script/upgrades/staking/` |
| `InfraredBERADepositor` | See `DEPLOYMENTS.md` | `script/upgrades/staking/` |
| `InfraredBERAWithdrawor` | See `DEPLOYMENTS.md` | `script/upgrades/staking/` |

Historical implementations for storage layout reference are in `src/depreciated/`.

---

## How UUPS Upgrades Work

The proxy stores the implementation address in the ERC-1967 slot. When `upgradeToAndCall(newImpl, initData)` is called on the proxy, it:

1. Checks the caller has `GOVERNANCE_ROLE` (`_authorizeUpgrade` in `Upgradeable.sol`)
2. Replaces the implementation address in the proxy slot
3. Optionally delegatecalls `initData` on the new implementation (used to run a versioned initializer like `initializeV1_10()`)

**State is always in the proxy.** The implementation is stateless — it only holds logic. This means storage layout must remain compatible across upgrades.

### Storage Safety (ERC-7201)

Infrared contracts use ERC-7201 namespaced storage to prevent collisions. State variables are stored in structs accessed via a deterministic `keccak256`-derived slot:

```solidity
// Example from Infrared.sol
bytes32 private constant VALIDATOR_STORAGE_LOCATION =
    0x...;  // keccak256(abi.encode(uint256(keccak256("infrared.storage.validator")) - 1)) & ~bytes32(uint256(0xff))

function _validatorStorage() internal pure returns (ValidatorStorage storage $) {
    assembly { $.slot := VALIDATOR_STORAGE_LOCATION }
}
```

**Rules:**
- Never add fields in the middle of a storage struct — append only
- When adding new state variables to a struct, reduce the `__gap` array by the same number of slots
- Never change the type of an existing field
- Never remove a field (it would shift subsequent fields)

---

## Pre-Upgrade Checklist

Complete every item before executing any upgrade on mainnet.

### 1. Harvest all rewards

Upgrading mid-cycle can cause accounting discrepancies. Ensure all pending rewards are settled:

```bash
make keeper-harvest NETWORK=mainnet
make keeper-harvest-operator NETWORK=mainnet
```

For staking contract upgrades, also ensure no pending deposits or withdrawals are in flight:

```bash
make check-pending NETWORK=mainnet
make check-ibera-withdrawal-queue NETWORK=mainnet
```

### 2. Verify storage layout compatibility

Compare the storage layout of the new implementation against the current one:

```bash
# Current implementation (from depreciated/)
forge inspect src/depreciated/core/InfraredV1_9.sol:InfraredV1_9 storage-layout

# New implementation
forge inspect src/core/Infrared.sol:Infrared storage-layout
```

Confirm that:
- All existing fields appear at the same slot offsets
- New fields are appended at the end of their respective structs
- The `__gap` size is reduced by exactly the number of new slots added

### 3. Run the upgrade validation script

Each upgrade script includes a `validate()` function using OpenZeppelin's `Upgrades.validateUpgrade()`. Run it locally before broadcasting:

```bash
forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
  --sig "validate()" \
  --rpc-url $RPC_URL_TESTNET
```

This checks storage layout compatibility against the `referenceContract` set in the script options.

### 4. Full test suite passes

```bash
make test
```

Fork tests against the current mainnet state are especially important:

```bash
forge test --fork-url $RPC_URL_MAINNET --match-path tests/e2e/
```

### 5. Test on Bepolia testnet first

Execute the testnet upgrade function before mainnet. Each upgrade script has a separate `upgradeXTestnet()` or similar function that broadcasts directly (no multisig batching):

```bash
forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
  --sig "upgradeInfraredTestnet(address,address,address,address,uint256)" \
  $INFRARED_PROXY_TESTNET $IR_TOKEN $KEEPER $STAKED_IR $PAYOUT_AMOUNT \
  --rpc-url $RPC_URL_TESTNET \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Verify the upgrade on testnet:
- All state is intact (check balances, validator list, vault registry)
- New functions work as expected
- No events emitted unexpectedly

---

## Mainnet Upgrade Process

Mainnet upgrades are executed as batched Safe transactions via `BatchScript`. The upgrade script builds the transaction batch and submits it to the Safe for signing.

### Step 1 — Deploy new implementation(s)

Deploy the new implementation contract(s) to mainnet. This does **not** activate the upgrade yet.

```bash
# Example for Infrared
forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
  --sig "deploy()" \
  --rpc-url $RPC_URL_MAINNET \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Note the deployed implementation address from the output.

### Step 2 — Build and send the Safe batch

The `upgradeX(bool _send, ...)` function builds the upgrade batch. Pass `_send=false` to simulate first, then `_send=true` to submit to Safe.

```bash
# Simulate (dry run)
forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
  --sig "upgradeInfrared(bool,address,address,address,address,address,uint256)" \
  false $INFRARED_PROXY $IR_TOKEN $IBGT $KEEPER $STAKED_IR $PAYOUT_AMOUNT \
  --rpc-url $RPC_URL_MAINNET \
  --private-key $PRIVATE_KEY

# Submit to Safe
forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
  --sig "upgradeInfrared(bool,address,address,address,address,address,uint256)" \
  true $INFRARED_PROXY $IR_TOKEN $IBGT $KEEPER $STAKED_IR $PAYOUT_AMOUNT \
  --rpc-url $RPC_URL_MAINNET \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Step 3 — Collect multisig signatures

Share the pending Safe transaction with all required signers. The transaction will appear in the Safe UI at https://app.safe.global.

Signers should independently:
1. Verify the target contract address matches the proxy in `DEPLOYMENTS.md`
2. Verify the implementation address matches what was deployed in Step 1
3. Verify any `initializeVX()` calldata parameters are correct
4. Simulate the transaction in Tenderly or similar before signing

### Step 4 — Execute

Once quorum is reached, execute the batch from the Safe UI or via the final signer's execution.

---

## Post-Upgrade Verification

After execution, verify the upgrade was applied correctly:

```bash
# Confirm the implementation slot points to the new implementation
cast storage $PROXY_ADDRESS 0x360894a13ba1a3210667c828492db98dca3e2076 --rpc-url $RPC_URL_MAINNET

# Run health check
make health-check NETWORK=mainnet
make check-all NETWORK=mainnet

# Verify key state is intact
make check-exchange-rate NETWORK=mainnet
make check-validators NETWORK=mainnet
make check-protocol-fees NETWORK=mainnet
```

For staking contract upgrades, verify accounting consistency:

```bash
make check-deposits NETWORK=mainnet
make check-pending NETWORK=mainnet
make check-confirmed NETWORK=mainnet
```

Run a harvest cycle to confirm reward flow is intact:

```bash
make keeper-harvest NETWORK=mainnet
```

---

## Contract-Specific Notes

### `Infrared`

- Run `harvestBase()` and `harvestOperatorRewards()` before upgrading — reward accounting can break if validators are being managed mid-harvest
- If the upgrade introduces a new versioned initializer (e.g. `initializeV1_10()`), it **must** be called atomically with the upgrade via `upgradeToAndCall`
- If new reward tokens or vaults are being added as part of the upgrade, batch those `addReward()` / `updateWhiteListedRewardTokens()` calls into the same Safe transaction

### `BribeCollector`

- Claim all pending fees before upgrading: `make keeper-harvest-bribes NETWORK=mainnet`
- Verify keeper addresses still have `KEEPER_ROLE` after upgrade (some versions added new role grants to the batch)

### `InfraredBERA` / `InfraredBERADepositor` / `InfraredBERAWithdrawor`

- These three contracts are closely coupled — upgrades often affect all three simultaneously and must be batched together
- Ensure the deposit queue and withdrawal queue are empty (or at a safe checkpoint) before upgrading
- After upgrading, run `executeDepositProofs` / `executeWithdrawProofs` to confirm the proof verification logic still works with current beacon state
- The `WithdraworLite` variant (used on testnet) has a different interface — use the correct proxy address per network

---

## Rollback

UUPS upgrades are **not automatically reversible** — there is no built-in rollback. To revert to a previous implementation:

1. Confirm the previous implementation contract is still deployed (check `src/depreciated/` for address history)
2. Build a new Safe batch calling `upgradeToAndCall(previousImpl, "")` on the proxy
3. Execute the same governance process as a forward upgrade
4. Note: if the forward upgrade ran a versioned initializer that wrote new state, rolling back the implementation does **not** undo that state — test carefully on testnet first

---

## Adding a New Upgradeable Contract

When introducing a new upgradeable contract:

1. Inherit from `Upgradeable` (`src/utils/Upgradeable.sol`)
2. Use ERC-7201 namespaced storage — do not use top-level state variables
3. Add a `__gap` array of 40 slots at the end of each storage struct
4. Use `_disableInitializers()` in the constructor
5. Create a deployment script in `script/deploy/` and a corresponding upgrade script template in `script/upgrades/`
6. Add the proxy address to `DEPLOYMENTS.md` after deployment
7. Add the contract to the table at the top of this document
