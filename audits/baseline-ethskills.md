# Ethskills baseline audit — Infrared contracts

**Date:** 2026-04-21
**Commit:** 70e955c
**Scope:** `src/**.sol` excluding `src/depreciated/**` (unless cross-referenced).
**Scanner report:** `ai-reports/ethskills-report.json` — 105 Solidity files; 4 applicable checklists.

This is a baseline, not a full audit. It walks each ethskills checklist
against the live (non-deprecated) contracts, records the items that
have been verified, and flags gaps that deserve deeper review. The
hack-monitor workflow should not re-flag items recorded as `PASS`
here unless the underlying code changes.

Prior external audits (Zellic, Zenith, Cantina) cover most of the
same ground — this baseline is additive, not a substitute.

## Legend

- **PASS** — checked, behaves as the checklist expects
- **FLAG** — checked, deserves follow-up (design note, not necessarily a bug)
- **N/A** — pattern does not apply to Infrared's architecture
- **DEFER** — not reviewed in this baseline (reason noted)

---

## Checklist 1 — Proxy & Upgradeable (`evm-audit-proxies.md`)

**Applies to 14 live files** (31 total with deprecated). Key contracts:
`Upgradeable.sol`, `InfraredUpgradeable.sol`, `InfraredV1_10.sol`,
`StakedIR.sol`, `InfraredBERAV2_1.sol`, `InfraredBERADepositorV2.sol`,
`InfraredBERAWithdrawor.sol`, `InfraredBERAFeeReceivor.sol`,
`CuttingBoardSyndicate.sol`, `BatchClaimerV2_2.sol`,
`InfraredDistributor.sol`, `IRAuction.sol`, `IRRewardDistributor.sol`,
`BribeCollectorV1_4.sol`.

### UUPS access control

| Item | Status | Evidence |
|---|---|---|
| `_authorizeUpgrade` enforces access control | **PASS** | `src/utils/Upgradeable.sol:95-102` — `onlyGovernor`. `src/periphery/BatchClaimerV2_2.sol:132-136` — `onlyOwner`. |
| Implementation constructors call `_disableInitializers()` | **PASS** | Confirmed in `Upgradeable.sol:66`, `InfraredUpgradeable.sol:27`, `StakedIR.sol:157`, `CuttingBoardSyndicate.sol:243`, `BatchClaimerV2_2.sol:50`. All descendants inherit `Upgradeable` which calls it. |
| No `selfdestruct` or unprotected `delegatecall` in implementations | **PASS** | `grep selfdestruct\|delegatecall src/** !depreciated` — zero matches. |
| Implementations include `proxiableUUID()` | **PASS** | Inherited from OZ `UUPSUpgradeable`. |

### Storage layout

| Item | Status | Evidence |
|---|---|---|
| ERC-7201 namespaced storage used for core contracts | **PASS** | `InfraredV1_10.sol` (VALIDATOR/VAULT/REWARDS_STORAGE_LOCATION), `StakedIR.sol:73`, `CuttingBoardSyndicate.sol:93`. |
| Storage-gap arrays in every upgradeable contract | **PASS** | All 14 live contracts have `uint256[N] private __gap` (sizes 36-49). See grep output. |
| No `immutable` declarations in upgradeable implementations | **PASS** | OZ `UUPSUpgradeable` pattern used; `immutable` only in non-upgradeable `WrappedVault` / `MerkleDistributor` / peripherals. |
| **Non-standard ERC-7201 derivation in StakedIR** | **FLAG** | `StakedIR.sol:70-74` — uses single-keccak derivation (pinned for deployed-storage compatibility). Safe but diverges from spec; documented in comment. Document in upgrade-safety checklist. |

### Initialization

| Item | Status | Evidence |
|---|---|---|
| `__Upgradeable_init()` invoked in all initializers | **PASS** | Called in `StakedIR.sol:172`, `CuttingBoardSyndicate.sol` init path, etc. |
| Re-initialization prevented via OZ `initializer` modifier | **PASS** | Inherited from `Initializable`. |
| Atomic init with deploy (scripts) | **DEFER** | Out of scope — covered by `script/deploy/` review, not contract code. |

### Metamorphic / CREATE2

| Item | Status | Evidence |
|---|---|---|
| CREATE2 `+ selfdestruct` rug vector | **N/A** | No `selfdestruct` anywhere in live code. |
| `extcodesize` as contract-check | **N/A** | No such checks in live code. |

