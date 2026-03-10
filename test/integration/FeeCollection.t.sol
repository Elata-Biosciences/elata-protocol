// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {ELTA} from "elta/ELTA.sol";
import "forge-std/Test.sol";

/// @notice Mock ElataPoints for testing
contract MockElataPoints is IElataPoints {
    mapping(address => uint256) private _balances;

    function setBalance(address user, uint256 balance) external {
        _balances[user] = balance;
    }

    function balanceOf(address user) external view returns (uint256) {
        return _balances[user];
    }

    function grantRole(bytes32, address) external {}

    function POINTS_OPERATOR_ROLE() external pure returns (bytes32) {
        return keccak256("POINTS_OPERATOR_ROLE");
    }
}

/// @notice Mock AppFeeRouter with 1% fee
contract MockAppFeeRouter is IAppFeeRouter {
    function routeFees(uint256, uint256) external {}
    function takeAndForwardFee(address, uint256) external {}

    function feeBps() external pure returns (uint256) {
        return 100; // 1% fee
    }

    function calculateFee(uint256 amount) external pure returns (uint256) {
        return (amount * 100) / 10000;
    }
}

/// @notice Mock Uniswap Router
contract MockUniswapRouter {
    address public factory = address(0x1111);

    function WETH() external pure returns (address) {
        return address(0x2222);
    }
}

/// @notice Mock AppFactory for testing
contract MockAppFactory {
    function onAppGraduated(uint256, address, address, uint256, uint256, uint256) external {}

    function initializeCurve(address curve, uint256 seedElta, uint256 tokenSupply) external {
        AppBondingCurve(curve).initializeCurve(seedElta, tokenSupply);
    }
}

/**
 * @title FeeCollectionTest
 * @notice End-to-end integration tests for bonding curve fee collection
 * @dev Tests the flow:
 *      1. Create app with bonding curve
 *      2. Trades accumulate fees in pendingFees
 *      3. sweepFees() sends fees to FeeCollector
 *      4. Verify fees arrive correctly
 */
