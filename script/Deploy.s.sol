// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {RiferaCursorPieces} from "../contracts/RiferaCursorPieces.sol";

/// @notice Deploy RiferaCursorPieces on BNB Chain.
/// Usage:
///   AGENT_ID=0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F \
///   forge script script/Deploy.s.sol --rpc-url <BSC_RPC_URL> --broadcast --account <KEYSTORE>
/// Mint starts CLOSED — the owner must call setMintOpen(true) after deploy.
/// No private key is stored anywhere in this repo.
contract Deploy is Script {
    function run() external returns (RiferaCursorPieces pieces) {
        address agentId = vm.envAddress("AGENT_ID");
        vm.startBroadcast();
        pieces = new RiferaCursorPieces(agentId);
        vm.stopBroadcast();
    }
}
