// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";

contract AppRegistryTwoPhaseHandler is Test {
    AppRegistry public registry;

    constructor(AppRegistry _registry) {
        registry = _registry;
    }

    function registerApp(uint256 rawAppId, uint256 salt) external {
        uint256 appId = rawAppId % 10;
        address ownerSafe = address(uint160(uint256(keccak256(abi.encode("owner", appId, salt)))));
        address split = address(uint160(uint256(keccak256(abi.encode("split", appId, salt)))));
        if (ownerSafe == address(0)) ownerSafe = address(1);
        if (split == address(0)) split = address(2);

        try registry.registerApp(appId, ownerSafe, split, "ipfs://meta") {} catch {}
    }

    function setTokenAndCurve(uint256 rawAppId, uint256 salt) external {
        uint256 appId = rawAppId % 10;
        address token = address(uint160(uint256(keccak256(abi.encode("token", appId, salt)))));
        address curve = address(uint160(uint256(keccak256(abi.encode("curve", appId, salt)))));
        if (token == address(0)) token = address(3);
        if (curve == address(0)) curve = address(4);

        try registry.setTokenAndCurve(appId, token, curve) {} catch {}
    }
}

contract AppRegistryTwoPhaseInvariants is Test {
    AppRegistry public registry;
    AppRegistryTwoPhaseHandler public handler;

    function setUp() public {
        registry = new AppRegistry(makeAddr("gov"), address(0xBEEF));
        handler = new AppRegistryTwoPhaseHandler(registry);

        vm.prank(registry.governance());
        registry.setAppFactory(address(handler));

        targetContract(address(handler));
    }

    function invariant_NoPartialLaunchState() public view {
        for (uint256 appId = 0; appId < 10; ++appId) {
            IAppRegistry.AppInfo memory info = registry.getApp(appId);
            if (info.ownerSafe == address(0)) continue; // not registered

            if (info.tokenLaunched) {
                assertTrue(info.appToken != address(0), "tokenLaunched but appToken==0");
                assertTrue(info.bondingCurve != address(0), "tokenLaunched but curve==0");
            } else {
                assertEq(info.appToken, address(0), "not launched but appToken!=0");
                assertEq(info.bondingCurve, address(0), "not launched but curve!=0");
            }
        }
    }
}

