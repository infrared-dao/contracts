# IR Token Cross-Chain Bridge

IR token bridging between Berachain and Binance Chain (BSC) using LayerZero's OFT standard.

## Architecture

```
Berachain                              Binance Chain (BSC)
┌────────────────────┐               ┌────────────────────┐
│  IR Token (ERC20)  │               │   IROFT (OFT)      │
│         ↓          │               │        ↑           │
│  IROFTAdapter      │←─ LayerZero ─→│   (Mint / Burn)    │
│  (Lock / Unlock)   │               │                    │
└────────────────────┘               └────────────────────┘
```

Two contracts:
- **IROFTAdapter** (Berachain) — Locks/unlocks existing IR tokens
- **IROFT** (Binance) — Mints/burns wrapped IR tokens

**Monitoring:** https://layerzeroscan.com/ (mainnet) / https://testnet.layerzeroscan.com/ (testnet)

---

## Environment Setup

Copy and configure the environment template:

```bash
cp .env.oft.example .env
```

**Required variables:**

```bash
# RPC URLs
BERACHAIN_RPC=https://...
BINANCE_RPC=https://...
BERACHAIN_RPC_TESTNET=https://bepolia.rpc.berachain.com
BINANCE_RPC_TESTNET=https://bsc-testnet-rpc.publicnode.com

# Private key (use hardware wallet for production)
PRIVATE_KEY=0x...

# LayerZero Endpoints (see https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts)
LZ_ENDPOINT_BERACHAIN=0x...
LZ_ENDPOINT_BINANCE=0x...
LZ_ENDPOINT_BERACHAIN_TESTNET=0x6C7Ab2202C98C4227C5c46f1417D81144DA716Ff
LZ_ENDPOINT_BINANCE_TESTNET=0x6EDCE65403992e310A62460808c4b910D972f10f

# Endpoint IDs
BERACHAIN_EID=30362           # Mainnet
BINANCE_EID=30102             # BSC Mainnet
BERACHAIN_EID_TESTNET=40371
BINANCE_EID_TESTNET=40102

# Existing IR token on Berachain
IR_TOKEN_ADDRESS=0x...

# Owners — MUST be multisig for production
ADAPTER_OWNER=0x...
OFT_OWNER=0x...
ADAPTER_OWNER_TESTNET=0x...
OFT_OWNER_TESTNET=0x...

# DVN addresses (see LayerZero docs)
BERA_DVN_0=0x...
BERA_DVN_1=0x...    # Second DVN recommended for security
BNB_DVN_0=0x...
BNB_DVN_1=0x...

# Message libraries
BERA_SEND_LIB_ADDRESS=0x...       # SendLib302 on Berachain
BERA_RECEIVE_LIB_ADDRESS=0x...    # ReceiveLib302 on Berachain
BNB_SEND_LIB_ADDRESS=0x...        # SendLib302 on Binance
BNB_RECEIVE_LIB_ADDRESS=0x...     # ReceiveLib302 on Binance

# Post-deployment (fill in after each step)
ADAPTER_ADDRESS=0x...
OFT_ADDRESS=0x...
ADAPTER_ADDRESS_TESTNET=0x...
OFT_ADDRESS_TESTNET=0x...

# Multisig (mainnet only)
SAFE_ADDRESS=0x...        # Berachain Safe
SAFE_ADDRESS_BNB=0x...    # Binance Safe
SENDER=0x...              # Proposer for multisig TXs

# Testing
RECIPIENT=0x...
AMOUNT=1000000000000000000   # 1 token (18 decimals)
USER=0x...
```

**Verify prerequisites before deployment:**

```bash
make oft-check-adapter-setup ENV=testnet   # Berachain
make oft-check-oft-setup ENV=testnet       # Binance
```

---

## Deployment

### Step 1 — Deploy IROFTAdapter (Berachain)

```bash
# Testnet
make oft-deploy-adapter ENV=testnet

# Mainnet (multisig recommended)
make oft-deploy-adapter ENV=mainnet
```

