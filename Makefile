# Infrared Protocol - Operations Makefile
# ========================================
# This Makefile provides streamlined commands for state checks, keeper operations,
# governance tasks, testing, and deployment.
#
# Usage: make [target] [NETWORK=<network>]
# Example: make state-deposits NETWORK=mainnet
#          make keeper-harvest NETWORK=testnet

include .env

.PHONY: help
.DEFAULT_GOAL := help

# Default network (override with NETWORK=mainnet, etc.)
NETWORK ?= mainnet

# Get RPC URL from environment or use --rpc-url $(NETWORK) for forge to resolve
ifdef RPC_URL_MAINNET
    RPC_URL_mainnet := $(RPC_URL_MAINNET)
endif
ifdef RPC_URL_TESTNET
    RPC_URL_testnet := $(RPC_URL_TESTNET)
endif
ifdef RPC_URL_DEVNET
    RPC_URL_devnet := $(RPC_URL_DEVNET)
endif
ifdef RPC_URL_LOCAL
    RPC_URL_local := $(RPC_URL_LOCAL)
endif

# Select RPC based on network
ifeq ($(NETWORK),mainnet)
    RPC_URL := $(RPC_URL_mainnet)
else ifeq ($(NETWORK),testnet)
    RPC_URL := $(RPC_URL_testnet)
else ifeq ($(NETWORK),devnet)
    RPC_URL := $(RPC_URL_devnet)
else ifeq ($(NETWORK),local)
    RPC_URL := $(RPC_URL_local)
else
    RPC_URL :=
endif

# Contract addresses (override these in .env or pass as args)
INFRARED_PROXY ?= 0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126
IBERA_PROXY ?= 0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5
IBGT_PROXY ?= 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
BRIBE_COLLECTOR ?= 0x8d44170e120B80a7E898bFba8cb26B01ad21298C
IBERA_WITHDRAWOR ?= 0x8c0E122960dc2E97dc0059c07d6901Dce72818E1
IBERA_RATE ?= 0x776fD57Bbeb752BDeEB200310faFAe9A155C50a0
HONEY ?= 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce
WBERA ?= 0x6969696969696969696969696969696969696969
BGT ?= 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba
WIBGT ?= 0x4f3C10D2bC480638048Fa67a7D00237a33670C1B
SAFE_ADDRESS ?= 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f


# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m

help: ## Show this help message
	@echo "$(GREEN)Infrared Protocol - Operations Makefile$(NC)"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC) make [target] NETWORK=<network>"
	@echo ""
	@echo "$(YELLOW)Networks:$(NC) local, devnet, testnet, mainnet"
	@echo ""
	@echo "$(YELLOW)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sed 's/Makefile://' | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;32m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make check-all NETWORK=mainnet"
	@echo "  make keeper-harvest NETWORK=testnet"
	@echo "  make test-unit"

# ========================================
# State Check Commands
# ========================================

check-all: ## Display all protocol state information
	@echo "$(GREEN)=== Infrared Protocol State ($(NETWORK)) ===$(NC)"
	@make -s check-deposits
	@make -s check-pending
	@make -s check-confirmed
	@make -s check-bgt

check-deposits: ## Check total iBERA deposits
	@echo "$(YELLOW)Total Deposits:$(NC)"
	@cast call $(IBERA_PROXY) "deposits()(uint256)" --rpc-url $(RPC_URL)

check-pending: ## Check pending validator stakes
	@echo "$(YELLOW)Pending Stakes:$(NC)"
	@cast call $(IBERA_PROXY) "pending()(uint256)" --rpc-url $(RPC_URL)

check-confirmed: ## Check confirmed validator stakes
	@echo "$(YELLOW)Confirmed Stakes:$(NC)"
	@cast call $(IBERA_PROXY) "confirmed()(uint256)" --rpc-url $(RPC_URL)

check-bgt: ## Check BGT balance
	@echo "$(YELLOW)BGT Balance:$(NC)"
	@cast call $(INFRARED_PROXY) "getBGTBalance()(uint256)" --rpc-url $(RPC_URL)

check-ibgt-supply: ## Check iBGT total supply
	@echo "$(YELLOW)iBGT Total Supply:$(NC)"
	@cast call $(IBGT_PROXY) "totalSupply()(uint256)" --rpc-url $(RPC_URL)