---

## Checklist 2 — ERC4626 vaults (`evm-audit-erc4626.md`)

**Applies to 6 live files.** Key contracts: `StakedIR.sol` (OZ
`ERC4626Upgradeable`), `WrappedVault.sol` (Solmate `ERC4626`),
`WrappedRewardToken.sol` (Solmate `ERC4626`). `InfraredBERAV2_1.sol`
is ERC4626-adjacent (has `totalAssets`/`convertToShares`) but is not
strictly ERC4626 — it exposes `mint(receiver) payable` / `burn` with
its own queue semantics.

### Inflation / first-depositor

| Item | Status | Evidence |
|---|---|---|
| StakedIR inflation protection | **PASS** | `StakedIR.sol:185` — `deposit(10 ether, address(this))` at `initialize()` seeds the vault. Requires governance pre-approval. |
| WrappedVault dead-share mechanism | **PASS** | `WrappedVault.sol:28,64` — `deadShares = 1e3` minted to `address(0)` in constructor; `totalAssets()` adds `deadShares`. |
| InfraredBERAV2_1 donation-before-init guard | **PASS** | `InfraredBERAV2_1.sol:276-277` — `_deposit` reverts if `!_initialized`, preventing pre-init donation attack. |
| WrappedRewardToken inflation mitigation | **FLAG** | Solmate ERC4626 has no built-in mitigation. If deployed as a user-facing vault, first depositor should be protocol. Deployment script should seed. |

### Rounding direction (EIP-4626)

| Item | Status | Evidence |
|---|---|---|
| StakedIR rounding | **PASS** | Uses OZ `ERC4626Upgradeable` which implements correct directions (deposit/redeem → DOWN; mint/withdraw → UP). |
| WrappedVault rounding | **PASS** | Uses Solmate `ERC4626` — correct default directions. |
| WrappedRewardToken rounding | **PASS** | Solmate `ERC4626` standard rounding. |

### Share price manipulation

| Item | Status | Evidence |
|---|---|---|
| `totalAssets()` avoids `balanceOf(address(this))`-only | **PASS (mixed)** | StakedIR: `balanceOf(this) - totalReserved` (accounts for withdrawal reservations). WrappedVault: `iVault.balanceOf(this) + deadShares` (reads InfraredVault stake, stable). WrappedRewardToken: `asset.balanceOf(this)` — balance-based, **FLAG** if used as non-protocol vault. |
| InfraredBERAV2_1 uses internal accounting | **PASS** | `totalAssets()` returns `deposits` (internal counter, not `address(this).balance`). Mitigates direct-transfer inflation. |
| Profit-lock / drip correctly reflected | **N/A** | No drip/lock streaming in these vaults. |

### Edge cases

| Item | Status | Evidence |
|---|---|---|
| `totalSupply == 0 && totalAssets == 0` div-by-zero | **PASS** | InfraredBERAV2_1 explicitly handles: `shares = (d != 0 && ts != 0) ? ... : amount` (line 228). OZ `ERC4626Upgradeable` handles internally. |
| Fee-on-transfer token handling | **DEFER** | StakedIR asset (IR token) and iBERA underlying are protocol-native; no FoT tokens accepted. WrappedVault underlying is user-supplied staking token — inherits Solmate behavior (no FoT handling). Document as constraint when onboarding new reward tokens. |
| Vault pausing traps user funds | **FLAG** | StakedIR: `_requestWithdraw` is `whenNotPaused`, so a pause blocks withdrawal. By design (emergency brake), but `claimWithdraw` path should be reviewed to confirm already-queued withdrawals can still be claimed. **→ follow-up review** |

### Fees

| Item | Status | Evidence |
|---|---|---|
| Fee bounds on `updateFee` | **PASS** | `src/core/libraries/RewardsLib.sol:205` — reverts if `_fee > UNIT_DENOMINATOR` (1e6 = 100%). |
| Fee role gating | **FLAG** | `InfraredV1_10.updateFee` is `onlyKeeper`, not `onlyGovernor`. Bounded at 100% but broad for operational role. Design choice; note for future tightening. |

---

## Checklist 3 — Liquid staking (`evm-audit-defi-staking.md`)

**Applies to 6 live files.** Key contracts: `InfraredBERAV2_1.sol`,
`InfraredBERADepositorV2.sol`, `InfraredBERADepositorV2_1.sol`,
`InfraredBERAWithdrawor.sol`, `InfraredBERAFeeReceivor.sol`,
`src/core/libraries/RewardsLib.sol`.

