// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppFactory } from "../../src/apps/AppFactory.sol";
import { AppFactoryViews } from "../../src/apps/AppFactoryViews.sol";
import { AppToken } from "../../src/apps/AppToken.sol";
import { AppBondingCurve } from "../../src/apps/AppBondingCurve.sol";
import { IUniswapV2Router02 } from "../../src/interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";
import { IElataXP } from "../../src/interfaces/IElataXP.sol";
import { MockAppFeeRouter, MockAppRewardsDistributor } from "../mocks/MockContracts.sol";

// Mock ElataXP
contract MockElataXP is IElataXP {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function setBalance(address account, uint256 balance) external {
        balances[account] = balance;
    }
}

// Mock RewardsDistributor
contract MockRewardsDistributor is IRewardsDistributor {
    function deposit(uint256) external pure { }
    function depositVeInToken(IERC20, uint256) external pure { }
}

contract AppFactoryTest is Test {
    ELTA public elta;
    AppFactory public factory;
    AppFactoryViews public views;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public creator = makeAddr("creator");
    address public user1 = makeAddr("user1");
    address public governance = makeAddr("governance");

    // Mock Uniswap router (for testing)
    address public mockRouter = makeAddr("mockRouter");

    MockAppFeeRouter public mockFeeRouter;
    MockAppRewardsDistributor public mockAppRewards;
    MockRewardsDistributor public mockRewards;
    MockElataXP public mockXP;

    function setUp() public {
        elta = new ELTA("ELTA", "ELTA", admin, treasury, 10_000_000 ether, 77_000_000 ether);

        // Deploy mocks
        mockFeeRouter = new MockAppFeeRouter();
        mockAppRewards = new MockAppRewardsDistributor();
        mockRewards = new MockRewardsDistributor();
        mockXP = new MockElataXP();

        // For testing, we'll use a mock router address
        // In production, this would be the actual Uniswap router
        vm.mockCall(
            mockRouter, abi.encodeWithSignature("factory()"), abi.encode(makeAddr("mockFactory"))
        );

        factory = new AppFactory(
            elta,
            IUniswapV2Router02(mockRouter),
            treasury,
            IAppFeeRouter(address(mockFeeRouter)),
            IAppRewardsDistributor(address(mockAppRewards)),
            IRewardsDistributor(address(mockRewards)),
            mockXP,
            governance,
            admin
        );

        // Deploy views contract for complex queries
        views = new AppFactoryViews(address(factory));

        // Give creator some ELTA
        vm.prank(treasury);
        elta.transfer(creator, 10_000 ether);
    }

    function test_Deployment() public {
        assertEq(address(factory.ELTA()), address(elta));
        assertEq(address(factory.router()), mockRouter);
        assertEq(factory.treasury(), treasury);
        assertEq(factory.seedElta(), 100 ether);
        assertEq(factory.targetRaisedElta(), 42_000 ether);
        assertEq(factory.defaultSupply(), 1_000_000_000 ether);
        assertEq(factory.appCount(), 0);
        assertFalse(factory.paused());
    }

    function test_CreateApp() public {
        uint256 totalCost = factory.creationFee() + factory.seedElta(); // 10 + 100 = 110 ELTA

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);

        uint256 appId = factory.createApp(
            "NeuroGame",
            "NEURO",
            0, // Use default supply
            "A revolutionary EEG-based game",
            "ipfs://QmHash...",
            "https://neurogame.com"
        );
        vm.stopPrank();

        assertEq(appId, 0);
        assertEq(factory.appCount(), 1);

        // Check app details
        AppFactory.App memory app = factory.getApp(appId);
        assertEq(app.creator, creator);
        assertEq(app.createdAt, block.timestamp);
        assertFalse(app.graduated);
        assertTrue(app.token != address(0));
        assertTrue(app.curve != address(0));

        // Check token details
        AppToken token = AppToken(app.token);
        assertEq(token.name(), "NeuroGame");
        assertEq(token.symbol(), "NEURO");
        assertEq(token.appCreator(), creator);
        assertEq(token.totalSupply(), factory.defaultSupply());

        // Check creator apps mapping (use views contract)
        uint256[] memory creatorApps = views.getCreatorApps(creator);
        assertEq(creatorApps.length, 1);
        assertEq(creatorApps[0], appId);

        // Check token to app mapping
        assertEq(factory.tokenToAppId(app.token), appId);
    }

    function test_RevertWhen_CreateAppPaused() public {
        vm.prank(admin);
        factory.setPaused(true);

        vm.expectRevert(AppFactory.Paused.selector);
        vm.prank(creator);
        factory.createApp("Test", "TEST", 0, "", "", "");
    }

    function test_RevertWhen_CreateAppInsufficientFunds() public {
        // Creator doesn't have enough ELTA
        vm.expectRevert();
        vm.prank(creator);
        factory.createApp("Test", "TEST", 0, "", "", "");
    }

    // Parameters are now immutable (constants) for contract size optimization
    function test_ParametersAreImmutable() public view {
        assertEq(factory.seedElta(), 100 ether);
        assertEq(factory.targetRaisedElta(), 42_000 ether);
        assertEq(factory.defaultSupply(), 1_000_000_000 ether);
        assertEq(factory.lpLockDuration(), 365 days * 2);
        assertEq(factory.defaultDecimals(), 18);
        // Removed protocolFeeRate check - legacy fee removed in favor of unified 70/15/15 split
        assertEq(factory.creationFee(), 10 ether);
    }

    function test_GetLaunchStats() public {
        // Initially no apps
        (
            uint256 totalApps,
            uint256 graduatedApps,
            uint256 totalValueLocked,
            uint256 totalFeesCollected
        ) = views.getLaunchStats();

        assertEq(totalApps, 0);
        assertEq(graduatedApps, 0);
        assertEq(totalValueLocked, 0);
        assertEq(totalFeesCollected, 0);

        // Create an app
        uint256 totalCost = factory.creationFee() + factory.seedElta();
        vm.startPrank(creator);
        elta.approve(address(factory), totalCost);
        factory.createApp("Test", "TEST", 0, "", "", "");
        vm.stopPrank();

        // Check stats updated
        (totalApps,,,) = views.getLaunchStats();
        assertEq(totalApps, 1);
    }

    function test_MultipleApps() public {
        uint256 totalCost = factory.creationFee() + factory.seedElta();

        vm.startPrank(creator);
        elta.approve(address(factory), totalCost * 3);

        uint256 appId1 = factory.createApp("Game1", "GAME1", 0, "", "", "");
        uint256 appId2 = factory.createApp("Game2", "GAME2", 0, "", "", "");
        uint256 appId3 = factory.createApp("Game3", "GAME3", 0, "", "", "");

        vm.stopPrank();

        assertEq(appId1, 0);
        assertEq(appId2, 1);
        assertEq(appId3, 2);
        assertEq(factory.appCount(), 3);

        // Check creator apps (use views contract)
        uint256[] memory creatorApps = views.getCreatorApps(creator);
        assertEq(creatorApps.length, 3);
        assertEq(creatorApps[0], 0);
        assertEq(creatorApps[1], 1);
        assertEq(creatorApps[2], 2);
    }
}
