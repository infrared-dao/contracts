# EVM Audit — General Solidity/EVM Security Patterns

## Overview
Load this for **every** EVM smart contract audit. These items are non-obvious issues that apply universally across all smart contracts.

**Coverage**: External calls, force-feeding attacks, pause mechanisms, read-only reentrancy, Merkle trees, code asymmetry, multicall hazards, EVM quirks.

---

# General EVM Smart Contract Security Checklist

This checklist consolidates universal security patterns applicable to all smart contracts, excluding basic protections (reentrancy guards, overflow checks, access control).

## External Calls & Low-Level Interactions

- **Non-existent address returns success**: A `.call()` to an address without deployed code returns `(true, "")`. Verify target has code via `extcodesize > 0` before relying on success.

- **Returndata bombing grief attacks**: Untrusted addresses can return massive byte payloads, causing quadratic gas consumption. Use inline assembly to limit copied returndata size.

- **Hardcoded gas in `.call{gas: X}()`**: Fixed gas amounts break across hard forks (EIP-1884 repriced SLOAD) and differ on L2s. Avoid explicit gas caps.

- **`msg.value` reused in loops/multicalls**: Within delegatecall loops, `msg.value` remains constant each iteration, allowing the same ETH to be "spent" N times.

- **`msg.value` accessible via delegatecall**: Payable functions callable through delegatecall contexts expose value for re-reading.

- **Try/catch fails under gas exhaustion**: External calls with insufficient forwarded gas can be forced into catch paths via attacker control.

- **Hash collisions with `abi.encodePacked`**: `encodePacked("a","bc") == encodePacked("ab","c")`. Use `abi.encode()` instead for hashing multiple dynamic types.

- **Delegatecall to stateful contracts**: Called contract code executes in caller's storage context. Only delegatecall to stateless libraries.

- **ETH transfer via `.transfer()`/`.send()` fails**: Both use only 2300 gas, breaking for complex `receive()`/`fallback()` and some L2s (zkSync). Use `.call{value: x}("")`.

- **Unchecked return from `.call()`**: Silent failures occur when `success` isn't validated with `require()`.

## Force-Feeding Attacks

- **`selfdestruct` force-feeds ETH**: Bypasses `receive()`/`fallback()` and breaks balance-based invariants.

- **CREATE2 pre-funding**: ETH reaches CREATE2 addresses before deployment, causing unexpected non-zero balances.

- **Validator/miner coinbase targeting**: Validators can force-feed block rewards to any address.

- **Direct token transfers bypass accounting**: `transfer()` to contract inflates `balanceOf(address(this))` without updating internal ledgers. Track balances internally, not via introspection.

## Pause Mechanism Pitfalls

- **Pausing liquidations accumulates bad debt**: When resumed, cascading liquidations can drain the protocol.

- **Pause transactions are front-runnable**: Attacker monitors mempool and executes malicious transactions before pause takes effect.

- **`whenNotPaused` selectively applied**: Edge-case functions missing pause modifiers while similar functions have them.

- **Pause with no unpause path**: Permanent contract brick if unpause requires unmet conditions or lacks a mechanism entirely.

## Reentrancy (Non-Obvious Cases)

- **Read-only reentrancy**: View functions return stale state during callbacks. External protocols reading views during state mutations get incorrect data.

- **Cross-contract reentrancy**: Multiple contracts share state; `nonReentrant` on one doesn't protect shared storage accessed by another.

- **ERC721 safeMint/safeTransferFrom callbacks**: `onERC721Received()` creates reentrancy vectors without guards or Checks-Effects-Interactions.

- **ERC777 pre/post transfer hooks**: Both `tokensToSend()` and `tokensReceived()` are reentrancy entry points bypassing single-function locks.

- **`nonReentrant` modifier placement**: Must be **first** modifier; if placed later, preceding modifiers execute before the lock.

## Merkle Tree Pitfalls

- **Merkle proofs are front-runnable**: Once submitted, proofs are copyable. Bind claims to `msg.sender` by including it in the leaf.

- **Zero-hash as valid proof**: Poorly constructed trees treating empty nodes as `bytes32(0)` may accept this as valid.

- **Duplicate leaves enable double-claim**: Same data appearing twice allows claiming with identical proof twice.

## Code Structure Issues

- **Asymmetric deposit/withdraw**: Every state variable modified in `deposit()` must have symmetric reversal in `withdraw()`.

- **Semantic overloading**: Same return value (0, -1, max) meaning different things across contexts (not found vs. zero vs. failure).

- **Duplicated business logic**: Identical calculations in multiple places drift over time. Consolidate into shared internal functions.

- **Documentation-code mismatch**: Comments describing different behavior than implementation.

