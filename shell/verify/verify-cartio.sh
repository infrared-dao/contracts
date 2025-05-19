

forge verify-contract 0x7D6e08fe0d56A7e8f9762E9e65daaC491A0B475b src/core/InfraredBGT.sol:InfraredBGT --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0xAce9De5AF92Eb82A97A5973B00efF85024bDCB39 src/core/Infrared.sol:Infrared --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" 0x7D6e08fe0d56A7e8f9762E9e65daaC491A0B475b 0xE2257F3C674a7CBBFFCf7C01925D5bcB85ea0367 0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1 0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1 0xd137593CDB341CcC78426c54Fb98435C60Da193c) --libraries src/core/libraries/ValidatorManagerLib.sol:ValidatorManagerLib:0xb0ee334ae9011f64fb7a8ff57c66e16a443d06b7 --libraries src/core/libraries/RewardsLib.sol:RewardsLib:0xaf7a404442155371e345d87bcffb5f5d7c09b1cd --libraries src/core/libraries/VaultManagerLib.sol:VaultManagerLib:0x3e0bbdcac5c9ce092caa1f41762ed2e536f1be9d

forge verify-contract 0x4094fac92194e0ea37b505c32f1a52162cfd9c19 src/core/BribeCollector.sol:BribeCollector --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x976616cdf07c550e5695ea384e833f27f2c66c2a src/core/InfraredDistributor.sol:InfraredDistributor --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x4bd01f25b5ad5a07d247ad403849a71a5cc4241e src/core/RED.sol:RED --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x9b323d892d7ed5cc49929caf5fa83685e8baf50d src/voting/Voter.sol:Voter --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract  --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926 0x4bD01F25b5AD5a07d247Ad403849a71a5Cc4241e 0x4c648495586F5861FE954BcDaCccb45d6Af5435A 0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219) --watch --libraries src/voting/libraries/BalanceLogicLibrary.sol:BalanceLogicLibrary:0x048ceb55129a0f03451b9c9326f7ed332c49d22b --libraries src/voting/libraries/DelegationLogicLibrary.sol:DelegationLogicLibrary:0x90f16b6fc8574e024e263dd6ba1113adfab1cffe 0xb239d2f5157f0cb9f6f41e76bee89f266d4fb52c src/voting/VotingEscrow.sol:VotingEscrow

forge verify-contract 0x61178d8eace3cc7eb3d11a5d50b439c8cf7d8353 src/staking/InfraredBERA.sol:InfraredBERA --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0xa233c39402d7d7685941a09e125f79237d924322 src/staking/InfraredBERADepositor.sol:InfraredBERADepositor --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x181bd07957684a60b97936f675d938033886f278 src/staking/InfraredBERAWithdrawor.sol:InfraredBERAWithdrawor --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x4946cb9fd9269c0e6da45b39cfceef5ec006b4ef src/staking/InfraredBERAClaimor.sol:InfraredBERAClaimor --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26

forge verify-contract 0x18ce0b9979ca073aac2f24422a4a4d7962a44e5c src/staking/InfraredBERAFeeReceivor.sol:InfraredBERAFeeReceivor --verifier-url 'https://api.routescan.io/v2/network/testnet/evm/80000/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26