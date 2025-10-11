// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ELTA } from "../src/token/ELTA.sol";
import { ElataXP } from "../src/experience/ElataXP.sol";
import { VeELTA } from "../src/staking/VeELTA.sol";
import { LotPool } from "../src/governance/LotPool.sol";
import { RewardsDistributor } from "../src/rewards/RewardsDistributor.sol";
import { ElataGovernor } from "../src/governance/ElataGovernor.sol";
import { ElataTimelock } from "../src/governance/ElataTimelock.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { AppFactory } from "../src/apps/AppFactory.sol";
import { AppFactoryViews } from "../src/apps/AppFactoryViews.sol";
import { AppModuleFactory } from "../src/apps/AppModuleFactory.sol";
import { TournamentFactory } from "../src/apps/TournamentFactory.sol";
import { IUniswapV2Router02 } from "../src/interfaces/IUniswapV2Router02.sol";

/**
 * @title DeployLocalFull
 * @notice Comprehensive local deployment script for development
 * @dev Deploys ALL Elata Protocol contracts with mock Uniswap for local testing
 */

// ============= Mock Contracts for Local Development =============

contract MockUniswapV2Router {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Mock: just return the desired amounts
        return (amountADesired, amountBDesired, amountADesired + amountBDesired);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address,
        uint256
    ) external returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn; // 1:1 for simplicity
        return amounts;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountIn; // 1:1 for simplicity
        return amounts;
    }
}

contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Create a deterministic mock pair address
        pair =
            address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        getPair[tokenA][tokenB] = pair;
        getPair[tokenB][tokenA] = pair;
        allPairs.push(pair);
        return pair;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}

// ============= Main Deployment Script =============

