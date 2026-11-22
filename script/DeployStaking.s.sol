// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {RiferaCursorStake} from "../contracts/RiferaCursorStake.sol";

/// @notice Deploy RiferaCursorStake on BNB Chain.
/// Usage:
///   PIECES_ADDRESS=0x... (deployed RiferaCursorPieces) \
///   forge script script/DeployStaking.s.sol --rpc-url <BSC_RPC_URL> --broadcast --account <KEYSTORE>
/// The deployer becomes the stake contract owner. The owner has NO
/// privileged functions over the pool or anyone's NFTs — pool funding is
/// manual (fundPool) and the pool can only leave via staker claims.
/// Deploying staking does NOT open mint and does NOT fund the pool.
contract DeployStaking is Script {
    function run() external returns (RiferaCursorStake stake) {
        address pieces = vm.envAddress("PIECES_ADDRESS");
        vm.startBroadcast();
        stake = new RiferaCursorStake(pieces, msg.sender);
        vm.stopBroadcast();
    }
}
