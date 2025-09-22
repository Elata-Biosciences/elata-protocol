// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/xp/ElataXP.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { LotPool } from "../src/governance/LotPool.sol";

contract Deploy is Script {
    // EDIT THESE:
    address public ADMIN = vm.envAddress("ADMIN_MSIG"); // your Gnosis Safe
    address public INITIAL_TREAS = vm.envAddress("INITIAL_TREASURY"); // initial recipient
    uint256 public INITIAL_MINT = 10_000_000 ether; // e.g., 10M ELTA
    uint256 public MAX_SUPPLY = 77_000_000 ether; // cap (0 = uncapped)

    function run() external {
        vm.startBroadcast();

        ELTA elta = new ELTA("ELTA", "ELTA", ADMIN, INITIAL_TREAS, INITIAL_MINT, MAX_SUPPLY);

        ElataXP xp = new ElataXP(ADMIN);

        VeELTA ve = new VeELTA(elta, ADMIN);

        LotPool lot = new LotPool(elta, xp, ADMIN);

        // Note: LotPool no longer needs snapshot role as it uses block-based checkpoints

        // OPTIONAL: grant XP_MINTER_ROLE to systems that will award points
        // xp.grantRole(xp.XP_MINTER_ROLE(), SOME_REWARDER_ADDRESS);

        console2.log("ELTA:    ", address(elta));
        console2.log("ElataXP: ", address(xp));
        console2.log("VeELTA:  ", address(ve));
        console2.log("LotPool: ", address(lot));

        vm.stopBroadcast();
    }
}
