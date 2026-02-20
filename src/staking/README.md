# Staking Contracts — Infrared Protocol

The `staking` module provides liquid staking for BERA (Berachain's native gas token). Users deposit BERA and receive **iBERA** tokens, which appreciate over time as validator execution layer rewards are compounded back into the pool.

---

## Concepts

### Liquid Staking

Users deposit BERA into `InfraredBERA`, receive iBERA in return, and can later burn iBERA to reclaim BERA plus accumulated yield. The exchange rate between iBERA and BERA increases monotonically as EL rewards are compounded.

### Queue-based Operations

All consensus layer interactions are asynchronous. Deposits and withdrawals are queued on-chain and processed by the keeper once beacon chain confirmation is available.

- **Deposit queue** — `InfraredBERADepositor` accumulates BERA until a full validator deposit is ready, then executes via the Berachain deposit precompile
- **Withdrawal queue** — `InfraredBERAWithdrawor` queues EIP-7002 voluntary exits, waits for consensus layer processing (~27 hours), then releases BERA to claimants
- **Claim** — after withdrawal is processed, users claim their BERA from `InfraredBERAClaimor`

### Fee Management

Validators generate priority fees and MEV during block production. These flow to `IBERAFeeReceivor`, which splits them between the protocol treasury and the staking pool. The pool's share is compounded back via `compound()`, growing the iBERA exchange rate for all holders.

---

## Accounting Model

### Core Variables

| Variable | Description |
|----------|-------------|
| `deposits` | Total BERA the system is responsible for — includes both queued and CL-confirmed stake |
| `pending()` | BERA sitting in the deposit or withdrawal queue, not yet confirmed on the consensus layer |
| `confirmed()` | BERA confirmed active on the consensus layer: `deposits - pending()` |
| `totalSupply` | Total iBERA tokens in circulation |

### Exchange Rate

```
Exchange Rate = deposits / totalSupply
```

One iBERA is redeemable for `deposits / totalSupply` BERA. Because `deposits` grows as EL rewards are compounded in and `totalSupply` stays flat until mint/burn, the rate increases over time.

**Mint** (deposit BERA → receive iBERA):
```
shares = (amount × totalSupply) / deposits
```

**Burn** (redeem iBERA → receive BERA):
```
amount = (shares × deposits) / totalSupply
```

### `compound()` — Rate Growth Mechanism

Both `mint()` and `burn()` call `compound()` internally before calculating shares. `compound()` pulls any accumulated ETH from `IBERAFeeReceivor` and adds it to `deposits` without issuing new iBERA, permanently increasing the exchange rate. This means the rate at the time of each operation reflects the most current EL rewards.

**Example:**
```
Initial state: deposits = 1000 BERA, totalSupply = 1000 iBERA → rate = 1.0

After compounding 10 BERA of EL rewards:
  deposits = 1010, totalSupply = 1000 → rate = 1.01

User burns 100 iBERA:
  amount = (100 × 1010) / 1000 = 101 BERA returned
```

---

## Withdrawal Queue Lifecycle

Withdrawals follow a multi-step lifecycle due to the consensus layer delay (~27 hours for EIP-7002 exits):

```
User calls burn(shares)
        │
        ▼
[QUEUED] — iBERA burned, withdrawal request recorded in InfraredBERAWithdrawor
        │   User's BERA is now locked, waiting for validator exit
        │
        ▼ Keeper submits EIP-7002 voluntary exit + proof
[PROCESSING] — Validator initiating exit on the consensus layer
        │   Duration: ~27 hours
        │
        ▼ Keeper calls executeWithdrawProofs() with beacon proof
[PROCESSED] — BERA released to InfraredBERAClaimor, claimable by user
        │
        ▼ User calls claim()
[CLAIMED] — BERA transferred to user's wallet
```

**State checks:**
```bash
make check-ibera-withdrawal-queue NETWORK=mainnet  # total BERA queued
make check-pending NETWORK=mainnet                 # BERA in queues (deposit + withdrawal)
make check-confirmed NETWORK=mainnet               # BERA confirmed on CL
```

**Timeline:**
| Step | Duration |
|------|----------|
| Queue to validator exit initiation | Up to 1 hour (keeper cadence) |
| Validator exit processing (EIP-7002) | ~27 hours |
| Proof submission to claim availability | Minutes (keeper cadence) |

---

## Key Actors

| Actor | Role |
|-------|------|
| **Staker** | Deposits BERA, receives iBERA; burns iBERA to initiate withdrawal and then claims BERA |
| **Keeper** | Processes deposit/withdrawal queues, submits beacon chain proofs, executes fee sweeps |
| **Protocol Governor** | Updates fee rates, minimum amounts, and contract parameters via Safe multisig |
| **Validator** | Produces blocks; priority fees and MEV flow to `IBERAFeeReceivor` for compounding |

---

## Core Contracts

### `InfraredBERA.sol`

Primary coordinator. Mints and burns iBERA, owns the `deposits` accounting, and calls `compound()` before every share calculation.

- `mint(receiver)` — accepts BERA, compounds EL rewards, mints iBERA shares
- `burn(shares, receiver)` — burns iBERA, queues withdrawal, returns receipt
- `compound()` — pulls fees from `IBERAFeeReceivor`, adds to `deposits`, grows the exchange rate
- `deposits` / `pending()` / `confirmed()` — accounting state

### `InfraredBERADepositor.sol`

Manages the BERA → consensus layer deposit flow.

- Queues incoming BERA from `InfraredBERA.mint()`
- Keeper calls `executeDepositProofs(depositor, amount, proofsPath)` once validators are active on the CL, confirming the deposit and updating `deposits`
- Distributes deposits across multiple validators

### `InfraredBERAWithdrawor.sol`

Manages validator exits and the withdrawal queue.

- `queue(depositor, amount)` — used by keeper to rebalance stake between validators
- Keeper submits EIP-7002 exit requests and then calls `executeWithdrawProofs(withdrawor, amount, proofsPath)` once the exit is confirmed on the CL
- Routes released BERA to `InfraredBERAClaimor`

### `InfraredBERAClaimor.sol`

Holds processed withdrawal funds until users claim.

- Maintains per-user claimable balances
- `claim()` — transfers BERA to the user after their withdrawal is processed
- Supports batched claims

### `IBERAFeeReceivor.sol`

Receives validator EL rewards (priority fees, MEV) as the designated `fee_recipient` for Infrared validators.

- Accumulated ETH is split on sweep: a portion to the treasury, the rest pushed to `InfraredBERA.compound()`
- Sweep is called automatically by `compound()` on every mint/burn, and can also be triggered manually by the keeper

---

## Flow of Funds

```
DEPOSIT
  User ──BERA──▶ InfraredBERA.mint()
                      │ compound() pulls EL rewards first
                      │ shares minted to user
                      ▼
               InfraredBERADepositor
                      │ queued until deposit batch ready
                      ▼
               Berachain deposit precompile
                      │ stake confirmed on CL
                      ▼
               executeDepositProofs() → deposits accounting updated

WITHDRAWAL
  User ──iBERA──▶ InfraredBERA.burn()
                      │ iBERA burned, withdrawal queued
                      ▼
               InfraredBERAWithdrawor
                      │ EIP-7002 exit submitted (~27h)
                      ▼
               executeWithdrawProofs() → BERA released
                      ▼
               InfraredBERAClaimor ──BERA──▶ User.claim()

EL REWARDS
  Validator block rewards ──ETH──▶ IBERAFeeReceivor
                                        │ on sweep
                            ┌───────────┴───────────┐
                            ▼                       ▼
                         Treasury            InfraredBERA.compound()
                                                   │ deposits += amount
                                                   │ exchange rate increases
```

---

## Related Documentation

- [`OPERATIONS.md`](../../OPERATIONS.md) — manual keeper operations (§6.5), exchange rate formula (§7)
- [`docs/UPGRADE_GUIDE.md`](../../docs/UPGRADE_GUIDE.md) — upgrading the staking contracts