check-validator: ## Check specific validator stake (usage: make check-validator PUBKEY=0x...)
	@echo "$(YELLOW)Validator Stake for $(PUBKEY):$(NC)"
	@cast call $(IBERA_PROXY) "stakes(bytes)(uint256)" $(PUBKEY) --rpc-url $(RPC_URL)

check-vault: ## Check vault info for asset (usage: make check-vault ASSET=0x...)
	@echo "$(YELLOW)Vault for $(ASSET):$(NC)"
	@cast call $(INFRARED_PROXY) "vaultRegistry(address)(address)" $(ASSET) --rpc-url $(RPC_URL)

check-rewards: ## Check user rewards (usage: make check-rewards USER=0x...)
	@echo "$(YELLOW)Rewards for $(USER):$(NC)"
	@cast call $(INFRARED_PROXY) "getAllRewardsForUser(address)((address,uint256)[])" $(USER) --rpc-url $(RPC_URL)

check-exchange-rate: ## Check iBERA/BERA exchange rate
	@echo "$(YELLOW)iBERA Exchange Rate:$(NC)"
	@echo "Deposits: $$(cast call $(IBERA_PROXY) 'deposits()(uint256)' --rpc-url $(RPC_URL))"
	@echo "Total Supply: $$(cast call $(IBERA_PROXY) 'totalSupply()(uint256)' --rpc-url $(RPC_URL))"
	@echo "iBERA rate (value of 1 iBERA (1e18 wei) in bera)": $$(cast call $(IBERA_RATE) 'getRate()(uint256)' --rpc-url $(RPC_URL))" 

check-protocol-fees: ## Check fees in iBGT, wBERA, HONEY, iBERA
	@echo "$(YELLOW)Protocol fees accumulated:$(NC)"
	@echo "iBGT: $$(cast call $(INFRARED_PROXY) "protocolFeeAmounts(address)(uint256)" $(IBGT_PROXY) --rpc-url $(RPC_URL))"
	@echo "wiBGT: $$(cast call $(INFRARED_PROXY) "protocolFeeAmounts(address)(uint256)" $(WIBGT) --rpc-url $(RPC_URL))"
	@echo "iBERA: $$(cast call $(INFRARED_PROXY) "protocolFeeAmounts(address)(uint256)" $(IBERA_PROXY) --rpc-url $(RPC_URL))"
	@echo "HONEY: $$(cast call $(INFRARED_PROXY) "protocolFeeAmounts(address)(uint256)" $(HONEY) --rpc-url $(RPC_URL))"
	@echo "WBERA: $$(cast call $(INFRARED_PROXY) "protocolFeeAmounts(address)(uint256)" $(WBERA) --rpc-url $(RPC_URL))"
	@echo "burn fees iBERA: $$(cast call $(IBERA_PROXY) "balanceOf(address)(uint256)" $(IBERA_PROXY) --rpc-url $(RPC_URL))"

check-unboosted-bgt: ## Check unboosted bgt balance of infrared (useful for redeems)
	@echo "$(YELLOW)Unboosted BGT:$(NC)"
	@cast call $(BGT) "unboostedBalanceOf(address)(uint256)" $(INFRARED_PROXY) --rpc-url $(RPC_URL)

check-fee-rates:
	@echo "$(YELLOW)Fee rates:$(NC)"
	@echo "  0: HarvestOperatorFeeRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 0 --rpc-url $(RPC_URL))"
	@echo "  1: HarvestOperatorProtocolRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 1 --rpc-url $(RPC_URL))"
	@echo "  2: HarvestVaultFeeRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 2 --rpc-url $(RPC_URL))"
	@echo "  3: HarvestVaultProtocolRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 3 --rpc-url $(RPC_URL))"
	@echo "  4: HarvestBribesFeeRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 4 --rpc-url $(RPC_URL))"
	@echo "  5: HarvestBribesProtocolRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 5 --rpc-url $(RPC_URL))"
	@echo "  6: HarvestBoostFeeRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 6 --rpc-url $(RPC_URL))"
	@echo "  7: HarvestBoostProtocolRate: $$(cast call $(INFRARED_PROXY) "fees(uint256)(uint256)" 7 --rpc-url $(RPC_URL))"

