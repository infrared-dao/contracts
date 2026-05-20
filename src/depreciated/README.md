# Deprecated Contracts

Historical versions of core protocol contracts, retained for reference and upgrade safety. **Do not use these contracts in new integrations.** Current production implementations are in `src/core/` and `src/staking/`.

## Purpose

These files serve two purposes:

1. **Upgrade safety** — Solidity's UUPS upgrade pattern requires storage layout compatibility between versions. Keeping old versions in the repository makes it straightforward to diff storage layouts when preparing an upgrade (`forge inspect --storage-layout`).
2. **Historical reference** — the version history documents how contracts evolved, which is useful for audits, incident analysis, and understanding current design decisions.

## Structure

```
src/depreciated/
├── core/
│   ├── InfraredV1_2.sol     # First audited version
│   ├── InfraredV1_3.sol
│   ├── InfraredV1_4.sol
│   ├── InfraredV1_5.sol
│   ├── InfraredV1_6.sol
│   ├── InfraredV1_7.sol
│   ├── InfraredV1_8.sol
│   └── InfraredV1_9.sol     # Most recent deprecated version
├── staking/
│   ├── InfraredBERA.sol     # Original iBERA implementation
│   ├── InfraredBERAV1_1.sol
│   └── InfraredBERAV2.sol
└── interfaces/
    └── ...                  # Interface snapshots for each version
```

## Version History

### `Infrared` (Core Coordinator)

| Version | Key Changes |
|---------|-------------|
| V1_2 | Initial audited release; basic validator/vault management |
| V1_3 | Fee system improvements |
| V1_4 | Boost management updates |
| V1_5 | Cutting board integration |
| V1_6 | Bribe collection improvements |
| V1_7 | Operator reward distribution |
| V1_8 | Storage layout refactor (ERC-7201) |
| V1_9 | Final pre-current version; iBGT vault special handling |

Current production: `src/core/Infrared.sol`

### `InfraredBERA` (iBERA Liquid Staking)

| Version | Key Changes |
|---------|-------------|
| V1 | Original queue-based deposit/withdraw |
| V1_1 | EL reward compounding via `IBERAFeeReceivor` |
| V2 | Beacon chain proof verification; validator lifecycle management |

Current production: `src/staking/InfraredBERA.sol`

## Working with Deprecated Contracts

**Checking storage compatibility before an upgrade:**

```bash
# Compare storage layouts between current and previous version
forge inspect src/core/Infrared.sol:Infrared storage-layout
forge inspect src/depreciated/core/InfraredV1_9.sol:InfraredV1_9 storage-layout
```

**Finding what changed between versions:**

```bash
diff src/depreciated/core/InfraredV1_9.sol src/core/Infrared.sol
```

**Never:**
- Deploy deprecated contracts to production
- Add new features to deprecated files
- Remove deprecated files without confirming no live proxy points to them

## Related

- Upgrade scripts: `script/upgrades/`
- Storage layout verification: `forge inspect --storage-layout`
- Upgrade guidance: `OPERATIONS.md`
