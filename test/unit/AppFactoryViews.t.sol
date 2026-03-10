// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AppFactoryViews} from "../../src/apps/AppFactoryViews.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock AppFactory that implements IAppFactoryState interface
contract MockAppFactory {
    struct App {
        address creator;
        address token;
        address vault;
        address curve;
        address vestingWallet;
        address ecosystemVault;
        address pair;
        address locker;
        uint64 createdAt;
        uint64 graduatedAt;
        bool graduated;
        uint256 totalRaised;
        uint256 finalSupply;
        bool tokenLaunched;
        address ownerSafe;
        address contributorSplit;
    }

    App[] public appList;
    mapping(address => uint256) public tokenToAppIdMap;

    uint256 public seedEltaValue = 100 ether;
    uint256 public creationFeeValue = 10 ether;
    uint256 public targetRaisedEltaValue = 42_000 ether;
    uint256 public defaultSupplyValue = 10_000_000 ether;
    uint256 public lpLockDurationValue = 730 days;
    uint8 public defaultDecimalsValue = 18;
    uint256 public protocolFeeRateValue = 100; // 1%

    function addApp(
        address creator,
        address token,
        address vault,
        address curve,
        address vestingWallet,
        address ecosystemVault,
        address pair,
        address locker,
        uint64 createdAt,
        uint64 graduatedAt,
        bool graduated,
        uint256 totalRaised,
        uint256 finalSupply
    ) external returns (uint256 appId) {
        appId = appList.length;
        appList.push(
            App({
                creator: creator,
                token: token,
                vault: vault,
                curve: curve,
                vestingWallet: vestingWallet,
                ecosystemVault: ecosystemVault,
                pair: pair,
                locker: locker,
                createdAt: createdAt,
                graduatedAt: graduatedAt,
                graduated: graduated,
                totalRaised: totalRaised,
                finalSupply: finalSupply,
                tokenLaunched: token != address(0),
                ownerSafe: creator,
                contributorSplit: address(0)
            })
        );
        if (token != address(0)) {
            tokenToAppIdMap[token] = appId;
        }
    }

    function appCount() external view returns (uint256) {
        return appList.length;
    }

    function apps(uint256 appId)
        external
        view
        returns (
            address creator,
            address token,
            address vault,
            address curve,
            address vestingWallet,
            address ecosystemVault,
            address pair,
            address locker,
            uint64 createdAt,
            uint64 graduatedAt,
            bool graduated,
            uint256 totalRaised,
            uint256 finalSupply,
            bool tokenLaunched,
            address ownerSafe,
            address contributorSplit,
            string memory metadataURI
        )
    {
        require(appId < appList.length, "Invalid app ID");
        App storage app = appList[appId];
        creator = app.creator;
        token = app.token;
        vault = app.vault;
        curve = app.curve;
        vestingWallet = app.vestingWallet;
        ecosystemVault = app.ecosystemVault;
        pair = app.pair;
        locker = app.locker;
        createdAt = app.createdAt;
        graduatedAt = app.graduatedAt;
        graduated = app.graduated;
        totalRaised = app.totalRaised;
        finalSupply = app.finalSupply;
        tokenLaunched = app.tokenLaunched;
        ownerSafe = app.ownerSafe;
        contributorSplit = app.contributorSplit;
        metadataURI = "";
    }

    function tokenToAppId(address token) external view returns (uint256) {
        return tokenToAppIdMap[token];
    }

    function seedElta() external view returns (uint256) {
        return seedEltaValue;
    }

    function creationFee() external view returns (uint256) {
        return creationFeeValue;
    }

    function targetRaisedElta() external view returns (uint256) {
        return targetRaisedEltaValue;
    }

    function defaultSupply() external view returns (uint256) {
        return defaultSupplyValue;
    }

    function lpLockDuration() external view returns (uint256) {
        return lpLockDurationValue;
    }

    function defaultDecimals() external view returns (uint8) {
        return defaultDecimalsValue;
    }

    function protocolFeeRate() external view returns (uint256) {
        return protocolFeeRateValue;
    }

    // Setters for testing
    function setParameters(
        uint256 _seedElta,
        uint256 _creationFee,
        uint256 _targetRaised,
        uint256 _defaultSupply,
        uint256 _lpLockDuration,
        uint8 _defaultDecimals,
        uint256 _protocolFeeRate
    ) external {
        seedEltaValue = _seedElta;
        creationFeeValue = _creationFee;
        targetRaisedEltaValue = _targetRaised;
        defaultSupplyValue = _defaultSupply;
        lpLockDurationValue = _lpLockDuration;
        defaultDecimalsValue = _defaultDecimals;
        protocolFeeRateValue = _protocolFeeRate;
    }
}

