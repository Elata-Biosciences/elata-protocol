// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ELTA} from "elta/ELTA.sol";
import {AppFactory} from "../../src/apps/AppFactory.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {ContributorSplitFactory} from "../../src/contributors/ContributorSplitFactory.sol";
import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";
import {IUniswapV2Router02} from "../../src/interfaces/IUniswapV2Router02.sol";
import {IAppFeeRouter} from "../../src/interfaces/IAppFeeRouter.sol";
import {IAppRewardsDistributor} from "../../src/interfaces/IAppRewardsDistributor.sol";
import {IRewardsDistributor} from "../../src/interfaces/IRewardsDistributor.sol";
import {IElataPoints} from "../../src/interfaces/IElataPoints.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

contract AppFactoryTwoPhaseTest is Test {
    ELTA public elta;
    AppFactory public factory;
    AppRegistry public registry;
    ContributorSplitFactory public splitFactory;

    MockRouter public router;
    MockAppFeeRouter public feeRouter;
    MockXP public xp;
    MockAppRewardsDistributor public appRewards;
    MockRewardsDistributor public rewards;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");

    address public ownerSafe = makeAddr("ownerSafe");
    address public other = makeAddr("other");

    address public mockFeeSwapper = makeAddr("mockFeeSwapper");

    function setUp() public {
        elta = new ELTA(treasury);
        router = new MockRouter();
        feeRouter = new MockAppFeeRouter();
        xp = new MockXP();
        appRewards = new MockAppRewardsDistributor();
        rewards = new MockRewardsDistributor();

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

        registry = new AppRegistry(governance, address(factory));
        splitFactory = new ContributorSplitFactory(governance, address(factory));

        vm.startPrank(admin);
        factory.setAppRegistry(address(registry));
        factory.setContributorSplitFactory(address(splitFactory));
        factory.setFeeSwapper(mockFeeSwapper);
        vm.stopPrank();

        // Fund ownerSafe with enough ELTA for both phases.
        vm.prank(treasury);
        elta.transfer(ownerSafe, 10_000 ether);
    }

    function test_PhaseA_CreateAppWithoutToken_RegistersAppAndStoresContributorSplit() public {
        uint256 fee = factory.creationFee();
        vm.startPrank(ownerSafe);
        elta.approve(address(factory), fee);

        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: ownerSafe, shares: 10_000});

        (uint256 appId, address split) = factory.createAppWithoutToken(ownerSafe, "ipfs://meta", contributors);
        vm.stopPrank();

        assertEq(appId, 0);
        assertTrue(split != address(0));

        AppFactory.App memory app = factory.getApp(appId);
        assertEq(app.ownerSafe, ownerSafe);
        assertEq(app.contributorSplit, split);
        assertEq(app.token, address(0));
        assertEq(app.curve, address(0));
        assertFalse(app.tokenLaunched);

        IAppRegistry.AppInfo memory info = registry.getApp(appId);
        assertEq(info.ownerSafe, ownerSafe);
        assertEq(info.contributorSplit, split);
        assertEq(info.metadataURI, "ipfs://meta");
        assertFalse(info.tokenLaunched);
    }

    function test_PhaseB_LaunchTokenForApp_OnlyOwnerSafe() public {
        uint256 fee = factory.creationFee();

        vm.startPrank(ownerSafe);
        elta.approve(address(factory), fee);
        (uint256 appId,) = factory.createAppWithoutToken(ownerSafe, "", new IContributorSplit.Contributor[](0));
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert(AppFactory.OnlyOwnerSafe.selector);
        factory.launchTokenForApp(appId, "Name", "SYM", 0, new address[](0));
    }

    function test_PhaseB_LaunchTokenForApp_CollectsSeedAndSetsRegistry() public {
        uint256 fee = factory.creationFee();
        uint256 seed = factory.seedElta();

        vm.startPrank(ownerSafe);
        elta.approve(address(factory), fee + seed);
        (uint256 appId,) =
            factory.createAppWithoutToken(ownerSafe, "ipfs://meta", new IContributorSplit.Contributor[](0));

        (address token, address curve) = factory.launchTokenForApp(appId, "MyApp", "APP", 0, new address[](0));
        vm.stopPrank();

        assertTrue(token != address(0));
        assertTrue(curve != address(0));

        AppFactory.App memory app = factory.getApp(appId);
        assertEq(app.token, token);
        assertEq(app.curve, curve);
        assertTrue(app.tokenLaunched);

        IAppRegistry.AppInfo memory info = registry.getApp(appId);
        assertEq(info.appToken, token);
        assertEq(info.bondingCurve, curve);
        assertTrue(info.tokenLaunched);

        // Sanity check token metadata.
        assertEq(AppToken(token).name(), "MyApp");
        assertEq(AppToken(token).symbol(), "APP");
    }

    function test_PhaseB_RevertWhen_TokenAlreadyLaunched() public {
        uint256 fee = factory.creationFee();
        uint256 seed = factory.seedElta();

        vm.startPrank(ownerSafe);
        elta.approve(address(factory), fee + seed * 2);
        (uint256 appId,) = factory.createAppWithoutToken(ownerSafe, "", new IContributorSplit.Contributor[](0));
        factory.launchTokenForApp(appId, "MyApp", "APP", 0, new address[](0));

        vm.expectRevert(AppFactory.TokenAlreadyLaunched.selector);
        factory.launchTokenForApp(appId, "MyApp", "APP", 0, new address[](0));
        vm.stopPrank();
    }
}

