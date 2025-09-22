// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/xp/ElataXP.sol";
import { ElataXPWithDecay } from "../src/xp/ElataXPWithDecay.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { VeELTAMultiLock } from "../src/staking/VeELTAMultiLock.sol";
import { LotPool } from "../src/governance/LotPool.sol";
import { RewardsDistributor } from "../src/rewards/RewardsDistributor.sol";
import { ElataGovernorSimple } from "../src/governance/ElataGovernorSimple.sol";
import { ElataTimelock } from "../src/governance/ElataTimelock.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DeployAdvanced
 * @notice Deployment script for the complete Elata Protocol v2.0 with all advanced features
 */
contract DeployAdvanced is Script {
    // Configuration - EDIT THESE:
    address public ADMIN_MSIG = vm.envAddress("ADMIN_MSIG");
    address public INITIAL_TREASURY = vm.envAddress("INITIAL_TREASURY");
    uint256 public INITIAL_MINT = 10_000_000 ether;
    uint256 public MAX_SUPPLY = 77_000_000 ether;

    // Governance configuration
    uint256 public constant TIMELOCK_DELAY = 48 hours;
    uint256 public constant EMERGENCY_TIMELOCK_DELAY = 6 hours;

    struct DeployedContracts {
        ELTA elta;
        ElataXP xp;
        ElataXPWithDecay xpDecay;
        VeELTA veELTA;
        VeELTAMultiLock veELTAMulti;
        LotPool lotPool;
        RewardsDistributor rewardsDistributor;
        TimelockController timelock;
        TimelockController emergencyTimelock;
        ElataGovernorSimple governor;
    }

    function run() external returns (DeployedContracts memory deployed) {
        vm.startBroadcast();

        // 1. Deploy core token
        deployed.elta = new ELTA(
            "ELTA",
            "ELTA",
            ADMIN_MSIG,
            INITIAL_TREASURY,
            INITIAL_MINT,
            MAX_SUPPLY
        );

        // 2. Deploy XP systems
        deployed.xp = new ElataXP(ADMIN_MSIG);
        deployed.xpDecay = new ElataXPWithDecay(ADMIN_MSIG);

        // 3. Deploy staking systems
        deployed.veELTA = new VeELTA(deployed.elta, ADMIN_MSIG);
        deployed.veELTAMulti = new VeELTAMultiLock(deployed.elta, ADMIN_MSIG);

        // 4. Deploy governance infrastructure
        deployed.timelock = _deployTimelock(TIMELOCK_DELAY);
        deployed.emergencyTimelock = _deployTimelock(EMERGENCY_TIMELOCK_DELAY);
        
        deployed.governor = new ElataGovernorSimple(deployed.elta);

        // 5. Deploy funding and rewards systems
        deployed.lotPool = new LotPool(deployed.elta, deployed.xpDecay, ADMIN_MSIG);
        deployed.rewardsDistributor = new RewardsDistributor(deployed.veELTA, ADMIN_MSIG);

        // 6. Configure roles and permissions
        _configureGovernance(deployed);
        _configureRewards(deployed);
        _configureLotPool(deployed);

        // 7. Log deployment addresses
        _logDeployment(deployed);

        vm.stopBroadcast();
    }

    /**
     * @dev Deploys a timelock controller with standard configuration
     */
    function _deployTimelock(uint256 delay) internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Will be set to governor after deployment

        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        return new TimelockController(delay, proposers, executors, ADMIN_MSIG);
    }

    /**
     * @dev Configures governance roles and permissions
     */
    function _configureGovernance(DeployedContracts memory deployed) internal {
        // Grant governor proposer role on timelock
        deployed.timelock.grantRole(deployed.timelock.PROPOSER_ROLE(), address(deployed.governor));
        deployed.timelock.grantRole(deployed.timelock.EXECUTOR_ROLE(), address(deployed.governor));

        // Grant emergency roles
        deployed.emergencyTimelock.grantRole(
            deployed.emergencyTimelock.PROPOSER_ROLE(),
            address(deployed.governor)
        );
        deployed.emergencyTimelock.grantRole(
            deployed.emergencyTimelock.PROPOSER_ROLE(),
            ADMIN_MSIG
        );

        // Transfer token admin role to timelock for decentralized governance
        deployed.elta.grantRole(deployed.elta.DEFAULT_ADMIN_ROLE(), address(deployed.timelock));
    }

    /**
     * @dev Configures rewards distributor
     */
    function _configureRewards(DeployedContracts memory deployed) internal {
        // Add ELTA as a reward token
        deployed.rewardsDistributor.addRewardToken(deployed.elta);

        // Grant distributor role to admin for initial setup
        deployed.rewardsDistributor.grantRole(
            deployed.rewardsDistributor.DISTRIBUTOR_ROLE(),
            ADMIN_MSIG
        );
    }

    /**
     * @dev Configures lot pool with XP decay system
     */
    function _configureLotPool(DeployedContracts memory deployed) internal {
        // Grant XP minter role to lot pool for rewards
        deployed.xpDecay.grantRole(deployed.xpDecay.XP_MINTER_ROLE(), address(deployed.lotPool));

        // Grant keeper role to admin for decay management
        deployed.xpDecay.grantRole(deployed.xpDecay.KEEPER_ROLE(), ADMIN_MSIG);
    }

    /**
     * @dev Logs all deployment addresses
     */
    function _logDeployment(DeployedContracts memory deployed) internal view {
        console2.log("=== ELATA PROTOCOL V2.0 DEPLOYMENT ===");
        console2.log("ELTA Token:           ", address(deployed.elta));
        console2.log("ElataXP (Basic):      ", address(deployed.xp));
        console2.log("ElataXP (Decay):      ", address(deployed.xpDecay));
        console2.log("VeELTA (Single):      ", address(deployed.veELTA));
        console2.log("VeELTA (Multi-Lock):  ", address(deployed.veELTAMulti));
        console2.log("LotPool:              ", address(deployed.lotPool));
        console2.log("Rewards Distributor:  ", address(deployed.rewardsDistributor));
        console2.log("Timelock Controller:  ", address(deployed.timelock));
        console2.log("Emergency Timelock:   ", address(deployed.emergencyTimelock));
        console2.log("Elata Governor:       ", address(deployed.governor));
        console2.log("=====================================");
    }
}
