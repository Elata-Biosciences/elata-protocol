// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";

contract AppRegistryTest is Test {
    AppRegistry public registry;

    address public governance = makeAddr("governance");
    address public appFactory = makeAddr("appFactory");

    address public ownerSafe = makeAddr("ownerSafe");
    address public other = makeAddr("other");

    function setUp() public {
        registry = new AppRegistry(governance, appFactory);
    }

    function test_RegisterApp_OnlyAppFactory() public {
        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyAppFactory.selector);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "ipfs://x");
    }

    function test_RegisterApp_StoresInfoAndEmits() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "ipfs://x");

        IAppRegistry.AppInfo memory info = registry.getApp(1);
        assertEq(info.ownerSafe, ownerSafe);
        assertEq(info.metadataURI, "ipfs://x");
        assertFalse(info.tokenLaunched);
        assertFalse(info.paused);
        assertEq(info.appToken, address(0));
        assertEq(info.bondingCurve, address(0));
    }

    function test_SetTokenAndCurve_OnlyAppFactory() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyAppFactory.selector);
        registry.setTokenAndCurve(1, makeAddr("token"), makeAddr("curve"));
    }

    function test_SetTokenAndCurve_SetsFields() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        address token = makeAddr("token");
        address curve = makeAddr("curve");

        vm.prank(appFactory);
        registry.setTokenAndCurve(1, token, curve);

        IAppRegistry.AppInfo memory info = registry.getApp(1);
        assertEq(info.appToken, token);
        assertEq(info.bondingCurve, curve);
        assertTrue(info.tokenLaunched);
    }

    function test_RevertWhen_SetTokenAndCurve_Twice() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(appFactory);
        registry.setTokenAndCurve(1, makeAddr("token"), makeAddr("curve"));

        vm.prank(appFactory);
        vm.expectRevert(AppRegistry.TokenAlreadyLaunched.selector);
        registry.setTokenAndCurve(1, makeAddr("token2"), makeAddr("curve2"));
    }

    function test_SetOwnerSafe_OnlyOwnerSafe() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyOwnerSafe.selector);
        registry.setOwnerSafe(1, makeAddr("newOwner"));
    }

    function test_SetOwnerSafe_Updates() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        address newOwner = makeAddr("newOwner");
        vm.prank(ownerSafe);
        registry.setOwnerSafe(1, newOwner);

        assertEq(registry.ownerSafeOf(1), newOwner);
    }

    function test_SetContributorSplit_OnlyOwnerSafe() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyOwnerSafe.selector);
        registry.setContributorSplit(1, makeAddr("newSplit"));
    }

    function test_SetMetadataURI_OnlyOwnerSafe() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyOwnerSafe.selector);
        registry.setMetadataURI(1, "ipfs://new");
    }

    function test_SetPaused_OnlyGovernance() public {
        vm.prank(appFactory);
        registry.registerApp(1, ownerSafe, makeAddr("split"), "");

        vm.prank(other);
        vm.expectRevert(AppRegistry.OnlyGovernance.selector);
        registry.setPaused(1, true);
    }

    function test_TransferGovernance() public {
        address newGov = makeAddr("newGov");
        vm.prank(governance);
        registry.transferGovernance(newGov);
        assertEq(registry.governance(), newGov);
    }

    function test_GovernanceCanUpdateAppFactory() public {
        address newFactory = makeAddr("newFactory");
        vm.prank(governance);
        registry.setAppFactory(newFactory);
        assertEq(registry.appFactory(), newFactory);
    }

    function test_RevertOn_ZeroAddressConstructor() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new AppRegistry(address(0), appFactory);
    }
}