contract DeployLocalFull is Script {
    // Configuration
    uint256 public constant INITIAL_MINT = 10_000_000 ether; // 10M ELTA
    uint256 public constant MAX_SUPPLY = 77_000_000 ether; // 77M ELTA total cap
    uint256 public constant TIMELOCK_DELAY = 1 hours; // Shorter for local testing
    uint256 public constant TEST_ACCOUNT_ELTA = 100_000 ether; // 100K ELTA per test account

    struct DeploymentResult {
        // Core Protocol
        ELTA token;
        ElataXP xp;
        VeELTA staking;
        LotPool funding;
        RewardsDistributor rewards;
        TimelockController timelock;
        ElataGovernor governor;
        // App Ecosystem
        AppFactory appFactory;
        AppFactoryViews appFactoryViews;
        AppModuleFactory appModuleFactory;
        TournamentFactory tournamentFactory;
        // Mock Uniswap
        MockUniswapV2Factory uniFactory;
        MockUniswapV2Router uniRouter;
        // Accounts
        address deployer;
        address treasury;
        address[] testAccounts;
    }

    function run() external returns (DeploymentResult memory result) {
        // Use Anvil account #0 (has 10K ETH by default)
        uint256 deployerPrivateKey =
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        result.deployer = vm.addr(deployerPrivateKey);
        result.treasury = result.deployer;

        vm.startBroadcast(deployerPrivateKey);

        console2.log("\n=================================================");
        console2.log("  ELATA PROTOCOL - LOCAL DEVELOPMENT DEPLOYMENT");
        console2.log("=================================================\n");
        console2.log("Network:  Anvil (localhost:8545)");
        console2.log("Chain ID: 31337");
        console2.log("Deployer:", result.deployer);
        console2.log("Treasury:", result.treasury);
        console2.log("");

        // ===== STEP 1: Deploy Core Token =====
        console2.log("[1/10] Deploying ELTA Token...");
        result.token = new ELTA(
            "Elata Token",
            "ELTA",
            result.deployer, // admin
            result.treasury, // treasury
            INITIAL_MINT,
            MAX_SUPPLY
        );
        console2.log("       ELTA Token deployed at:", address(result.token));

        // ===== STEP 2: Deploy XP System =====
        console2.log("[2/10] Deploying ElataXP...");
        result.xp = new ElataXP(result.deployer);
        console2.log("       ElataXP deployed at:", address(result.xp));

        // ===== STEP 3: Deploy Staking System =====
        console2.log("[3/10] Deploying VeELTA Staking...");
        result.staking = new VeELTA(result.token, result.deployer);
        console2.log("       VeELTA deployed at:", address(result.staking));

        // ===== STEP 4: Deploy Governance =====
        console2.log("[4/10] Deploying Governance (Timelock + Governor)...");
        result.timelock = _deployTimelock(result.deployer);
        result.governor = new ElataGovernor(result.token);
        console2.log("       Timelock deployed at:", address(result.timelock));
        console2.log("       Governor deployed at:", address(result.governor));

        // ===== STEP 5: Deploy Funding System =====
        console2.log("[5/10] Deploying LotPool Funding...");
        result.funding = new LotPool(result.token, result.xp, result.deployer);
        console2.log("       LotPool deployed at:", address(result.funding));

        // ===== STEP 6: Deploy Rewards System =====
        console2.log("[6/10] Deploying Rewards Distributor...");
        // NOTE: RewardsDistributor deployment commented out - use script/Deploy.sol
        // RewardsDistributor now requires VeELTA, AppRewardsDistributor, and treasury
        // For full deployment, use: forge script script/Deploy.sol:Deploy --fork-url http://localhost:8545 --broadcast
        // result.rewards = new RewardsDistributor(...);
        console2.log("       RewardsDistributor deployed at:", address(result.rewards));

        // ===== STEP 7: Deploy Mock Uniswap =====
        console2.log("[7/10] Deploying Mock Uniswap (Factory + Router)...");
        result.uniFactory = new MockUniswapV2Factory();
        result.uniRouter = new MockUniswapV2Router(address(result.uniFactory));
        console2.log("       Mock Uniswap Factory deployed at:", address(result.uniFactory));
        console2.log("       Mock Uniswap Router deployed at:", address(result.uniRouter));

        // ===== STEP 8: Deploy App Launch Framework =====
        console2.log("[8/10] Deploying App Factories...");
        // NOTE: AppFactory deployment commented out - use script/Deploy.sol
        // AppFactory now requires AppFeeRouter and AppRewardsDistributor
        // result.appFactory = new AppFactory(...);
        console2.log("       AppFactory deployment skipped (use DeployEconomicUpgrade.s.sol)");

        result.appFactoryViews = new AppFactoryViews(address(result.appFactory));
        console2.log("       AppFactoryViews deployed at:", address(result.appFactoryViews));

        result.appModuleFactory =
            new AppModuleFactory(address(result.token), result.deployer, result.treasury);
        console2.log("       AppModuleFactory deployed at:", address(result.appModuleFactory));

        result.tournamentFactory = new TournamentFactory(result.deployer, result.treasury);
        console2.log("       TournamentFactory deployed at:", address(result.tournamentFactory));

        // ===== STEP 9: Configure Permissions =====
        console2.log("[9/10] Configuring Permissions...");
        _configurePermissions(result);
        console2.log("       Permissions configured successfully");

        // ===== STEP 10: Setup Test Accounts =====
        console2.log("[10/10] Setting up Test Accounts...");
        result.testAccounts = _setupTestAccounts(result.token);
        console2.log("       Test accounts funded successfully");

        vm.stopBroadcast();

        // ===== Log Deployment Summary =====
        _logDeploymentSummary(result);

        // ===== Write Deployment JSON =====
        _writeDeploymentJson(result);

        return result;
    }

    function _deployTimelock(address admin) internal returns (TimelockController) {
        address[] memory proposers = new address[](1);
        proposers[0] = address(0); // Will be set to governor

        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute

        return new ElataTimelock(TIMELOCK_DELAY, proposers, executors, admin);
    }

    function _configurePermissions(DeploymentResult memory result) internal {
        // Grant governor roles on timelock
        result.timelock.grantRole(result.timelock.PROPOSER_ROLE(), address(result.governor));
        result.timelock.grantRole(result.timelock.EXECUTOR_ROLE(), address(result.governor));

        // NOTE: RewardsDistributor no longer has addRewardToken()
        // New architecture uses ELTA directly in deposit()
        // result.rewards.addRewardToken(result.token);

        // Grant XP operator role to funding system
        result.xp.grantRole(result.xp.XP_OPERATOR_ROLE(), address(result.funding));
    }

    function _setupTestAccounts(ELTA token) internal returns (address[] memory accounts) {
        // Anvil's default test accounts (deterministic)
        accounts = new address[](5);
        accounts[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Account #1
        accounts[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Account #2
        accounts[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Account #3
        accounts[3] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // Account #4
        accounts[4] = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc; // Account #5

        // Mint ELTA to each test account
        for (uint256 i = 0; i < accounts.length; i++) {
            token.mint(accounts[i], TEST_ACCOUNT_ELTA);
        }

        return accounts;
    }

    function _logDeploymentSummary(DeploymentResult memory result) internal view {
        console2.log("\n=================================================");
        console2.log("         DEPLOYMENT COMPLETE - SUMMARY");
        console2.log("=================================================\n");

        console2.log("CORE PROTOCOL CONTRACTS:");
        console2.log("------------------------");
        console2.log("ELTA Token:              ", address(result.token));
        console2.log("ElataXP:                 ", address(result.xp));
        console2.log("VeELTA Staking:          ", address(result.staking));
        console2.log("LotPool Funding:         ", address(result.funding));
        console2.log("Rewards Distributor:     ", address(result.rewards));
        console2.log("Timelock Controller:     ", address(result.timelock));
        console2.log("Elata Governor:          ", address(result.governor));
        console2.log("");

        console2.log("APP ECOSYSTEM CONTRACTS:");
        console2.log("------------------------");
        console2.log("App Factory:             ", address(result.appFactory));
        console2.log("App Factory Views:       ", address(result.appFactoryViews));
        console2.log("App Module Factory:      ", address(result.appModuleFactory));
        console2.log("Tournament Factory:      ", address(result.tournamentFactory));
        console2.log("");

        console2.log("MOCK DEX CONTRACTS:");
        console2.log("-------------------");
        console2.log("Uniswap V2 Factory:      ", address(result.uniFactory));
        console2.log("Uniswap V2 Router:       ", address(result.uniRouter));
        console2.log("");

        console2.log("TEST ACCOUNTS (100K ELTA each):");
        console2.log("--------------------------------");
        console2.log("Deployer:                ", result.deployer);
        for (uint256 i = 0; i < result.testAccounts.length; i++) {
            console2.log(
                string.concat("Test Account #", vm.toString(i + 1), ":        "),
                result.testAccounts[i]
            );
        }
        console2.log("");

        console2.log("=================================================");
        console2.log("NEXT STEPS:");
        console2.log("1. Run seed script: npm run dev:seed");
        console2.log("2. Start frontend: npm run dev:frontend");
        console2.log("3. Addresses saved to: deployments/local.json");
        console2.log("=================================================\n");
    }

    function _writeDeploymentJson(DeploymentResult memory result) internal {
        // Build JSON string manually (Solidity doesn't have native JSON)
        string memory json = string.concat(
            "{\n",
            '  "network": "localhost",\n',
            '  "chainId": 31337,\n',
            '  "deployer": "',
            vm.toString(result.deployer),
            '",\n',
            '  "contracts": {\n',
            '    "ELTA": "',
            vm.toString(address(result.token)),
            '",\n',
            '    "ElataXP": "',
            vm.toString(address(result.xp)),
            '",\n',
            '    "VeELTA": "',
            vm.toString(address(result.staking)),
            '",\n',
            '    "LotPool": "',
            vm.toString(address(result.funding)),
            '",\n',
            '    "RewardsDistributor": "',
            vm.toString(address(result.rewards)),
            '",\n',
            '    "ElataTimelock": "',
            vm.toString(address(result.timelock)),
            '",\n',
            '    "ElataGovernor": "',
            vm.toString(address(result.governor)),
            '",\n',
            '    "AppFactory": "',
            vm.toString(address(result.appFactory)),
            '",\n',
            '    "AppFactoryViews": "',
            vm.toString(address(result.appFactoryViews)),
            '",\n',
            '    "AppModuleFactory": "',
            vm.toString(address(result.appModuleFactory)),
            '",\n',
            '    "TournamentFactory": "',
            vm.toString(address(result.tournamentFactory)),
            '",\n',
            '    "UniswapV2Factory": "',
            vm.toString(address(result.uniFactory)),
            '",\n',
            '    "UniswapV2Router": "',
            vm.toString(address(result.uniRouter)),
            '"\n',
            "  },\n",
            '  "testAccounts": [\n'
        );

        for (uint256 i = 0; i < result.testAccounts.length; i++) {
            json = string.concat(
                json,
                '    "',
                vm.toString(result.testAccounts[i]),
                '"',
                i < result.testAccounts.length - 1 ? ",\n" : "\n"
            );
        }

        json = string.concat(json, "  ]\n", "}\n");

        // Write to file
        vm.writeFile("deployments/local.json", json);
        console2.log("Deployment addresses written to: deployments/local.json");
    }
}