### LSD integration risks (stETH/rETH/cbETH/sfrxETH)

**N/A across the board** — Infrared operates on Berachain native BERA
via the deposit precompile, not Ethereum LSD wrappers. The specific
stETH rebase / rETH burn-revert / cbETH-blacklist / sfrxETH-detach
issues do not apply.

### Validator & deposit risks

| Item | Status | Evidence |
|---|---|---|
| WithdrawCredentials front-running | **PASS** | `InfraredBERAV2_1.setDepositSignature` (line 195-204) — only `onlyGovernor` sets signature; pubkey is checked against `INITIAL_DEPOSIT` signature off-chain before governance adds validator. |
| Deposit loop gas exhaustion | **PASS** | Deposits are queued one at a time via `InfraredBERADepositorV2.queue`; no batch-validator loops. |
| Validator iteration gas limits | **DEFER** | `InfraredV1_10` / `Infrared.sol` iterate validators during harvest. Operator count is bounded by governance; not a user-gated vector. Cantina audit covered this. |

### Reward mechanism

| Item | Status | Evidence |
|---|---|---|
| `notifyRewardAmount(0)` dilution | **DEFER** | `MultiRewards.notifyRewardAmount` access control reviewed in prior audits; re-check if new callers added. |
| Disabled receiver token loss | **N/A** | No per-receiver disable in this flow. |

### Token / accounting

| Item | Status | Evidence |
|---|---|---|
| Derivative price oracle sandwiching | **N/A** | Exchange rate is `deposits / totalSupply`; no external oracle on the mint/burn path. BEX rate provider is read-only, used only for pool preview (line 357 fee=0 edge case). |
| ETH `.transfer()` / `.send()` avoided | **PASS** | All ETH paths use `SafeTransferLib.safeTransferETH` (`call{value}("")`). See `InfraredBERAWithdrawor.sol:341,357,458,507`, `InfraredBERADepositorV2_1.sol:27`. |
| Stake accounting vs CL balance reconciliation | **PASS** | `InfraredBERAV2_1.registerViaProofs` (line 493) uses `BeaconRootsVerify` to reconcile internal stake with CL balance via Merkle proofs. |

### Withdrawal queue

| Item | Status | Evidence |
|---|---|---|
| Burn reverts on empty pool | **PASS** | `InfraredBERAV2_1.burn` requires `withdrawalsEnabled` and checks `ts == 0` before dividing. Queue absorbs; does not revert silently. |
| Min exit fee prevents dust griefing | **PASS** | `burn` requires `shares >= burnFee` (line 250), governed by `updateBurnFee`. |

---

## Checklist 4 — General / Access control (`evm-audit-general.md`)

**Applies broadly.** Key checks:

### External calls

| Item | Status | Evidence |
|---|---|---|
| `.transfer()` / `.send()` avoided for ETH | **PASS** | See liquid-staking section. |
| `.call()` return value checked | **PASS** | `InfraredBERAWithdrawor.sol:342` — `if (!success) revert Errors.CallFailed()`. |
| Non-existent address returning success | **DEFER** | Precompile address (`WITHDRAW_PRECOMPILE`) is a chain-level constant; no dynamic address calls from live code that would benefit from `extcodesize` checks. |
| Returndata bombing | **N/A** | No untrusted `.call()` targets in live code. |

### Pause mechanism

| Item | Status | Evidence |
|---|---|---|
| `unpause` path exists | **PASS** | `Upgradeable.sol:88` — `unpause()` is `onlyGovernor`; never permanently bricked. |
| Pauser vs governor separation | **PASS** | `pause()` allows PAUSER_ROLE OR GOVERNANCE_ROLE; `unpause()` is governor-only. Fast-stop, deliberate unblock. |
| `whenNotPaused` coverage on user-facing fns | **DEFER** | Per-function review — Cantina / Zenith reports cover this. Note `CuttingBoardSyndicate` deliberately leaves `exitSlot`/`claimRefund`/`expireRound` unpaused (per code comments) — users can always exit. |

### Merkle trees

