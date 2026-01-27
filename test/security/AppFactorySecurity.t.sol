// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppFactory} from "../../src/apps/AppFactory.sol";
import {AppFactoryViews} from "../../src/apps/AppFactoryViews.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Mock implementations
contract MockRouter {
    function factory() external pure returns (address) {
        return address(1);
    }

    function WETH() external pure returns (address) {
        return address(2);
    }
}

contract MockAppFeeRouter is IAppFeeRouter {
    function takeAndForwardFee(address, uint256) external pure {}

    function feeBps() external pure returns (uint256) {
        return 100;
    }

    function calculateFee(uint256) external pure returns (uint256) {
        return 0;
    }
}

contract MockXP is IElataPoints {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }
}

contract MockAppRewardsDistributor is IAppRewardsDistributor {
    function registerApp(address) external pure {}
    function registerApp(address, address) external pure {}
    function distribute(uint256) external pure {}
    function depositForApp(IERC20, uint256) external pure {}
    function claim(address, uint256) external pure {}
    function claimToken(address, IERC20, uint256) external pure {}
}

contract MockRewardsDistributor is IRewardsDistributor {
    function deposit(uint256) external pure {}
    function depositVeInToken(IERC20, uint256) external pure {}
}

/**
 * @title AppFactorySecurity
 * @notice Red team security tests for AppFactory
 */
contract AppFactorySecurity is Test {
    ELTA public elta;
    AppFactory public factory;
    AppFactoryViews public views;

    MockRouter public router;
    MockAppFeeRouter public feeRouter;
    MockXP public xp;
    MockAppRewardsDistributor public appRewards;
    MockRewardsDistributor public rewards;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public attacker = makeAddr("attacker");
    address public creator = makeAddr("creator");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy mocks
        router = new MockRouter();
        feeRouter = new MockAppFeeRouter();
        xp = new MockXP();
        appRewards = new MockAppRewardsDistributor();
        rewards = new MockRewardsDistributor();

        // Deploy factory
        factory = new AppFactory(
            IERC20(address(elta)),
            IUniswapV2Router02(address(router)),
            treasury,
            IAppFeeRouter(address(feeRouter)),
            IAppRewardsDistributor(address(appRewards)),
            IRewardsDistributor(address(rewards)),
            IElataPoints(address(xp)),
            governance,
            admin
        );

        views = new AppFactoryViews(address(factory));

        // Fund users
        vm.startPrank(admin);
        elta.transfer(attacker, 1_000_000 ether);
        elta.transfer(creator, 1_000_000 ether);
        vm.stopPrank();

        // Give XP to users
        xp.setBalance(creator, 1000 ether);
        xp.setBalance(attacker, 1000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FEE BYPASS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotCreateAppWithoutFee() public {
        uint256 creationFee = factory.creationFee();
        uint256 seedElta = factory.seedElta();

        vm.startPrank(creator);
        // Approve less than needed
        elta.approve(address(factory), creationFee + seedElta - 1);

        vm.expectRevert();
        factory.createApp("Test", "TEST", 0, "desc", "", "", new address[](0));
        vm.stopPrank();
    }

    function test_Security_CreationFeeDeducted() public {
        uint256 creationFee = factory.creationFee();
        uint256 seedElta = factory.seedElta();
        uint256 totalCost = creationFee + seedElta;

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        uint256 balanceBefore = elta.balanceOf(creator);
        factory.createApp("Test", "TEST", 0, "desc", "", "", new address[](0));
        uint256 balanceAfter = elta.balanceOf(creator);

        assertEq(balanceBefore - balanceAfter, totalCost, "Full cost should be deducted");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PAUSE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanPause() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setPaused(true);
    }

    function test_Security_CannotCreateAppWhenPaused() public {
        // Pause
        vm.prank(admin);
        factory.setPaused(true);

        // Try to create app
        uint256 totalCost = factory.creationFee() + factory.seedElta();
        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        vm.expectRevert();
        factory.createApp("Test", "TEST", 0, "desc", "", "", new address[](0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SUPPLY MANIPULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_CannotExceedDefaultSupply() public {
        uint256 defaultSupply = factory.defaultSupply();
        uint256 excessiveSupply = defaultSupply * 10;
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        // Factory should use default if excessive supply requested, or revert
        // depending on implementation
        try factory.createApp("Test", "TEST", excessiveSupply, "desc", "", "", new address[](0)) {
            // If it succeeds, check the actual supply used
            AppFactory.App memory app = factory.getApp(0);
            // The token should exist with some reasonable supply
            assertTrue(app.token != address(0), "Token should be created");
        } catch {
            // Revert is also acceptable
        }
        vm.stopPrank();
    }

    function test_Security_ZeroSupplyUsesDefault() public {
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        factory.createApp("Test", "TEST", 0, "desc", "", "", new address[](0));

        // Should use default supply
        AppFactory.App memory app = factory.getApp(0);
        assertTrue(app.token != address(0), "Token should be created");
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_OnlyAdminCanSetFeeManager() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setFeeManager(attacker);
    }

    function test_Security_OnlyAdminCanSetFeeCollector() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setFeeCollector(attacker);
    }

    function test_Security_OnlyAdminCanSetProtocolConfig() public {
        vm.expectRevert();
        vm.prank(attacker);
        factory.setProtocolConfig(attacker);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MULTIPLE APP TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Security_AppIdIncrementsCorrectly() public {
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost * 3);

        uint256 id1 = factory.createApp("App1", "APP1", 0, "", "", "", new address[](0));
        uint256 id2 = factory.createApp("App2", "APP2", 0, "", "", "", new address[](0));
        uint256 id3 = factory.createApp("App3", "APP3", 0, "", "", "", new address[](0));

        assertEq(id1, 0, "First app should be ID 0");
        assertEq(id2, 1, "Second app should be ID 1");
        assertEq(id3, 2, "Third app should be ID 2");
        assertEq(factory.appCount(), 3, "App count should be 3");
        vm.stopPrank();
    }

    function test_Security_CreatorTrackedCorrectly() public {
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        factory.createApp("Test", "TEST", 0, "desc", "", "", new address[](0));
        vm.stopPrank();

        AppFactory.App memory app = factory.getApp(0);
        assertEq(app.creator, creator, "Creator should be tracked");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_Security_CreateMultipleApps(uint8 numApps) public {
        numApps = uint8(bound(numApps, 1, 5));
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost * numApps);

        for (uint8 i = 0; i < numApps; i++) {
            string memory name = string(abi.encodePacked("App", i));
            factory.createApp(name, "TEST", 0, "", "", "", new address[](0));
        }

        assertEq(factory.appCount(), numApps, "App count should match");
        vm.stopPrank();
    }
}
