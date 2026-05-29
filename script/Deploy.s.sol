// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EtornieAttestation} from "../src/EtornieAttestation.sol";
import {EtornieIpToken} from "../src/EtornieIpToken.sol";
import {EtornieZkVerifier} from "../src/EtornieZkVerifier.sol";

/// @notice Deploy all three Etornie contracts in a single broadcast.
/// @dev    Reads `PRIVATE_KEY` from env. Deployer becomes admin + initial operator
///         for the attestation and IP-token contracts, and admin for the
///         ZK verifier. Roles can be rotated post-deploy via DEFAULT_ADMIN_ROLE.
///
/// Usage (dry-run):
///   forge script script/Deploy.s.sol --rpc-url moca_testnet
///
/// Usage (broadcast):
///   forge script script/Deploy.s.sol --rpc-url moca_testnet --broadcast
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console2.log("=== Etornie Moca contract deploy ===");
        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("Balance: ", deployer.balance);

        vm.startBroadcast(pk);

        EtornieAttestation att = new EtornieAttestation(deployer, deployer);
        EtornieIpToken nft = new EtornieIpToken(deployer, deployer);
        EtornieZkVerifier zk = new EtornieZkVerifier(deployer);

        vm.stopBroadcast();

        console2.log("EtornieAttestation:", address(att));
        console2.log("EtornieIpToken:    ", address(nft));
        console2.log("EtornieZkVerifier: ", address(zk));
    }
}