Save the deployed address: `ADAPTER_ADDRESS_TESTNET=0x...`

### Step 2 — Deploy IROFT (Binance)

```bash
# Testnet
make oft-deploy-oft ENV=testnet

# Mainnet
make oft-deploy-oft ENV=mainnet
```

Save the deployed address: `OFT_ADDRESS_TESTNET=0x...`

### Step 3 — Configure Peers

Establish bidirectional communication between contracts.

```bash
# Testnet
make oft-configure-adapter-peer ENV=testnet    # Berachain → Binance
make oft-configure-oft-peer ENV=testnet        # Binance → Berachain

# Mainnet (multisig)
make oft-configure-adapter-peer-multisig SAFE=0x...
make oft-configure-oft-peer-multisig SAFE=0x...
```

### Step 4 — Set Enforced Options

Enforced options guarantee minimum gas for cross-chain execution. Set **200,000 gas** on both contracts:

```bash
# Testnet
make oft-set-enforced-options-all ENV=testnet

# Mainnet (multisig)
make oft-set-enforced-options-adapter-multisig SAFE=<berachain-safe>
make oft-set-enforced-options-oft-multisig SAFE=<binance-safe>
```

Verify:
```bash
cast call $ADAPTER_ADDRESS "enforcedOptions(uint32,uint16)(bytes)" $BINANCE_EID 1 --rpc-url $BERACHAIN_RPC
cast call $OFT_ADDRESS "enforcedOptions(uint32,uint16)(bytes)" $BERACHAIN_EID 1 --rpc-url $BINANCE_RPC
```

Expected: non-empty bytes value.

### Step 5 — Configure DVNs (Critical)

LayerZero uses DVNs (Decentralized Verifier Networks) to verify messages. Each direction needs a **send config** and a **receive config** — **4 transactions total**.

```
Berachain → Binance:  send config on Berachain  + receive config on Binance
Binance → Berachain:  send config on Binance    + receive config on Berachain
```

```bash
# Testnet (all 4 at once)
make oft-setup-dvns ENV=testnet

# Or individually:
make oft-set-send-config ENV=testnet               # Berachain → Binance (send)
make oft-set-receive-config ENV=testnet            # Berachain → Binance (receive)
make oft-set-send-config-binance ENV=testnet       # Binance → Berachain (send)
make oft-set-receive-config-berachain ENV=testnet  # Binance → Berachain (receive)

# Mainnet (multisig)
make oft-set-send-config-multisig SAFE=0x...
make oft-set-receive-config-multisig SAFE=0x...
make oft-set-send-config-binance-multisig SAFE=0x...
make oft-set-receive-config-berachain-multisig SAFE=0x...
```

Use at least 2 DVNs per direction for production security.

### Step 6 — Verify

```bash
make oft-verify-all ENV=testnet
```

Individual checks:
```bash
make oft-verify-adapter ENV=testnet          # Peer config
make oft-verify-oft ENV=testnet              # Peer config
make oft-verify-dvn-berachain ENV=testnet    # DVN configs on Berachain
make oft-verify-dvn-binance ENV=testnet      # DVN configs on Binance
```

Expected output: `BRIDGE STATUS: READY`

---

## Production Deployment Checklist

- [ ] Deploy contracts via multisig
- [ ] Configure peers on both chains
- [ ] Set enforced options on both contracts
- [ ] Set DVN configs for BOTH directions (4 transactions total)
- [ ] Verify all configurations with `make oft-verify-all`
- [ ] Test with small amounts first
- [ ] Monitor LayerZero Scan for all transactions
- [ ] Set up alerts for failed messages

---

## Bridging Tokens

### Quote Fee First

```bash
export RECIPIENT=0x...
export AMOUNT=1000000000000000000   # 1 IR token

make oft-quote-fee ENV=testnet
```

### Bridge Berachain → Binance

```bash
make oft-bridge-to-binance ENV=testnet   # or oft-send-from-berachain
```