contract FeeCollectionTest is Test {
    // Core contracts
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    FeeCollector public feeCollector;
    FeeManager public feeManager;
    MockAppFactory public appFactory;
    MockElataPoints public xp;
    MockAppFeeRouter public feeRouter;
    MockUniswapRouter public router;

    // Addresses
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public buyer = makeAddr("buyer");

    // Constants
    uint256 constant APP_ID = 1;
    uint256 constant APP_TOKEN_SUPPLY = 1_000_000_000 ether;
    uint256 constant SEED_ELTA = 100 ether;
    uint256 constant TARGET_RAISED = 100_000 ether;
    uint256 constant TRADE_AMOUNT = 1000 ether;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(admin);

        // Deploy mocks
        xp = new MockElataPoints();
        xp.setBalance(buyer, 1000 ether); // Give buyer XP for early access
        feeRouter = new MockAppFeeRouter();
        router = new MockUniswapRouter();
        appFactory = new MockAppFactory();

        // Deploy FeeManager (minimal for testing)
        feeManager = new FeeManager(
            address(elta), makeAddr("usdc"), admin, admin, makeAddr("appRewards"), makeAddr("rewards"), treasury, 1 days
        );

        // Deploy FeeCollector
        feeCollector = new FeeCollector(
            address(elta),
            admin,
            address(feeManager),
            address(0) // No FeeSwapper
        );

        // Make FeeCollector an authorized depositor on FeeManager
        feeManager.setDepositor(address(feeCollector), true);

        // Deploy AppToken
        appToken = new AppToken(
            AppToken.InitParams({
                name: "TestApp",
                symbol: "TEST",
                decimals: 18,
                maxSupply: APP_TOKEN_SUPPLY,
                creator: creator,
                admin: admin,
                governance: governance,
                appRewardsDistributor: treasury,
                rewardsDistributor: treasury,
                treasury: treasury
            })
        );

        // Deploy BondingCurve with feeCollector wired
        curve = new AppBondingCurve(
            AppBondingCurve.InitParams({
                appId: APP_ID,
                factory: address(appFactory),
                elta: IERC20(address(elta)),
                token: appToken,
                router: IUniswapV2Router02(address(router)),
                targetRaisedElta: TARGET_RAISED,
                lpLockDuration: 365 days * 2,
                lpBeneficiary: creator,
                treasury: treasury,
                appFeeRouter: IAppFeeRouter(address(feeRouter)),
                elataPoints: IElataPoints(address(xp)),
                governance: governance,
                activationDelay: 0,
                maxDuration: 365 days,
                creator: creator,
                feeCollector: address(feeCollector),
                referralRegistry: address(0)
            })
        );

        // Mint tokens to curve
        appToken.mint(address(curve), APP_TOKEN_SUPPLY / 2);

        // Seed curve with ELTA
        elta.transfer(address(curve), SEED_ELTA);

        // Initialize curve via factory
        appFactory.initializeCurve(address(curve), SEED_ELTA, APP_TOKEN_SUPPLY / 2);

        // Fund buyer with ELTA
        elta.transfer(buyer, 100_000 ether);

        vm.stopPrank();

        // Activate the curve (it has 0 delay, just needs to be called)
        curve.activate();
    }

    function test_Integration_TradesAccumulateFees() public {
        // Initial state: no pending fees
        assertEq(curve.pendingFees(), 0, "Initial pending fees should be 0");

        // Buyer trades on the curve (approve extra for fee)
        vm.startPrank(buyer);
        elta.approve(address(curve), TRADE_AMOUNT * 2); // Extra for fees

        // Buy tokens
        uint256 tokensReceived = curve.buy(TRADE_AMOUNT, 0, address(0));
        assertGt(tokensReceived, 0, "Should receive tokens");

        // Verify fees accumulated
        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Fees should have accumulated");

        vm.stopPrank();
    }

    function test_Integration_SweepFeesToCollector() public {
        // Trade to accumulate fees (approve extra for fee)
        vm.startPrank(buyer);
        elta.approve(address(curve), TRADE_AMOUNT * 2);
        curve.buy(TRADE_AMOUNT, 0, address(0));
        vm.stopPrank();

        // Get pending fees amount
        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Fees should exist to sweep");

        // Initial FeeCollector balance
        uint256 collectorBefore = elta.balanceOf(address(feeCollector));

        // Sweep fees
        curve.sweepFees();

        // Verify fees swept
        assertEq(curve.pendingFees(), 0, "Pending fees should be 0 after sweep");

        // Verify FeeCollector received fees
        uint256 collectorAfter = elta.balanceOf(address(feeCollector));
        assertGt(collectorAfter, collectorBefore, "FeeCollector should have more ELTA");
    }

    function test_Integration_MultipleTrades() public {
        vm.startPrank(buyer);
        elta.approve(address(curve), TRADE_AMOUNT * 5);

        // Multiple trades
        for (uint256 i = 0; i < 5; i++) {
            curve.buy(TRADE_AMOUNT / 5, 0, address(0));
        }

        // Check accumulated fees
        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Fees should accumulate from multiple trades");

        vm.stopPrank();

        // Sweep
        uint256 collectorBefore = elta.balanceOf(address(feeCollector));
        curve.sweepFees();
        uint256 collectorAfter = elta.balanceOf(address(feeCollector));

        // Verify all fees swept
        assertEq(curve.pendingFees(), 0, "All fees should be swept");
        assertEq(collectorAfter - collectorBefore, pendingFees, "Collector should receive exact fee amount");
    }

    function test_Integration_LargeTradeFees() public {
        uint256 largeTrade = 10_000 ether;

        vm.startPrank(buyer);
        elta.approve(address(curve), largeTrade * 2); // Extra for fees

        // Large buy
        uint256 tokensReceived = curve.buy(largeTrade, 0, address(0));
        assertGt(tokensReceived, 0, "Should receive tokens");

        // Check fees from large trade
        uint256 pendingFees = curve.pendingFees();
        assertGt(pendingFees, 0, "Fees should accumulate from large trade");

        // Fees should be proportional to trade size
        // Generally should be around 1-2% of trade depending on fee bps
        assertGt(pendingFees, largeTrade / 200, "Fees should be meaningful portion of trade");

        vm.stopPrank();
    }

    function test_Integration_NoFeesWhenZeroTrade() public {
        // No trades, no fees
        assertEq(curve.pendingFees(), 0, "No fees without trades");

        // Sweep should work but do nothing
        curve.sweepFees();
        assertEq(curve.pendingFees(), 0, "Still no fees");
    }

    function test_Integration_FeeCollectorTracksAppFees() public {
        // Trade to accumulate fees (approve extra for fee)
        vm.startPrank(buyer);
        elta.approve(address(curve), TRADE_AMOUNT * 2);
        curve.buy(TRADE_AMOUNT, 0, address(0));
        vm.stopPrank();

        // Sweep fees to collector
        curve.sweepFees();

        // FeeCollector should have ELTA
        uint256 collectorBalance = elta.balanceOf(address(feeCollector));
        assertGt(collectorBalance, 0, "FeeCollector should have ELTA");

        // Get pending ELTA fees for this app in collector
        uint256 pendingAppFees = feeCollector.pendingEltaFees(APP_ID, FeeKind.TRADING_FEE);
        assertGt(pendingAppFees, 0, "App fees should be tracked in pendingEltaFees");
    }
}
