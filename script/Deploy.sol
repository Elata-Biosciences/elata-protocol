// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/experience/ElataXP.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { LotPool } from "../src/governance/LotPool.sol";
import { RewardsDistributor } from "../src/rewards/RewardsDistributor.sol";
import { ElataGovernor } from "../src/governance/ElataGovernor.sol";
import { ElataTimelock } from "../src/governance/ElataTimelock.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { AppFactory } from "../src/apps/AppFactory.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";

/**
 * @title Deploy
 * @notice Official deployment script for the Elata Protocol
 * @dev Deploys the complete protocol with all features in the correct order
 */
contract Deploy is Script {
    // Configuration - Set via environment variables
    address public ADMIN_MSIG = vm.envAddress("ADMIN_MSIG");
    address public INITIAL_TREASURY = vm.envAddress("INITIAL_TREASURY");

    // Token configuration
    uint256 public constant INITIAL_MINT = 10_000_000 ether; // 10M ELTA initial
    uint256 public constant MAX_SUPPLY = 77_000_000 ether; // 77M ELTA total cap

    // Governance configuration
    uint256 public constant TIMELOCK_DELAY = 48 hours;

    struct ProtocolContracts {
        ELTA token;
        ElataXP xp;
        VeELTA staking;
        LotPool funding;
        RewardsDistributor rewards;
        TimelockController timelock;
        ElataGovernor governor;
        AppFactory appFactory;
    }

    event ProtocolDeployed(
        address indexed token,
        address indexed staking,
        address indexed xp,
        address funding,
        address rewards,
        address governor,
        address timelock,
        address appFactory
    );

    function run() external returns (ProtocolContracts memory protocol) {
        vm.startBroadcast();

        console2.log("=== ELATA PROTOCOL DEPLOYMENT ===");
        console2.log("Admin:", ADMIN_MSIG);
        console2.log("Treasury:", INITIAL_TREASURY);
        console2.log("Network:", block.chainid);
        console2.log("=====================================");

        // 1. Deploy core token
        protocol.token =
            new ELTA("ELTA", "ELTA", ADMIN_MSIG, INITIAL_TREASURY, INITIAL_MINT, MAX_SUPPLY);

        // 2. Deploy experience point system
        protocol.xp = new ElataXP(ADMIN_MSIG);

        // 3. Deploy staking system
        protocol.staking = new VeELTA(protocol.token, ADMIN_MSIG);

        // 4. Deploy governance infrastructure
        protocol.timelock = _deployTimelock();
        protocol.governor = new ElataGovernor(protocol.token);

        // 5. Deploy funding and rewards systems
        protocol.funding = new LotPool(protocol.token, protocol.xp, ADMIN_MSIG);
        protocol.rewards = new RewardsDistributor(protocol.staking, ADMIN_MSIG);

        // 6. Deploy app launch framework
        // Note: Router address should be set via environment variable for each network
        address routerAddress =
            vm.envOr("UNISWAP_V2_ROUTER", address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)); // Mainnet default
        if (routerAddress != address(0)) {
            protocol.appFactory = new AppFactory(
                protocol.token, IUniswapV2Router02(routerAddress), INITIAL_TREASURY, ADMIN_MSIG
            );
        }

        // 7. Configure system permissions
        _configurePermissions(protocol);

        // 7. Log deployment addresses
        _logDeployment(protocol);

        // 8. Emit deployment event
        emit ProtocolDeployed(
            address(protocol.token),
            address(protocol.staking),
            address(protocol.xp),
            address(protocol.funding),
            address(protocol.rewards),
            address(protocol.governor),
            address(protocol.timelock),
            address(protocol.appFactory)
        );

        vm.stopBroadcast();
    }

    /**
     * @dev Deploys timelock controller with standard configuration
     */
    function _deployTimelock() internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Will be set to governor after deployment

        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        return new ElataTimelock(TIMELOCK_DELAY, proposers, executors, ADMIN_MSIG);
    }

    /**
     * @dev Configures initial permissions and roles
     */
    function _configurePermissions(ProtocolContracts memory protocol) internal {
        // Grant governor proposer role on timelock
        protocol.timelock.grantRole(protocol.timelock.PROPOSER_ROLE(), address(protocol.governor));
        protocol.timelock.grantRole(protocol.timelock.EXECUTOR_ROLE(), address(protocol.governor));

        // Add ELTA as reward token
        protocol.rewards.addRewardToken(protocol.token);

        // Grant XP minter role to funding system for rewards
        protocol.xp.grantRole(protocol.xp.XP_MINTER_ROLE(), address(protocol.funding));

        console2.log("Permissions configured successfully");
    }

    /**
     * @dev Logs all deployment addresses for verification
     */
    function _logDeployment(ProtocolContracts memory protocol) internal view {
        console2.log("=== DEPLOYMENT COMPLETE ===");
        console2.log("ELTA Token:        ", address(protocol.token));
        console2.log("ElataXP:           ", address(protocol.xp));
        console2.log("VeELTA Staking:    ", address(protocol.staking));
        console2.log("LotPool Funding:   ", address(protocol.funding));
        console2.log("Rewards:           ", address(protocol.rewards));
        console2.log("Governor:          ", address(protocol.governor));
        console2.log("Timelock:          ", address(protocol.timelock));
        console2.log("App Factory:       ", address(protocol.appFactory));
        console2.log("===========================");

        // Verification commands
        console2.log("\n=== VERIFICATION COMMANDS ===");
        console2.log("cast call", address(protocol.token), '"name()"');
        console2.log("cast call", address(protocol.token), '"totalSupply()"');
        console2.log("cast call", address(protocol.staking), '"name()"');
        console2.log("cast call", address(protocol.xp), '"name()"');
        console2.log("=============================");
    }
}
