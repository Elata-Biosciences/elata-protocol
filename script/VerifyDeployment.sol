// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/experience/ElataXP.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { LotPool } from "../src/governance/LotPool.sol";
import { RewardsDistributor } from "../src/rewards/RewardsDistributor.sol";
import { ElataGovernor } from "../src/governance/ElataGovernor.sol";

/**
 * @title Deployment Verification Script
 * @notice Verifies that all deployed contracts are working correctly
 * @dev Run this script after deployment to validate the entire protocol
 */
contract VerifyDeployment is Script {
    function run() external view {
        // Get deployed contract addresses from environment
        address eltaAddress = vm.envAddress("DEPLOYED_ELTA");
        address xpAddress = vm.envAddress("DEPLOYED_XP");
        address stakingAddress = vm.envAddress("DEPLOYED_STAKING");
        address fundingAddress = vm.envAddress("DEPLOYED_FUNDING");
        address rewardsAddress = vm.envAddress("DEPLOYED_REWARDS");
        address governorAddress = vm.envAddress("DEPLOYED_GOVERNOR");

        console2.log("=== ELATA PROTOCOL DEPLOYMENT VERIFICATION ===");

        _verifyELTA(eltaAddress);
        _verifyElataXP(xpAddress);
        _verifyVeELTA(stakingAddress, eltaAddress);
        _verifyLotPool(fundingAddress, eltaAddress, xpAddress);
        _verifyRewardsDistributor(rewardsAddress, stakingAddress);
        _verifyGovernor(governorAddress, eltaAddress);

        console2.log("=== ALL CONTRACTS VERIFIED SUCCESSFULLY ===");
        console2.log("Protocol is ready for production use!");
    }

    function _verifyELTA(address eltaAddress) internal view {
        ELTA elta = ELTA(eltaAddress);

        console2.log("\n--- ELTA Token Verification ---");
        console2.log("Address:", eltaAddress);
        console2.log("Name:", elta.name());
        console2.log("Symbol:", elta.symbol());
        console2.log("Decimals:", elta.decimals());
        console2.log("Total Supply:", elta.totalSupply());
        console2.log("Max Supply:", elta.MAX_SUPPLY());

        require(keccak256(bytes(elta.name())) == keccak256(bytes("ELTA")), "Invalid token name");
        require(keccak256(bytes(elta.symbol())) == keccak256(bytes("ELTA")), "Invalid token symbol");
        require(elta.decimals() == 18, "Invalid decimals");
        require(elta.totalSupply() > 0, "No initial supply");
        require(elta.MAX_SUPPLY() == 77_000_000 ether, "Invalid max supply");

        console2.log("[OK] ELTA Token verified");
    }

    function _verifyElataXP(address xpAddress) internal view {
        ElataXP xp = ElataXP(xpAddress);

        console2.log("\n--- ElataXP Verification ---");
        console2.log("Address:", xpAddress);
        console2.log("Name:", xp.name());
        console2.log("Symbol:", xp.symbol());
        console2.log("Decay Window:", xp.DECAY_WINDOW());
        console2.log("Min Decay Interval:", xp.MIN_DECAY_INTERVAL());

        require(keccak256(bytes(xp.name())) == keccak256(bytes("Elata XP")), "Invalid XP name");
        require(keccak256(bytes(xp.symbol())) == keccak256(bytes("ELTAXP")), "Invalid XP symbol");
        require(xp.DECAY_WINDOW() == 14 days, "Invalid decay window");
        require(xp.MIN_DECAY_INTERVAL() == 1 hours, "Invalid decay interval");

        console2.log("[OK] ElataXP verified");
    }

    function _verifyVeELTA(address stakingAddress, address eltaAddress) internal view {
        VeELTA staking = VeELTA(stakingAddress);

        console2.log("\n--- VeELTA Staking Verification ---");
        console2.log("Address:", stakingAddress);
        console2.log("Name:", staking.name());
        console2.log("Symbol:", staking.symbol());
        console2.log("ELTA Address:", address(staking.ELTA()));
        console2.log("Min Lock:", staking.MIN_LOCK());
        console2.log("Max Lock:", staking.MAX_LOCK());
        console2.log("Emergency Penalty:", staking.EMERGENCY_UNLOCK_PENALTY());

        require(address(staking.ELTA()) == eltaAddress, "Invalid ELTA reference");
        require(staking.MIN_LOCK() == 1 weeks, "Invalid min lock");
        require(staking.MAX_LOCK() == 208 weeks, "Invalid max lock");
        require(staking.EMERGENCY_UNLOCK_PENALTY() == 5000, "Invalid emergency penalty");

        console2.log("[OK] VeELTA verified");
    }

    function _verifyLotPool(address fundingAddress, address eltaAddress, address xpAddress)
        internal
        view
    {
        LotPool funding = LotPool(fundingAddress);

        console2.log("\n--- LotPool Verification ---");
        console2.log("Address:", fundingAddress);
        console2.log("ELTA Address:", address(funding.ELTA()));
        console2.log("XP Address:", address(funding.XP()));
        console2.log("Current Round ID:", funding.currentRoundId());

        require(address(funding.ELTA()) == eltaAddress, "Invalid ELTA reference");
        require(address(funding.XP()) == xpAddress, "Invalid XP reference");

        console2.log("[OK] LotPool verified");
    }

    function _verifyRewardsDistributor(address rewardsAddress, address stakingAddress)
        internal
        view
    {
        RewardsDistributor rewards = RewardsDistributor(rewardsAddress);

        console2.log("\n--- RewardsDistributor Verification ---");
        console2.log("Address:", rewardsAddress);
        console2.log("VeELTA Address:", address(rewards.veELTA()));
        console2.log("Epoch Duration:", rewards.EPOCH_DURATION());
        console2.log("Min Distribution Delay:", rewards.MIN_DISTRIBUTION_DELAY());
        console2.log("Current Epoch:", rewards.currentEpoch());

        require(address(rewards.veELTA()) == stakingAddress, "Invalid VeELTA reference");
        require(rewards.EPOCH_DURATION() == 7 days, "Invalid epoch duration");
        require(rewards.MIN_DISTRIBUTION_DELAY() == 1 days, "Invalid distribution delay");

        console2.log("[OK] RewardsDistributor verified");
    }

    function _verifyGovernor(address governorAddress, address eltaAddress) internal view {
        ElataGovernor governor = ElataGovernor(payable(governorAddress));

        console2.log("\n--- ElataGovernor Verification ---");
        console2.log("Address:", governorAddress);
        console2.log("Name:", governor.name());
        console2.log("Token Address:", address(governor.token()));
        console2.log("Voting Delay:", governor.votingDelay());
        console2.log("Voting Period:", governor.votingPeriod());
        console2.log("Proposal Threshold:", governor.proposalThreshold());

        require(address(governor.token()) == eltaAddress, "Invalid token reference");
        require(governor.votingDelay() == 1 days, "Invalid voting delay");
        require(governor.votingPeriod() == 7 days, "Invalid voting period");
        require(governor.proposalThreshold() == 77000e18, "Invalid proposal threshold");

        console2.log("[OK] ElataGovernor verified");
    }
}