check-validators:
	@echo "$(YELLOW)Infrared validators:$(NC)"
	@cast call $(INFRARED_PROXY) "infraredValidators()((bytes,address)[])" --rpc-url $(RPC_URL)

check-ibera-withdrawal-queue:
	@echo "$(YELLOW)iBERA withdrawal queue:$(NC)"
	@cast call $(IBERA_WITHDRAWOR) "getQueuedAmount()(uint256)" --rpc-url $(RPC_URL)

# ========================================
# Keeper Operations
# ========================================

keeper-harvest: ## Run all harvest operations (KEEPER ONLY)
	@echo "$(GREEN)Running harvest operations...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "harvest()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-harvest-base: ## Harvest base rewards (KEEPER ONLY)
	@echo "$(GREEN)Harvesting base rewards...$(NC)"
	@cast send $(INFRARED_PROXY) "harvestBase()" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-harvest-vault: ## Harvest vault rewards (usage: make keeper-harvest-vault ASSET=0x...) (KEEPER ONLY)
	@echo "$(GREEN)Harvesting vault rewards for $(ASSET)...$(NC)"
	@cast send $(INFRARED_PROXY) "harvestVault(address)" $(ASSET) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-harvest-bribes: ## Harvest bribes (KEEPER ONLY)
	@echo "$(GREEN)Harvesting bribes...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "harvestBribes()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-harvest-boost: ## Harvest boost rewards (KEEPER ONLY)
	@echo "$(GREEN)Harvesting boost rewards...$(NC)"
	@cast send $(INFRARED_PROXY) "harvestBoostRewards()" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-harvest-operator: ## Harvest operator rewards (KEEPER ONLY)
	@echo "$(GREEN)Harvesting operator rewards...$(NC)"
	@cast send $(INFRARED_PROXY) "harvestOperatorRewards()" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-deposit-validator: ## Deposit to validators (KEEPER ONLY)
	@echo "$(GREEN)Depositing to validators...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "depositValidator()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-activate-commissions: ## Activate queued validator commissions (KEEPER ONLY)
	@echo "$(GREEN)Activating validator commissions...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "activateValCommissions()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-queue-boost: ## Queue validator boost (usage: make keeper-queue-boost PUBKEY=0x... AMOUNT=<amount>) (KEEPER ONLY)
	@echo "$(GREEN)Queueing boost for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "queueBoosts(bytes[],uint128[])" "[$(PUBKEY)]" "[$(AMOUNT)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-activate-boost: ## Activate queued boosts (usage: make keeper-activate-boost PUBKEY=0x...) (KEEPER ONLY)
	@echo "$(GREEN)Activating boosts...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "activateBoosts()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-drop-boost: ## Drop boost (usage: make keeper-drop-boost PUBKEY=0x... AMOUNT=<amount>) (KEEPER ONLY)
	@echo "$(GREEN)Dropping boost for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "dropBoosts(bytes[],uint128[])" "[$(PUBKEY)]" "[$(AMOUNT)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-cancel-queue-boosts: ## Cancel queued boosts (usage: make keeper-cancel-queue-boosts PUBKEY=0x...) (KEEPER ONLY)
	@echo "$(YELLOW)Cancelling queued boosts for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "cancelQueueBoosts(bytes[])" "[$(PUBKEY)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-queue-drop-boost: ## Queue drop boost (usage: make keeper-queue-drop-boost PUBKEY=0x... AMOUNT=<amount>) (KEEPER ONLY)
	@echo "$(YELLOW)Queueing drop boost for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "queueDropBoosts(bytes[],uint128[])" "[$(PUBKEY)]" "[$(AMOUNT)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-cancel-drop-boosts: ## Cancel queued drop boosts (usage: make keeper-cancel-drop-boosts PUBKEY=0x...) (KEEPER ONLY)
	@echo "$(YELLOW)Cancelling queued drop boosts for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "cancelDropBoosts(bytes[])" "[$(PUBKEY)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-execute-depositor: ## Execute iBERA depositor (KEEPER ONLY)
	@echo "$(GREEN)Executing iBERA depositor...$(NC)"
	@forge script script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript \
		--sig "depositValidator()" \
		--rpc-url $(RPC_URL) \
		--broadcast

keeper-sweep-withdrawor: ## Sweep iBERA withdrawor (KEEPER ONLY)
	@echo "$(GREEN)Sweeping iBERA withdrawor...$(NC)"
	@cast send $(IBERA_WITHDRAWOR) "sweep()" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-claim-incentives: ## Claim incentives (usage: make keeper-claim-incentives TOKENS=0x...,0x...) (KEEPER ONLY)
	@echo "$(GREEN)Claiming incentives for tokens: $(TOKENS)...$(NC)"
	@cast send $(BRIBE_COLLECTOR) "claimIncentives(address[])" "[$(TOKENS)]" \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

keeper-activate-cutting-board: ## Activate queued cutting board (usage: make keeper-activate-cutting-board PUBKEY=0x...) (KEEPER ONLY)
	@echo "$(GREEN)Activating cutting board for $(PUBKEY)...$(NC)"
	@cast send $(INFRARED_PROXY) "activateQueuedCuttingBoard(bytes)" $(PUBKEY) \
		--rpc-url $(RPC_URL) \
		--private-key $(PRIVATE_KEY)

# ========================================
# Governance Operations (Multisig)
# ========================================

gov-add-validator: ## Add validator (usage: make gov-add-validator PUBKEY=0x... OPERATOR=0x...)
	@echo "$(GREEN)Adding validator $(PUBKEY) with operator $(OPERATOR)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "addValidator(address,address,address,bytes)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(OPERATOR) $(PUBKEY) \
		--rpc-url $(RPC_URL)

gov-remove-validator: ## Remove validator (usage: make gov-remove-validator PUBKEY=0x...)
	@echo "$(YELLOW)Removing validator $(PUBKEY)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "removeValidator(address,address,bytes)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(PUBKEY) \
		--rpc-url $(RPC_URL)

gov-whitelist-token: ## Whitelist reward token (usage: make gov-whitelist-token TOKEN=0x...)
	@echo "$(GREEN)Whitelisting token $(TOKEN)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "updateWhiteListedRewardTokens(address,address,address,bool)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(TOKEN) true \
		--rpc-url $(RPC_URL)

gov-add-reward: ## Add reward to vault (usage: make gov-add-reward STAKING_TOKEN=0x... REWARD_TOKEN=0x... DURATION=<seconds>)
	@echo "$(GREEN)Adding reward $(REWARD_TOKEN) to vault $(STAKING_TOKEN)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "addReward(address,address,address,address,uint256)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(STAKING_TOKEN) $(REWARD_TOKEN) $(DURATION) \
		--rpc-url $(RPC_URL)

gov-update-fee: ## Update fee (usage: make gov-update-fee FEE_TYPE=<0-7> FEE=<amount>)
	@echo "$(YELLOW)Updating fee type $(FEE_TYPE) to $(FEE)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "updateFee(address,address,uint8,uint256)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(FEE_TYPE) $(FEE) \
		--rpc-url $(RPC_URL)

gov-pause-vault: ## Pause vault staking (usage: make gov-pause-vault ASSET=0x...)
	@echo "$(RED)Pausing vault staking for $(ASSET)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "pauseVaultStaking(address,address)" \
		$(INFRARED_PROXY) $(ASSET) \
		--rpc-url $(RPC_URL)

gov-unpause-vault: ## Unpause vault staking (usage: make gov-unpause-vault ASSET=0x...)
	@echo "$(GREEN)Unpausing vault staking for $(ASSET)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "unpauseVaultStaking(address,address)" \
		$(INFRARED_PROXY) $(ASSET) \
		--rpc-url $(RPC_URL)

gov-grant-keeper: ## Grant keeper role (usage: make gov-grant-keeper KEEPER=0x...)
	@echo "$(GREEN)Granting keeper role to $(KEEPER)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "grantKeeperRole(address,address,address,address)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(IBERA_PROXY) $(KEEPER) \
		--rpc-url $(RPC_URL)

gov-revoke-keeper: ## Revoke keeper role (usage: make gov-revoke-keeper KEEPER=0x...)
	@echo "$(RED)Revoking keeper role from $(KEEPER)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "revokeKeeperRole(address,address,address,address)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(IBERA_PROXY) $(KEEPER) \
		--rpc-url $(RPC_URL)

gov-recover-erc20: ## Recover ERC20 tokens (usage: make gov-recover-erc20 TOKEN=0x... RECIPIENT=0x... AMOUNT=<amount>)
	@echo "$(YELLOW)Recovering $(AMOUNT) of $(TOKEN) to $(RECIPIENT)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "recoverERC20(address,address,address,address,uint256)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(RECIPIENT) $(TOKEN) $(AMOUNT) \
		--rpc-url $(RPC_URL)

gov-set-bribe-payout: ## Set bribe collector payout token (usage: make gov-set-bribe-payout TOKEN=0x...)
	@echo "$(GREEN)Setting bribe collector payout token to $(TOKEN)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "setPayoutToken(address,address,address)" \
		$(SAFE_ADDRESS) $(BRIBE_COLLECTOR) $(TOKEN) \
		--rpc-url $(RPC_URL)

gov-queue-commissions: ## Queue validator commissions (usage: make gov-queue-commissions PUBKEY=0x...)
	@echo "$(GREEN)Queueing validator commissions...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "queueValCommissions(address,address,bytes[])" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) "[$(PUBKEY)]" \
		--rpc-url $(RPC_URL)

gov-whitelist-tokens: ## Whitelist multiple reward tokens (usage: make gov-whitelist-tokens TOKENS="0x...,0x...")
	@echo "$(GREEN)Whitelisting tokens: $(TOKENS)...$(NC)"
	@IFS=, TOKENS_ARRAY=($(TOKENS)); \
	forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "updateMultipleWhiteListedRewardTokens(address,address,address,address[],bool)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(IBERA_PROXY) "[$(TOKENS)]" true \
		--rpc-url $(RPC_URL) \
		--ffi

gov-onboard-validator: ## Onboard new validator (requires: PUBKEY, OPERATOR, SIGNATURE)
	@echo "$(GREEN)Onboarding validator $(PUBKEY)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "onboardValidator(address,address,address,address,bytes,bytes)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(IBERA_PROXY) $(OPERATOR) $(PUBKEY) $(SIGNATURE) \
		--rpc-url $(RPC_URL) \
		--ffi

gov-migrate-vault: ## Migrate vault (usage: make gov-migrate-vault ASSET=0x... VERSION=1)
	@echo "$(YELLOW)Migrating vault for $(ASSET) to version $(VERSION)...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "migrateVault(address,address,address,uint8)" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(ASSET) $(VERSION) \
		--rpc-url $(RPC_URL) \
		--ffi

gov-claim-fees: ## Claim protocol fees for specified tokens (usage: make gov-claim-fees TOKENS="0x...,0x...")
	@echo "$(GREEN)Claiming protocol fees...$(NC)"
	@forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
		--sig "claimProtocolFees(address,address,address,address[])" \
		$(SAFE_ADDRESS) $(INFRARED_PROXY) $(SAFE_ADDRESS) "[$(TOKENS)]" \
		--rpc-url $(RPC_URL) \
		--ffi


# ========================================
# Utility & Monitoring Operations
# ========================================

util-get-total-assets: ## Get total protocol assets across all vaults
	@echo "$(YELLOW)Fetching total assets...$(NC)"
	@echo "Symbol\tContract Address\tTotal Assets"
	@echo "-----------------------------------------"
	@DEPOSITS=$$(cast call $(IBERA_PROXY) "deposits()(uint256)" --rpc-url $(RPC_URL)); \
	echo -e "iBERA\t$(IBERA_PROXY)\t$$DEPOSITS"

# ========================================
# Testing Commands
# ========================================

test: ## Run all tests
	@echo "$(GREEN)Running all tests...$(NC)"
	@forge test -vv

test-unit: ## Run unit tests only
	@echo "$(GREEN)Running unit tests...$(NC)"
	@forge test --match-path "tests/unit/**/*.sol" -vv

test-integration: ## Run integration tests (e2e)
	@echo "$(GREEN)Running integration tests...$(NC)"
	@forge test --match-path "tests/e2e/**/*.sol" -vv

test-invariant: ## Run invariant tests
	@echo "$(GREEN)Running invariant tests...$(NC)"
	@forge test --match-path "tests/invariant/**/*.sol" -vv

test-fork: ## Run fork tests (requires RPC)
	@echo "$(GREEN)Running fork tests...$(NC)"
	@forge test --match-path "tests/e2e/**/*.sol" --fork-url $(RPC_URL) -vv

test-coverage: ## Generate test coverage report
	@echo "$(GREEN)Generating coverage report...$(NC)"
	@forge coverage --report lcov --exclude-tests --no-match-coverage "(script|src/depreciated|src/beraswap)" && genhtml lcov.info --output-directory coverage && open coverage/index.html
	@echo "$(GREEN)Coverage report generated: lcov.info$(NC)"

test-gas: ## Run tests with gas reporting
	@echo "$(GREEN)Running tests with gas report...$(NC)"
	@forge test --gas-report

test-specific: ## Run specific test (usage: make test-specific TEST=testFunctionName)
	@echo "$(GREEN)Running test: $(TEST)$(NC)"
	@forge test --match-test $(TEST) -vvv

# ========================================
# Build & Deploy Commands
# ========================================

build: ## Build contracts
	@echo "$(GREEN)Building contracts...$(NC)"
	@forge build

build-production: ## Build contracts with production optimizer settings
	@echo "$(GREEN)Building contracts with production settings...$(NC)"
	@FOUNDRY_PROFILE=production forge build

clean: ## Clean build artifacts
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@forge clean

deploy-infrared: ## Deploy Infrared (use with caution, mainnet only via governance)
	@echo "$(RED)Deploying Infrared to $(NETWORK)...$(NC)"
	@forge script script/deploy/InfraredDeployer.s.sol:InfraredDeployer \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify

deploy-ibera: ## Deploy InfraredBERA (use with caution, mainnet only via governance)
	@echo "$(RED)Deploying InfraredBERA to $(NETWORK)...$(NC)"
	@forge script script/deploy/InfraredBERARateProviderDeployer.s.sol:InfraredBERARateProviderDeployer \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify

# ========================================
# Utility Commands
# ========================================

format: ## Format Solidity files
	@echo "$(GREEN)Formatting Solidity files...$(NC)"
	@forge fmt

format-check: ## Check Solidity formatting
	@echo "$(GREEN)Checking Solidity formatting...$(NC)"
	@forge fmt --check

lint: ## Run Slither static analysis
	@echo "$(GREEN)Running Forge linter...$(NC)"
	@forge lint

snapshot: ## Create gas snapshot
	@echo "$(GREEN)Creating gas snapshot...$(NC)"
	@forge snapshot

install: ## Install dependencies
	@echo "$(GREEN)Installing dependencies...$(NC)"
	@forge install

update: ## Update dependencies
	@echo "$(YELLOW)Updating dependencies...$(NC)"
	@forge update

# ========================================
# Documentation Commands
# ========================================

docs: ## Generate documentation
	@echo "$(GREEN)Generating documentation...$(NC)"
	@forge doc

docs-serve: ## Serve documentation locally
	@echo "$(GREEN)Serving documentation at http://localhost:3000$(NC)"
	@forge doc --serve

# ========================================
# Monitoring & Health Checks
# ========================================

health-check: ## Run protocol health checks
	@echo "$(GREEN)=== Protocol Health Check ($(NETWORK)) ===$(NC)"
	@make -s check-all
	@echo ""
	@echo "$(YELLOW)Exchange Rate Check:$(NC)"
	@make -s check-exchange-rate
	@echo ""
	@echo "$(GREEN)Health check complete$(NC)"

monitor-queue: ## Monitor withdrawal queue depth
	@echo "$(YELLOW)Monitoring withdrawal queue...$(NC)"
	@while true; do \
		echo "$$(date): Pending = $$(cast call $(IBERA_PROXY) 'pending()(uint256)' --rpc-url $(RPC_URL))"; \
		sleep 60; \
	done

# ========================================
# Emergency Operations
# ========================================

emergency-pause-all: ## EMERGENCY: Pause all vault staking (requires governance)
	@echo "$(RED)!!! EMERGENCY: Pausing all vaults !!!$(NC)"
	@echo "$(RED)This should only be used in critical situations$(NC)"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
			--sig "pauseMultipleVaultStaking(address,address,address[])" \
			$(SAFE_ADDRESS) $(INFRARED_PROXY) "[]" \
			--rpc-url $(RPC_URL); \
	fi

# ========================================
# Configuration
# ========================================

config-show: ## Show current configuration
	@echo "$(GREEN)=== Current Configuration ===$(NC)"
	@echo "$(YELLOW)Network:$(NC) $(NETWORK)"
	@echo "$(YELLOW)RPC URL:$(NC) $(RPC_URL)"
	@echo "$(YELLOW)Infrared Proxy:$(NC) $(INFRARED_PROXY)"
	@echo "$(YELLOW)iBERA Proxy:$(NC) $(IBERA_PROXY)"
	@echo "$(YELLOW)iBGT Proxy:$(NC) $(IBGT_PROXY)"
	@echo "$(YELLOW)Bribe Collector:$(NC) $(BRIBE_COLLECTOR)"
	@echo "$(YELLOW)Safe Address:$(NC) $(SAFE_ADDRESS)"

config-validate: ## Validate contract addresses
	@echo "$(GREEN)Validating contract addresses...$(NC)"
	@if [ -z "$(INFRARED_PROXY)" ]; then echo "$(RED)ERROR: INFRARED_PROXY not set$(NC)"; exit 1; fi
	@echo "$(GREEN)Infrared Proxy: $(INFRARED_PROXY) ✓$(NC)"
	@if [ ! -z "$(IBERA_PROXY)" ]; then echo "$(GREEN)iBERA Proxy: $(IBERA_PROXY) ✓$(NC)"; fi
	@if [ ! -z "$(IBGT_PROXY)" ]; then echo "$(GREEN)iBGT Proxy: $(IBGT_PROXY) ✓$(NC)"; fi

# ========================================
# Development Workflow
# ========================================

dev-setup: ## Setup development environment
	@echo "$(GREEN)Setting up development environment...$(NC)"
	@make install
	@cp .env.example .env
	@echo "$(GREEN)Setup complete! Edit .env with your configuration$(NC)"

dev-test: ## Run development test cycle (build + test)
	@make build
	@make test

dev-check: ## Run all checks (format + lint + test)
	@make format-check
	@make lint
	@make test

# ========================================
# Info Targets
# ========================================
info-fee-types: ## Show fee type enum values
	@echo "$(GREEN)Fee Type Enum Values:$(NC)"
	@echo "  0: HarvestOperatorFeeRate"
	@echo "  1: HarvestOperatorProtocolRate"
	@echo "  2: HarvestVaultFeeRate"
	@echo "  3: HarvestVaultProtocolRate"
	@echo "  4: HarvestBribesFeeRate"
	@echo "  5: HarvestBribesProtocolRate"
	@echo "  6: HarvestBoostFeeRate"
	@echo "  7: HarvestBoostProtocolRate"

info-roles: ## Show role hashes
	@echo "$(GREEN)Role Hashes:$(NC)"
	@echo "$(YELLOW)GOVERNANCE_ROLE:$(NC)"
	@cast call $(INFRARED_PROXY) "GOVERNANCE_ROLE()(bytes32)" --rpc-url $(RPC_URL)
	@echo "$(YELLOW)KEEPER_ROLE:$(NC)"
	@cast call $(INFRARED_PROXY) "KEEPER_ROLE()(bytes32)" --rpc-url $(RPC_URL)
	@echo "$(YELLOW)PAUSER_ROLE:$(NC)"
	@cast call $(INFRARED_PROXY) "PAUSER_ROLE()(bytes32)" --rpc-url $(RPC_URL)
	@echo "$(YELLOW)DEFAULT_ADMIN_ROLE:$(NC)"
	@cast call $(INFRARED_PROXY) "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url $(RPC_URL)

info-networks: ## Show available networks
	@echo "$(GREEN)Available Networks:$(NC)"
	@echo "  local   - Local development node"
	@echo "  devnet  - Berachain devnet"
	@echo "  testnet - Berachain testnet"
	@echo "  mainnet - Berachain mainnet"
	@echo ""
	@echo "$(YELLOW)Usage:$(NC) make <target> NETWORK=<network>"