- **Deployment scripts untested**: Script bugs (wrong constructor args, missing initialization, chain misconfigs) are as critical as contract bugs.

## Array and Loop Hazards

- **Unbounded loops with external calls = DoS**: User-growable arrays iterated over with `.call()`, `.transfer()`, or token transfers can exceed block gas limit.

- **Duplicate addresses in calldata arrays**: Double-counting or double-payment when iterating user-supplied address arrays without deduplication.

- **First iteration edge case**: First loop iteration may behave differently if prior state is assumed.

## Block/Time Assumptions

- **`block.timestamp` unreliable for short intervals**: Validators manipulate timestamps by seconds. Don't use for sub-15-minute precision.

- **Block time varies across chains**: 12s (mainnet) vs. ~2s (Optimism) vs. ~0.25s (Arbitrum). Hardcoded block counts as time proxies fail multichain.

- **Arbitrum block.number reflects L1 state**: Updates in ~5-block jumps, not monotonically per transaction.

## Comparison & Logic Operators

- **Off-by-one in boundary comparisons**: `<` vs `<=` in liquidation thresholds or time windows shifts correctness by one unit.

- **Incorrect logical operators**: `&&` vs `||`, `==` vs `!=`, negation placement in complex conditionals.

## Multi-Agent Systems

- **Single person controls multiple roles**: Borrower self-liquidates for profit; buyer/seller self-trades; proposer votes. No Sybil resistance.

- **Receiver parameter targets system contracts**: User-supplied receiver could be another contract in the system, bypassing balance checks or creating circular logic.

## Solidity Compiler Issues

- **Version-specific compiler bugs**: Each release has known bugs. Cross-reference `pragma` version with Solidity changelog.

- **PUSH0 opcode incompatibility**: Solidity ≥0.8.20 emits `push0` by default, unsupported on many L2s and alt-chains.

- **Unchecked blocks require manual verification**: Overflow/underflow bypass must be manually validated, especially with user-influenced values.

- **Signed-to-unsigned conversion edge cases**: Casting negative `int` to `uint` reverts in ≥0.8.0; wraps in `unchecked`.

- **Time literal type limitations**: `1 days`, `1 hours` are `uint24` in some contexts; arithmetic with larger types may silently truncate.

## General Solidity Footguns

- **No automatic upcast in arithmetic**: `uint8 a * uint8 b` reverts if result > 255 even when assigned to `uint256`. Upcast both operands explicitly.

- **Ternary returns uint8**: `(condition ? 1 : 0)` returns `uint8`. Cast to `uint256` to avoid overflow when adding to large numbers.

- **Downcasting silently truncates**: `int8(value + 1)` truncates without reverting in ≥0.8. Use SafeCast library for type narrowing.

- **Storage pointer reassignment is no-op**: `Foo storage foo = arr[0]; foo = arr[1];` doesn't copy; the pointer reassignment affects nothing.

- **Deleting structs preserves nested mappings**: `delete myStruct` zeros fields but inner `mapping` data persists.

- **Mixed balance accounting**: Tracking via internal variable **and** `address(this).balance` creates inconsistency when ETH arrives via selfdestruct or direct sends.

- **Merkle leaf as password**: If leaf is unhashed address without `msg.sender` binding, anyone with tree knowledge creates valid proofs. Also, unhashed leaf == root passes verification.

- **ERC20 fee-on-transfer breakage**: Recording `balances[user] += amount` but receiving `amount * 99/100` understates actual balance, short-changing withdrawals.

- **Rebasing tokens break fixed balances**: Auto-balance changes cause recorded `balanceHeld[user]` to diverge from actual `balanceOf()`. Disallow or use `balanceOf(address(this))` checks.

- **ERC4626 inflation attack**: First depositor inflates share price; subsequent depositors receive 0 shares. Mitigate with virtual shares/assets or minimum first deposit.

- **Auction timing off-by-one**: Using `>` instead of `>=` in `auctionEnd` checks allows seizure one second early.

- **Dust loans bypass minLoanSize on refinancing**: `minLoanSize` checked at creation but not refinancing/splitting allows attackers to create splinter positions.

---

## Infrared Protocol Specific Checks

Given Infrared Protocol's architecture, pay special attention to:

### External Interactions
- BGT token interactions with Berachain ecosystem
- BerachainRewardsVault integrations
- Validator delegation and undelegation calls
- Oracle price feed dependencies

### Time-Sensitive Operations
- Validator boost queue timing
- Withdrawal queue mechanics
- Reward distribution schedules
- Cutting board activation periods

### Multi-Contract State
- Shared storage patterns across upgradeable contracts
- Cross-contract reentrancy between core contracts
- State synchronization between vault and main contracts

Apply this checklist systematically to all Infrared Protocol contracts as a foundation before specialized analysis.