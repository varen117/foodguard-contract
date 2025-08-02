-include .env

# Clean the repo
clean:; forge clean

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test

format :; forge fmt

anvil :; anvil --accounts 10 --balance 1000000 --base-fee 100000000

NETWORK_ARGS := --rpc-url $(ANVIL_RPC_URL) --private-key $(ANVIL_PRIVATE_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(SEPOLIA_PRIVATE_KEY) --broadcast  --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --legacy -vvvv
endif

deploy:
	@forge script script/DeployFoodguard.s.sol:DeployFoodguard $(NETWORK_ARGS)
