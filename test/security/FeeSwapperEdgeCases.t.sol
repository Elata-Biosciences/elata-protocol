// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeSwapper} from "../../src/fees/FeeSwapper.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockELTA2 is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract MockTokenIn is ERC20 {
    constructor() ERC20("Mock In", "IN") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract RevertingSplit {
    function onFeeReceived(FeeKind, address, uint256, address) external pure {
        revert("should not be called");
    }
}

contract MockRegistryZeroSplit {
    function getApp(uint256) external pure returns (IAppRegistry.AppInfo memory) {
        return IAppRegistry.AppInfo({
            ownerSafe: address(0x1234),
            contributorSplit: address(0),
            appToken: address(0),
            bondingCurve: address(0),
            metadataURI: "",
            tokenLaunched: false,
            paused: false
        });
    }
}

contract FeeSwapperEdgeCasesTest is Test {
    FeeSwapper swapper;
    MockELTA2 elta;
    MockTokenIn tokenIn;
    AppRegistry registry;

    address admin = makeAddr("admin");
    address governance = makeAddr("governance");
    address treasury = makeAddr("treasury");
    address payer = makeAddr("payer");

    function setUp() public {
        elta = new MockELTA2();
        tokenIn = new MockTokenIn();

        registry = new AppRegistry(governance, address(this));
        swapper = new FeeSwapper(address(elta), admin, governance, treasury, address(registry));

        // appId=1: normal app with a non-reverting split.
        registry.registerApp(1, makeAddr("owner1"), makeAddr("split1"), "ipfs://meta1");

        // appId=2: paused app with a split that would revert if called.
        registry.registerApp(2, makeAddr("owner2"), address(new RevertingSplit()), "ipfs://meta2");
        vm.prank(governance);
        registry.setPaused(2, true);

        // Fund payer and approve swapper for accrue tests.
        tokenIn.transfer(payer, 10_000 ether);
        vm.prank(payer);
        tokenIn.approve(address(swapper), type(uint256).max);
    }

    function test_RevertWhen_SwapRouterNotAllowed() public {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(elta);

        vm.prank(payer);
        vm.expectRevert(FeeSwapper.RouterNotAllowed.selector);
        swapper.swap(1, FeeKind.TRADING_FEE, address(tokenIn), 1 ether, 0, makeAddr("router"), path);
    }

    function test_RevertWhen_SwapPathDoesNotEndInELTA() public {
        // Allow some router address.
        address router = makeAddr("router");
        vm.prank(governance);
        swapper.setRouterAllowed(router, true);

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenIn);

        vm.prank(payer);
        vm.expectRevert(Errors.InvalidAmount.selector);
        swapper.swap(1, FeeKind.TRADING_FEE, address(tokenIn), 1 ether, 0, router, path);
    }

    function test_RevertWhen_SetDefaultTreasuryTakeAbove100Percent() public {
        vm.prank(governance);
        vm.expectRevert(Errors.InvalidAmount.selector);
        swapper.setDefaultTreasuryTakeBps(10_001);
    }

    function test_RevertWhen_SetAppTreasuryTakeAbove100Percent() public {
        vm.prank(governance);
        vm.expectRevert(Errors.InvalidAmount.selector);
        swapper.setAppTreasuryTakeBps(1, 10_001);
    }

    function test_AppRevenuePausedApp_RoutesAllToTreasury() public {
        uint256 amount = 100 ether;
        uint256 treasuryBefore = tokenIn.balanceOf(treasury);

        vm.prank(payer);
        swapper.accrue(2, FeeKind.CONTENT_SALE, address(tokenIn), amount, payer);

        // When paused, the split must never be called; all funds go to treasury.
        assertEq(tokenIn.balanceOf(treasury) - treasuryBefore, amount);
    }

    function test_RevertWhen_AppRevenueMissingContributorSplit() public {
        // AppRegistry prevents registering a zero split, but FeeSwapper still defensively
        // checks this in case governance swaps in a malicious registry implementation.
        FeeSwapper local =
            new FeeSwapper(address(elta), admin, governance, treasury, address(new MockRegistryZeroSplit()));

        vm.startPrank(payer);
        tokenIn.approve(address(local), type(uint256).max);
        vm.expectRevert(Errors.ZeroAddress.selector);
        local.accrue(3, FeeKind.CONTENT_SALE, address(tokenIn), 1 ether, payer);
        vm.stopPrank();
    }

    function test_AppTreasuryTake100Percent_SendsAllToTreasury() public {
        vm.prank(governance);
        swapper.setAppTreasuryTakeBps(1, 10_000);

        uint256 amount = 42 ether;
        uint256 treasuryBefore = tokenIn.balanceOf(treasury);

        vm.prank(payer);
        swapper.accrue(1, FeeKind.OTHER, address(tokenIn), amount, payer);

        assertEq(tokenIn.balanceOf(treasury) - treasuryBefore, amount);
    }
}

