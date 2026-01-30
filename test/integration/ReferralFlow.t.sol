// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AppBondingCurve} from "../../src/apps/AppBondingCurve.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {ReferralRegistry} from "../../src/modules/ReferralRegistry.sol";
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

/// @notice Mock AppFeeRouter
contract MockAppFeeRouter is IAppFeeRouter {
    function routeFees(uint256, uint256) external {}
    function takeAndForwardFee(address, uint256) external {}

    function feeBps() external pure returns (uint256) {
        return 0;
    }

    function calculateFee(uint256) external pure returns (uint256) {
        return 0;
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
 * @title ReferralFlowTest
 * @notice End-to-end integration tests for referral tracking in bonding curve trades
 * @dev Tests the flow:
 *      1. Create app with bonding curve wired to ReferralRegistry
 *      2. User buys with referrer address
 *      3. Verify referrer is set in registry
 *      4. Verify referral count increases
 */
contract ReferralFlowTest is Test {
    // Core contracts
    ELTA public elta;
    AppToken public appToken;
    AppBondingCurve public curve;
    ReferralRegistry public referralRegistry;
    MockAppFactory public appFactory;
    MockElataPoints public xp;
    MockAppFeeRouter public feeRouter;
    MockUniswapRouter public router;

    // Addresses
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public referrer = makeAddr("referrer");

    // Constants
    uint256 constant APP_ID = 1;
    uint256 constant APP_TOKEN_SUPPLY = 1_000_000_000 ether;
    uint256 constant SEED_ELTA = 100 ether;
    uint256 constant TARGET_RAISED = 100_000 ether;
    uint256 constant TRADE_AMOUNT = 1000 ether;
    uint256 constant REFERRAL_FEE_BPS = 500; // 5%

    function setUp() public {
        vm.startPrank(admin);

        // Deploy ELTA
        elta = new ELTA(admin);

        // Deploy ReferralRegistry
        referralRegistry = new ReferralRegistry(admin, address(elta), REFERRAL_FEE_BPS);

        // Deploy mocks
        xp = new MockElataPoints();
        xp.setBalance(buyer1, 1000 ether);
        xp.setBalance(buyer2, 1000 ether);
        feeRouter = new MockAppFeeRouter();
        router = new MockUniswapRouter();
        appFactory = new MockAppFactory();

        // Deploy AppToken
        appToken = new AppToken(
            "TestApp", "TEST", 18, APP_TOKEN_SUPPLY, creator, admin, governance, treasury, treasury, treasury
        );

        // Deploy BondingCurve with ReferralRegistry wired
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
                feeCollector: address(0),
                referralRegistry: address(referralRegistry)
            })
        );

        // Authorize the curve to set referrals
        referralRegistry.setAuthorizedCaller(address(curve), true);

        // Mint tokens to curve
        appToken.mint(address(curve), APP_TOKEN_SUPPLY / 2);

        // Seed curve with ELTA
        elta.transfer(address(curve), SEED_ELTA);

        // Initialize curve via factory
        appFactory.initializeCurve(address(curve), SEED_ELTA, APP_TOKEN_SUPPLY / 2);

        // Fund buyers with ELTA
        elta.transfer(buyer1, 50_000 ether);
        elta.transfer(buyer2, 50_000 ether);

        vm.stopPrank();

        // Activate the curve (it has 0 delay, just needs to be called)
        curve.activate();
    }

    function test_Integration_BuyWithReferrer() public {
        // Initial state: buyer1 has no referrer for this app
        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), address(0), "Initial referrer should be 0");

        // Buyer1 buys with referrer
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT);
        uint256 tokensReceived = curve.buy(TRADE_AMOUNT, 0, referrer);
        vm.stopPrank();

        // Verify tokens received
        assertGt(tokensReceived, 0, "Should receive tokens");

        // Verify referrer was set
        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), referrer, "Referrer should be set");
    }

    function test_Integration_ReferrerNotOverwritten() public {
        // First purchase with referrer
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT * 2);
        curve.buy(TRADE_AMOUNT, 0, referrer);
        vm.stopPrank();

        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), referrer, "Initial referrer set");

        // Second purchase with different referrer - should NOT overwrite
        address newReferrer = makeAddr("newReferrer");
        vm.startPrank(buyer1);
        curve.buy(TRADE_AMOUNT, 0, newReferrer);
        vm.stopPrank();

        // Original referrer should remain
        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), referrer, "Original referrer should remain");
    }

    function test_Integration_SelfReferralPrevented() public {
        // Try to buy with self as referrer - should revert
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT);
        vm.expectRevert(ReferralRegistry.SelfReferral.selector);
        curve.buy(TRADE_AMOUNT, 0, buyer1); // Self-referral attempt
        vm.stopPrank();
    }

    function test_Integration_NoReferrer() public {
        // Buy without referrer
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT);
        curve.buy(TRADE_AMOUNT, 0, address(0)); // No referrer
        vm.stopPrank();

        // No referrer should be set
        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), address(0), "No referrer when none provided");
    }

    function test_Integration_ReferralCount() public {
        // Initial count
        assertEq(referralRegistry.getReferralCount(APP_ID, referrer), 0, "Initial count should be 0");

        // Multiple buyers use same referrer
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT);
        curve.buy(TRADE_AMOUNT, 0, referrer);
        vm.stopPrank();

        assertEq(referralRegistry.getReferralCount(APP_ID, referrer), 1, "Count should be 1");

        vm.startPrank(buyer2);
        elta.approve(address(curve), TRADE_AMOUNT);
        curve.buy(TRADE_AMOUNT, 0, referrer);
        vm.stopPrank();

        assertEq(referralRegistry.getReferralCount(APP_ID, referrer), 2, "Count should be 2");
    }

    function test_Integration_MultipleReferrers() public {
        address referrer2 = makeAddr("referrer2");

        // Buyer1 uses referrer
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT);
        curve.buy(TRADE_AMOUNT, 0, referrer);
        vm.stopPrank();

        // Buyer2 uses referrer2
        vm.startPrank(buyer2);
        elta.approve(address(curve), TRADE_AMOUNT);
        curve.buy(TRADE_AMOUNT, 0, referrer2);
        vm.stopPrank();

        // Verify different referrers
        assertEq(referralRegistry.getReferrer(APP_ID, buyer1), referrer, "Buyer1 referrer");
        assertEq(referralRegistry.getReferrer(APP_ID, buyer2), referrer2, "Buyer2 referrer");
        assertEq(referralRegistry.getReferralCount(APP_ID, referrer), 1, "Referrer count");
        assertEq(referralRegistry.getReferralCount(APP_ID, referrer2), 1, "Referrer2 count");
    }

    function test_Integration_SubsequentBuysDontIncreaseCount() public {
        // Buy with referrer first
        vm.startPrank(buyer1);
        elta.approve(address(curve), TRADE_AMOUNT * 3);

        // First buy sets referrer
        curve.buy(TRADE_AMOUNT, 0, referrer);
        uint256 countAfterFirstBuy = referralRegistry.getReferralCount(APP_ID, referrer);
        assertEq(countAfterFirstBuy, 1, "First buy should set count to 1");

        // Second buy by same user should not increase count
        curve.buy(TRADE_AMOUNT, 0, referrer);
        uint256 countAfterSecondBuy = referralRegistry.getReferralCount(APP_ID, referrer);
        assertEq(countAfterSecondBuy, 1, "Second buy should not increase count");

        // Third buy should also not increase count
        curve.buy(TRADE_AMOUNT, 0, referrer);
        uint256 countAfterThirdBuy = referralRegistry.getReferralCount(APP_ID, referrer);
        assertEq(countAfterThirdBuy, 1, "Third buy should not increase count");

        vm.stopPrank();
    }

    function test_Integration_UnauthorizedCallerCannotSetReferral() public {
        // Try to set referral directly (not through authorized curve)
        vm.expectRevert();
        referralRegistry.setReferrer(APP_ID, buyer1, referrer);
    }

    function test_Integration_AdminCanAuthorize() public {
        address newCurve = makeAddr("newCurve");

        // Initially not authorized
        assertFalse(referralRegistry.authorizedCallers(newCurve), "Initially not authorized");

        // Admin authorizes
        vm.prank(admin);
        referralRegistry.setAuthorizedCaller(newCurve, true);

        assertTrue(referralRegistry.authorizedCallers(newCurve), "Should be authorized");
    }
}