| Item | Status | Evidence |
|---|---|---|
| `MerkleDistributor` leaf binds to recipient | **PASS** | `MerkleDistributor.sol:155,265` — `keccak256(abi.encode(account, amount))`. Funds go to `account` param, not `msg.sender`; front-running only wastes gas. |
| `abi.encode` (not `abi.encodePacked`) | **PASS** | `MerkleDistributor.sol:155` uses `abi.encode` — no hash-collision risk. |
| Zero-hash as valid proof | **PASS** | OZ/Solmate `MerkleProofLib` rejects empty proofs; root cannot equal `bytes32(0)` due to initializer check (`_merkleRoot == bytes32(0)` reverts, line 79). |

### Access control

| Item | Status | Evidence |
|---|---|---|
| Three roles separated (GOVERNANCE/KEEPER/PAUSER) | **PASS** | `Upgradeable.sol:25-27`. |
| Single-signer controlling multiple roles | **DEFER** | On-chain: all three roles can be held by one multisig (governance). Off-chain policy — not contract-level. |
| Role preservation across upgrades | **PASS** | OZ `AccessControlUpgradeable` uses namespaced storage; roles survive upgrade. |

### Code structure

| Item | Status | Evidence |
|---|---|---|
| Asymmetric deposit/withdraw | **PASS** | Symmetry verified in iBERA mint/burn (`deposits` increments on mint, decrements on burn via withdrawor), StakedIR (`totalReserved` balances request/claim). |
| Unbounded loops with external calls | **DEFER** | Validator loops in `Infrared.sol` harvest path — bounded by governance whitelist. Cantina audit covered. |
| Deletion of structs with nested mappings | **N/A** | No struct-with-mapping deletes in live code paths reviewed. |

### Solidity footguns

| Item | Status | Evidence |
|---|---|---|
| `pragma 0.8.26` — known bug review | **PASS** | No entries in Solidity bug list affecting 0.8.26 that apply to this codebase. |
| PUSH0 opcode compatibility | **PASS** | Berachain supports Cancun EVM (PUSH0 available). |
| Unchecked blocks with comments | **DEFER** | Per-block review recommended when touching arithmetic; convention is documented in `GUIDELINES.md`. |
| `abi.encodePacked` hash misuse | **PASS** | Only used in `CuttingBoardSyndicate` for non-hash event encoding; hashes (MerkleDistributor) use `abi.encode`. |

---

## Summary

**PASS:** 28 items — core UUPS safety, rounding, inflation mitigations,
Merkle design, ETH transfer patterns, access control all verified.

**FLAG (4):**
1. `StakedIR` ERC-7201 storage slot uses single-keccak derivation (documented for upgrade compat — track in upgrade runbook).
2. `WrappedRewardToken` has no built-in inflation mitigation — deployment script must seed when used as user-facing vault.
3. `StakedIR._requestWithdraw` is `whenNotPaused` — review that already-queued `claimWithdraw` works during pause.
4. `InfraredV1_10.updateFee` is `onlyKeeper` (bounded at 100%) — broader than `onlyGovernor`; note for future tightening.

**N/A (8):** Items tied to Ethereum LSD wrappers (stETH/rETH/cbETH/sfrxETH), metamorphic CREATE2, and external-oracle exchange rates don't apply — Infrared uses Berachain native precompile + internal accounting.

**DEFER (9):** Items already covered by external audits (Zellic, Zenith, Cantina) or requiring per-function pass over paths not in critical scope here (harvest iteration, unchecked blocks, deploy script atomicity, `whenNotPaused` coverage matrix).

---

## How to use this baseline

- **Hack monitor:** when Claude's auto-analysis flags an exploit class,
  check this doc first. If the class is marked **PASS** or **N/A**
  here, the finding can be closed as "already reviewed in baseline"
  unless the code in that area has changed since `70e955c`.
- **Follow-up work:** the four FLAGs above are the concrete next
  review items. None are known vulnerabilities — they're design
  choices or defer points.
- **Re-running the baseline:** re-run `make ai-security-scan` and
  update this doc after:
  - Adding a new module under `src/` (new contract type)
  - Changing the upgrade pattern in `Upgradeable.sol`
  - Onboarding a non-native reward token class (fee-on-transfer, rebase)
  - A major dependency version bump (OZ, Solmate)

## Sources

- Scanner report: `ai-reports/ethskills-report.json`
- Checklists: `ethskills/evm-audit-proxies.md`, `evm-audit-erc4626.md`,
  `evm-audit-defi-staking.md`, `evm-audit-general.md`
- Prior audits: `audits/Infrared - Zellic Audit Report.pdf`,
  Zenith (x2), Cantina (0503)