/**
 * @title AppFactoryViewsTest
 * @notice Unit tests for AppFactoryViews helper contract
 * @dev Tests view functions, gas usage, and DoS resistance
 */
contract AppFactoryViewsTest is Test {
    AppFactoryViews public views;
    MockAppFactory public factory;

    address public creator1 = makeAddr("creator1");
    address public creator2 = makeAddr("creator2");
    address public creator3 = makeAddr("creator3");

    function setUp() public {
        factory = new MockAppFactory();
        views = new AppFactoryViews(address(factory));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Deployment() public view {
        assertEq(views.factory(), address(factory));
    }

    function test_RevertWhen_DeployWithZeroFactory() public {
        vm.expectRevert("Zero address");
        new AppFactoryViews(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION ACCURACY
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetApp_ReturnsCorrectData() public {
        address token = makeAddr("token");
        address vault = makeAddr("vault");
        address curve = makeAddr("curve");
        address vestingWallet = makeAddr("vesting");
        address ecosystemVault = makeAddr("ecosystem");
        address pair = makeAddr("pair");
        address locker = makeAddr("locker");
        uint64 createdAt = uint64(block.timestamp);
        uint64 graduatedAt = uint64(block.timestamp + 1 days);
        bool graduated = true;
        uint256 totalRaised = 50_000 ether;
        uint256 finalSupply = 10_000_000 ether;

        factory.addApp(
            creator1,
            token,
            vault,
            curve,
            vestingWallet,
            ecosystemVault,
            pair,
            locker,
            createdAt,
            graduatedAt,
            graduated,
            totalRaised,
            finalSupply
        );

        AppFactoryViews.App memory app = views.getApp(0);

        assertEq(app.creator, creator1);
        assertEq(app.token, token);
        assertEq(app.vault, vault);
        assertEq(app.curve, curve);
        assertEq(app.vestingWallet, vestingWallet);
        assertEq(app.ecosystemVault, ecosystemVault);
        assertEq(app.pair, pair);
        assertEq(app.locker, locker);
        assertEq(app.createdAt, createdAt);
        assertEq(app.graduatedAt, graduatedAt);
        assertEq(app.graduated, graduated);
        assertEq(app.totalRaised, totalRaised);
        assertEq(app.finalSupply, finalSupply);
    }

    function test_GetApp_InvalidAppIdReverts() public {
        // No apps exist
        vm.expectRevert();
        views.getApp(0);

        // Add one app
        factory.addApp(
            creator1,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        // App 0 works
        views.getApp(0);

        // App 1 doesn't exist
        vm.expectRevert();
        views.getApp(1);
    }

    function test_GetCreatorApps_ReturnsAllCreatorApps() public {
        // Creator1 makes 3 apps
        factory.addApp(
            creator1,
            makeAddr("t1"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator1,
            makeAddr("t2"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator1,
            makeAddr("t3"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        // Creator2 makes 2 apps
        factory.addApp(
            creator2,
            makeAddr("t4"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator2,
            makeAddr("t5"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        uint256[] memory creator1Apps = views.getCreatorApps(creator1);
        uint256[] memory creator2Apps = views.getCreatorApps(creator2);

        assertEq(creator1Apps.length, 3);
        assertEq(creator1Apps[0], 0);
        assertEq(creator1Apps[1], 1);
        assertEq(creator1Apps[2], 2);

        assertEq(creator2Apps.length, 2);
        assertEq(creator2Apps[0], 3);
        assertEq(creator2Apps[1], 4);
    }

    function test_GetCreatorApps_EmptyForNewAddress() public {
        // Add some apps
        factory.addApp(
            creator1,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        // Creator2 has no apps
        uint256[] memory creator2Apps = views.getCreatorApps(creator2);
        assertEq(creator2Apps.length, 0);
    }

    function test_GetAppIdFromToken_ReturnsCorrectId() public {
        address token1 = makeAddr("token1");
        address token2 = makeAddr("token2");

        factory.addApp(
            creator1, token1, address(0), address(0), address(0), address(0), address(0), address(0), 0, 0, false, 0, 0
        );
        factory.addApp(
            creator2, token2, address(0), address(0), address(0), address(0), address(0), address(0), 0, 0, false, 0, 0
        );

        assertEq(views.getAppIdFromToken(token1), 0);
        assertEq(views.getAppIdFromToken(token2), 1);
    }

    function test_GetTotalCreationCost_CalculatesCorrectly() public view {
        uint256 totalCost = views.getTotalCreationCost();
        uint256 expected = factory.seedEltaValue() + factory.creationFeeValue();

        assertEq(totalCost, expected);
        assertEq(totalCost, 110 ether); // 100 + 10
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PARAMETER VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetParameters_AllFieldsAccurate() public view {
        (
            uint256 seed,
            uint256 creation,
            uint256 target,
            uint256 supply,
            uint256 lpLock,
            uint8 decimals,
            uint256 protocolFee
        ) = views.getParameters();

        assertEq(seed, 100 ether);
        assertEq(creation, 10 ether);
        assertEq(target, 42_000 ether);
        assertEq(supply, 10_000_000 ether);
        assertEq(lpLock, 730 days);
        assertEq(decimals, 18);
        assertEq(protocolFee, 100);
    }

    function test_GetParameters_ReflectsUpdates() public {
        // Update factory parameters
        factory.setParameters(200 ether, 20 ether, 50_000 ether, 20_000_000 ether, 365 days, 8, 200);

        (
            uint256 seed,
            uint256 creation,
            uint256 target,
            uint256 supply,
            uint256 lpLock,
            uint8 decimals,
            uint256 protocolFee
        ) = views.getParameters();

        assertEq(seed, 200 ether);
        assertEq(creation, 20 ether);
        assertEq(target, 50_000 ether);
        assertEq(supply, 20_000_000 ether);
        assertEq(lpLock, 365 days);
        assertEq(decimals, 8);
        assertEq(protocolFee, 200);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATISTICS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetGraduatedApps_OnlyIncludesGraduated() public {
        // Add 5 apps, 2 graduated
        factory.addApp(
            creator1,
            makeAddr("t1"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator1,
            makeAddr("t2"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            uint64(block.timestamp),
            true,
            50_000 ether,
            10_000_000 ether
        );
        factory.addApp(
            creator2,
            makeAddr("t3"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator2,
            makeAddr("t4"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            uint64(block.timestamp),
            true,
            45_000 ether,
            10_000_000 ether
        );
        factory.addApp(
            creator3,
            makeAddr("t5"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        uint256[] memory graduated = views.getGraduatedApps();

        assertEq(graduated.length, 2);
        assertEq(graduated[0], 1); // Second app
        assertEq(graduated[1], 3); // Fourth app
    }

    function test_GetGraduatedApps_EmptyWhenNoneGraduated() public {
        // Add non-graduated apps
        factory.addApp(
            creator1,
            makeAddr("t1"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator2,
            makeAddr("t2"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        uint256[] memory graduated = views.getGraduatedApps();
        assertEq(graduated.length, 0);
    }

    function test_GetLaunchStats_Accurate() public {
        // Add apps with varying states
        factory.addApp(
            creator1,
            makeAddr("t1"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );
        factory.addApp(
            creator1,
            makeAddr("t2"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            uint64(block.timestamp),
            true,
            50_000 ether,
            10_000_000 ether
        );
        factory.addApp(
            creator2,
            makeAddr("t3"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            uint64(block.timestamp),
            true,
            45_000 ether,
            10_000_000 ether
        );

        (uint256 totalApps, uint256 graduatedApps, uint256 totalValueLocked, uint256 totalFeesCollected) =
            views.getLaunchStats();

        assertEq(totalApps, 3);
        assertEq(graduatedApps, 2);
        assertEq(totalValueLocked, 95_000 ether); // 50k + 45k
        assertEq(totalFeesCollected, 2 * factory.creationFeeValue()); // Approximation based on graduated apps
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS AND DOS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetCreatorApps_GasWithManyApps() public {
        // Add 100 apps for creator1
        for (uint256 i = 0; i < 100; i++) {
            factory.addApp(
                creator1,
                makeAddr(string(abi.encodePacked("token", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                0,
                false,
                0,
                0
            );
        }

        // Add 50 apps for other creators to mix things up
        for (uint256 i = 0; i < 50; i++) {
            factory.addApp(
                creator2,
                makeAddr(string(abi.encodePacked("other", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                0,
                false,
                0,
                0
            );
        }

        uint256 gasBefore = gasleft();
        uint256[] memory creator1Apps = views.getCreatorApps(creator1);
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(creator1Apps.length, 100);
        console2.log("Gas used for 100 apps among 150 total:", gasUsed);

        // Gas should be reasonable (< 5M for 150 apps)
        assertLt(gasUsed, 5_000_000);
    }

    function test_GetGraduatedApps_GasWithManyApps() public {
        // Add 100 apps, 50 graduated
        for (uint256 i = 0; i < 100; i++) {
            bool isGraduated = i % 2 == 0;
            factory.addApp(
                creator1,
                makeAddr(string(abi.encodePacked("token", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                isGraduated ? uint64(block.timestamp) : 0,
                isGraduated,
                isGraduated ? 50_000 ether : 0,
                isGraduated ? 10_000_000 ether : 0
            );
        }

        uint256 gasBefore = gasleft();
        uint256[] memory graduatedApps = views.getGraduatedApps();
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(graduatedApps.length, 50);
        console2.log("Gas used for 50 graduated apps among 100 total:", gasUsed);

        assertLt(gasUsed, 5_000_000);
    }

    function test_GetLaunchStats_GasWithManyApps() public {
        // Add 100 apps
        for (uint256 i = 0; i < 100; i++) {
            bool graduated = i % 3 == 0;
            factory.addApp(
                creator1,
                makeAddr(string(abi.encodePacked("token", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                graduated ? uint64(block.timestamp) : 0,
                graduated,
                graduated ? 50_000 ether : 0,
                graduated ? 10_000_000 ether : 0
            );
        }

        uint256 gasBefore = gasleft();
        (uint256 totalApps, uint256 graduatedApps, uint256 tvl, uint256 fees) = views.getLaunchStats();
        uint256 gasUsed = gasBefore - gasleft();

        assertEq(totalApps, 100);
        assertGt(graduatedApps, 0);
        console2.log("Gas used for getLaunchStats with 100 apps:", gasUsed);

        assertLt(gasUsed, 5_000_000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzz_GetApp_ValidAppIds(uint8 numApps, uint8 queryIndex) public {
        numApps = uint8(bound(numApps, 1, 50));
        queryIndex = uint8(bound(queryIndex, 0, numApps - 1));

        // Add apps
        for (uint8 i = 0; i < numApps; i++) {
            factory.addApp(
                i % 2 == 0 ? creator1 : creator2,
                makeAddr(string(abi.encodePacked("token", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                uint64(block.timestamp + i),
                0,
                false,
                0,
                0
            );
        }

        // Query should work for any valid index
        AppFactoryViews.App memory app = views.getApp(queryIndex);
        assertEq(app.createdAt, uint64(block.timestamp + queryIndex));
    }

    function testFuzz_GetCreatorApps_MultipleCreators(uint8 numCreator1, uint8 numCreator2) public {
        numCreator1 = uint8(bound(numCreator1, 0, 25));
        numCreator2 = uint8(bound(numCreator2, 0, 25));

        // Add creator1 apps
        for (uint8 i = 0; i < numCreator1; i++) {
            factory.addApp(
                creator1,
                makeAddr(string(abi.encodePacked("c1t", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                0,
                false,
                0,
                0
            );
        }

        // Add creator2 apps
        for (uint8 i = 0; i < numCreator2; i++) {
            factory.addApp(
                creator2,
                makeAddr(string(abi.encodePacked("c2t", i))),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0,
                0,
                false,
                0,
                0
            );
        }

        uint256[] memory c1Apps = views.getCreatorApps(creator1);
        uint256[] memory c2Apps = views.getCreatorApps(creator2);

        assertEq(c1Apps.length, numCreator1);
        assertEq(c2Apps.length, numCreator2);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetApp_AllZeroValues() public {
        factory.addApp(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        AppFactoryViews.App memory app = views.getApp(0);

        assertEq(app.creator, address(0));
        assertEq(app.token, address(0));
        assertEq(app.graduated, false);
        assertEq(app.totalRaised, 0);
    }

    function test_GetCreatorApps_ZeroAddress() public {
        // Add app with zero creator
        factory.addApp(
            address(0),
            makeAddr("t1"),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            0,
            0,
            false,
            0,
            0
        );

        uint256[] memory zeroApps = views.getCreatorApps(address(0));
        assertEq(zeroApps.length, 1);
        assertEq(zeroApps[0], 0);
    }

    function test_GetLaunchStats_NoApps() public view {
        (uint256 totalApps, uint256 graduatedApps, uint256 tvl, uint256 fees) = views.getLaunchStats();

        assertEq(totalApps, 0);
        assertEq(graduatedApps, 0);
        assertEq(tvl, 0);
        assertEq(fees, 0);
    }
}
