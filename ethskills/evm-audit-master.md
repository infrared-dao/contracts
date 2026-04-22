# EVM Smart Contract Security Audit — Master Index (Complete Skill File)

This is the complete audit routing and methodology document for EVM smart contract security analysis.

## Quick Start
1. **Always load this skill first** for any audit
2. Read the contract(s) under review
3. Use the routing table to identify which specialized skills apply
4. Execute each relevant skill's checklist systematically

## 20 Core Skills Overview

| # | Skill Name | Focus Area | Item Count |
|---|---|---|---|
| 1 | **evm-audit-master** | Routing table, methodology, master index | — |
| 2 | **evm-audit-general** | Storage pointers, struct deletion, delegatecall, upgrades, token rebasing | 46+ |
| 3 | **evm-audit-precision-math** | Division-before-multiplication, rounding, decimal assumptions | 23+ |
| 4 | **evm-audit-erc20** | Fee-on-transfer, rebasing tokens, approve race conditions | 27+ |
| 5 | **evm-audit-defi-amm** | AMM slippage, CLM vulnerabilities, Uniswap hooks | 30+ |
| 6 | **evm-audit-defi-lending** | Liquidation patterns, bad debt, collateral hiding | 33+ |
| 7 | **evm-audit-defi-staking** | Liquid staking, EigenLayer, reward precision | 30+ |
| 8 | **evm-audit-erc4626** | Share conversion, inflation attacks, rounding issues | 42+ |
| 9 | **evm-audit-erc4337** | Account abstraction, paymaster attacks, session keys | 18+ |
| 10 | **evm-audit-bridges** | Cross-chain messaging, finality, message replay | 32+ |
| 11 | **evm-audit-proxies** | UUPS, Transparent, storage collision, uninitialized logic | 18+ |
| 12 | **evm-audit-signatures** | Replay attacks, ecrecover, EIP-712, malleability | 19+ |
| 13 | **evm-audit-governance** | Flash loan voting, proposal execution, quorum issues | 23+ |
| 14 | **evm-audit-oracles** | Chainlink staleness, L2 sequencer, depeg detection | 29+ |
| 15 | **evm-audit-assembly** | Memory corruption, call semantics, overflow detection | 27+ |
| 16 | **evm-audit-chain-specific** | L2 quirks (Arbitrum, OP, zkSync, Blast, BSC, Polygon) | 29+ |
| 17 | **evm-audit-flashloans** | Flash loan oracle manipulation, governance attacks | 15+ |
| 18 | **evm-audit-erc721** | onERC721Received callbacks, enumeration DoS | 20+ |
| 19 | **evm-audit-dos** | Unbounded loops, gas limits, griefing via revert | 18+ |
| 20 | **evm-audit-access-control** | Missing modifiers, 2-step ownership, role patterns | 15+ |

**Total: 500+ checklist items**

## Routing Decision Tree

| Contract Pattern | Skills to Load |
|---|---|
| **All contracts** | `evm-audit-general`, `evm-audit-precision-math` |
| ERC20 interaction (deposits, swaps, collateral) | `evm-audit-erc20` |
| AMM/DEX/liquidity protocol | `evm-audit-defi-amm` |
| Lending/borrowing/CDP system | `evm-audit-defi-lending` |
| Staking or liquid staking derivatives | `evm-audit-defi-staking` |
| ERC4626 vault implementation | `evm-audit-erc4626` |
| Smart wallet or account abstraction | `evm-audit-erc4337` |
| Cross-chain bridge integration | `evm-audit-bridges` |
| Proxy-based upgrade mechanism | `evm-audit-proxies` |
| Off-chain signatures or permits | `evm-audit-signatures` |
| DAO or governance contracts | `evm-audit-governance` |
| Price feed dependency | `evm-audit-oracles` |
| Inline assembly or Yul | `evm-audit-assembly` |
| Non-mainnet deployment | `evm-audit-chain-specific` |
| Flash loan composability | `evm-audit-flashloans` |
| NFT implementation | `evm-audit-erc721` |
| Complex state transitions | `evm-audit-dos` |
| Authorization or roles | `evm-audit-access-control` |

## Standard Audit Workflow

### Phase 1: Preparation
- Collect all contract source files
- Map inheritance and dependencies
- Identify external integrations and token flows
- Document target chain(s)

### Phase 2: Skill Selection
Load mandatory skills (`evm-audit-general`, `evm-audit-precision-math`), then select 4-6 additional skills from the routing table based on contract functionality.

### Phase 3: Parallel Analysis
Spawn one independent agent per selected skill. Each agent receives:
- Complete contract source code
- Their specialized checklist
- Standard finding format (below)
- Output destination

### Phase 4: Deduplication & Synthesis
Merge findings from all agents. Consolidate duplicate issues. Identify cross-cutting concerns (e.g., oracle + liquidation interactions).

### Phase 5: Issue Filing
For repos with GitHub access, file all Medium+ findings as issues with appropriate severity prefixes.

## Standard Issue Format

```
## [Skill-Number] Issue Title
**Severity**: Critical | High | Medium | Low | Info
**Category**: [Relevant skill name]
**Location**: functionName() or file:line reference
**Description**: Specific technical explanation with affected variables/patterns
**Proof of Concept**: Exploitation steps or failure mode demonstration
**Recommendation**: Concrete remediation with code example where applicable
```

### Severity Scale
- **Critical**: Third-party fund loss, no special conditions required
- **High**: Conditional fund loss or permanent service denial
- **Medium**: Incorrect accounting, trust violation, owner-only losses
- **Low**: Best practice gap or latent defect without direct loss vector
- **Info**: Documentation or clarity improvement

## Key Sources
- beirao.xyz audit framework
- Dacian security deep-dives (liquidation, CLM, governance, signatures, assembly, lending, slippage, precision)
- Devdacian AI auditor primers (comprehensive baseline)
- Decurity protocol-specific checklists
- weird-erc20 token edge cases repository
- Sigma Prime security research (governance, oracles, liquid restaking)
- RareSkills smart contract security curriculum
- Cyfrin oracle security guidance
- ERC4626 inflation & rounding vulnerability compendium (85+ patterns)
- ERC4337 account abstraction framework
- LayerZero V2, CCIP, Wormhole, Across bridge guides
- Arbitrum, Blast, zkSync L2 documentation

---

This master file governs all subordinate audit skill selection and execution. Load this document first, then delegate to specialized skills based on contract type.