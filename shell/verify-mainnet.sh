forge verify-contract 0x559d1347242F350bDc44f99C729984Bfb188092f src/core/Infrared.sol:Infrared --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,address,address,uint256,uint256)" 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f 0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8 0xdf960E8F3F19C481dDE769edEDD439ea1a63426a 0x4242424242424242424242424242424242424242 0x6969696969696969696969696969696969696969 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce 86400 10000000000000000000000) --libraries src/core/libraries/ValidatorManagerLib.sol:ValidatorManagerLib:0xe9b8b63361cbd64a9995a0d97689cfe7d890317b --libraries src/core/libraries/RewardsLib.sol:RewardsLib:0xb00a8bb981894ad2a69bd153d4487d6df46842cb --libraries src/core/libraries/VaultManagerLib.sol:VaultManagerLib:0x64b8e30b276649700d99380f6539a0f8d1bd262c --watch


forge verify-contract 0x61bd35FBEC49B144A1953f48f84ef8d2B321Da40 src/core/BribeCollector.sol:BribeCollector --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x742EbBF91A37064e89E5628D139070B73aa90247 src/core/InfraredDistributor.sol:InfraredDistributor --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x94B5d53483117FE3832c8E08d2a71Ab8AB546d81 src/staking/InfraredBERA.sol:InfraredBERA --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xef26bcFb9ce4E807465A46087e9DD73b652feF87 src/staking/InfraredBERADepositor.sol:InfraredBERADepositor --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x725a5576232220132F129f08E4A9EB7d4Be92444 src/staking/InfraredBERAWithdraworLite.sol:InfraredBERAWithdraworLite --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xAB2dADD15Af962b036d361849c024A3F70B18254 src/staking/InfraredBERAFeeReceivor.sol:InfraredBERAFeeReceivor --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b src/core/InfraredBGT.sol:InfraredBGT --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x4EF0c533D065118907f68e6017467Eb05DBb2c8C src/core/InfraredVault.sol:InfraredVault --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,uint256)" 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b 86400) --watch 




# forge verify-contract 0x559d1347242F350bDc44f99C729984Bfb188092f src/core/Infrared.sol:Infrared --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY --num-of-optimizations 200 --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,address,address,uint256,uint256)" 0x182a31A27A0D39d735b31e80534CFE1fCd92c38f 0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0 0x656b95E550C07a9ffe548bd4085c72418Ceb1dba 0x94Ad6Ac84f6C6FbA8b8CCbD71d9f4f101def52a8 0xdf960E8F3F19C481dDE769edEDD439ea1a63426a 0x4242424242424242424242424242424242424242 0x6969696969696969696969696969696969696969 0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce 86400 10000000000000000000000) --libraries src/core/libraries/ValidatorManagerLib.sol:ValidatorManagerLib:0xe9b8b63361cbd64a9995a0d97689cfe7d890317b --libraries src/core/libraries/RewardsLib.sol:RewardsLib:0xb00a8bb981894ad2a69bd153d4487d6df46842cb --libraries src/core/libraries/VaultManagerLib.sol:VaultManagerLib:0x64b8e30b276649700d99380f6539a0f8d1bd262c --watch


forge verify-contract 0x61bd35FBEC49B144A1953f48f84ef8d2B321Da40 src/core/BribeCollector.sol:BribeCollector --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x742EbBF91A37064e89E5628D139070B73aa90247 src/core/InfraredDistributor.sol:InfraredDistributor --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x94B5d53483117FE3832c8E08d2a71Ab8AB546d81 src/staking/InfraredBERA.sol:InfraredBERA --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xef26bcFb9ce4E807465A46087e9DD73b652feF87 src/staking/InfraredBERADepositor.sol:InfraredBERADepositor --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x725a5576232220132F129f08E4A9EB7d4Be92444 src/staking/InfraredBERAWithdraworLite.sol:InfraredBERAWithdraworLite --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xAB2dADD15Af962b036d361849c024A3F70B18254 src/staking/InfraredBERAFeeReceivor.sol:InfraredBERAFeeReceivor --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b src/core/InfraredBGT.sol:InfraredBGT --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --watch

forge verify-contract 0x4EF0c533D065118907f68e6017467Eb05DBb2c8C src/core/InfraredVault.sol:InfraredVault --verifier-url $VERIFIER --etherscan-api-key $BERASCAN_API_KEY  --num-of-optimizations 200  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,uint256)" 0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b 86400) --watch 