Flow: Adapter locks IR on Berachain → LayerZero message → OFT mints IR on Binance.

### Bridge Binance → Berachain

```bash
make oft-bridge-to-berachain ENV=testnet   # or oft-send-from-binance
```

Flow: OFT burns IR on Binance → LayerZero message → Adapter unlocks IR on Berachain.

### Check Balance

```bash
make oft-check-balance ENV=testnet   # or oft-balance
```

---

## Monitoring & Maintenance

**Regular tasks:**
1. Monitor LayerZero Scan for stuck or failed messages
2. Verify token supply consistency across chains (total locked ≈ total minted)
3. Test periodically with small amounts
4. Update DVN addresses if LayerZero updates them

**Alerts to set up:**
- Failed LayerZero messages
- Unusual transfer patterns
- Token supply imbalance

---

## Emergency Procedures

```bash
# Pause bridge (stops all OFT transfers on Binance)
cast send $OFT_ADDRESS "pause()" --rpc-url $BINANCE_RPC --from $MULTISIG

# Unpause
cast send $OFT_ADDRESS "unpause()" --rpc-url $BINANCE_RPC --from $MULTISIG

# Check pause status
cast call $OFT_ADDRESS "paused()(bool)" --rpc-url $BINANCE_RPC
```

---

## Troubleshooting

### Transaction stuck INFLIGHT

**Symptoms:** LayerZero Scan shows INFLIGHT; executor WAITING; DVN SUCCEEDED.

**Cause:** Insufficient gas for destination execution.

**Fix:**
1. Wait 10–15 minutes (testnet can be slow)
2. Find the "Deliver" or "Manual Relay" button on LayerZero Scan
3. Click it and pay gas to manually complete delivery
4. For future: enforced options (Step 4) set 200k gas to prevent this

### Peer not set

```bash
# Re-run peer configuration
make oft-configure-adapter-peer ENV=testnet
make oft-configure-oft-peer ENV=testnet
make oft-verify-adapter ENV=testnet
make oft-verify-oft ENV=testnet
```

### DVN configuration not set

```bash
# Run all 4 DVN configs
make oft-setup-dvns ENV=testnet
make oft-verify-dvn-berachain ENV=testnet
make oft-verify-dvn-binance ENV=testnet
```

### Owner cannot perform actions

Transaction must come from the multisig owner address. Use Safe Transaction Builder to propose.

### Token transfer failed (adapter)

Ensure IR token approval for the adapter contract before sending.

---

## Makefile Command Reference

| Command | Description |
|---------|-------------|
| `make oft-help` | Show all OFT commands |
| `make oft-deploy-adapter` | Deploy IROFTAdapter on Berachain |
| `make oft-deploy-oft` | Deploy IROFT on Binance |
| `make oft-configure-adapter-peer` | Set peer on adapter |
| `make oft-configure-oft-peer` | Set peer on OFT |
| `make oft-set-enforced-options-all` | Set gas options on both chains |
| `make oft-setup-dvns` | Configure all 4 DVN configs |
| `make oft-verify-all` | Verify complete setup |
| `make oft-bridge-to-binance` | Send IR to Binance |
| `make oft-bridge-to-berachain` | Send IR to Berachain |
| `make oft-balance` | Check IR balance |
| `make oft-quote-fee` | Quote cross-chain fee |

All commands accept `ENV=testnet` or `ENV=mainnet`.
Multisig variants are suffixed with `-multisig SAFE=0x...`.

---

## Upgrade Path

If contracts need upgrades:
1. Deploy new contract versions
2. Configure new peer relationships
3. Migrate any locked tokens if necessary
4. Update `DEPLOYMENTS.md` with new addresses

## Resources

- [LayerZero V2 Docs](https://docs.layerzero.network/v2)
- [OFT Quickstart](https://docs.layerzero.network/v2/developers/evm/oft/quickstart)
- [Deployed Contracts](https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts)
- [LayerZero Scan](https://layerzeroscan.com/)
