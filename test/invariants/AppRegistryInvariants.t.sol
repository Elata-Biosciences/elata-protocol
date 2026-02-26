// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppRegistry} from "../../src/registry/AppRegistry.sol";
import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";

contract AppRegistryHandler is Test {
    AppRegistry public registry;

    // Track first launched token/curve per appId (0 means unset).
    mapping(uint256 => address) public ghost_token;
    mapping(uint256 => address) public ghost_curve;

    constructor(AppRegistry _registry) {
        registry = _registry;
    }

    function registerApp(uint256 rawAppId) external {
        uint256 appId = rawAppId % 10;
        address ownerSafe = address(uint160(uint256(keccak256(abi.encode("owner", appId)))));
        address split = address(uint160(uint256(keccak256(abi.encode("split", appId)))));

        // Avoid zero addresses in case of edge values.
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

        // Only record on the first successful launch.
        try registry.setTokenAndCurve(appId, token, curve) {
            if (ghost_token[appId] == address(0)) {
                ghost_token[appId] = token;
                ghost_curve[appId] = curve;
            }
        } catch {}
    }
}

contract AppRegistryInvariants is Test {
    AppRegistry public registry;
    AppRegistryHandler public handler;

    function setUp() public {
        // appFactory is the handler itself.
        registry = new AppRegistry(makeAddr("gov"), address(0xBEEF));
        handler = new AppRegistryHandler(registry);

        // Set the registry's appFactory to the handler (governance-only).
        vm.prank(registry.governance());
        registry.setAppFactory(address(handler));

        targetContract(address(handler));
    }

    function invariant_TokenLaunchIsMonotonicAndImmutable() public view {
        for (uint256 appId = 0; appId < 10; ++appId) {
            address token = handler.ghost_token(appId);
            address curve = handler.ghost_curve(appId);

            IAppRegistry.AppInfo memory info = registry.getApp(appId);

            if (token != address(0)) {
                // Once launched, flags and addresses must remain set.
                assertTrue(info.tokenLaunched, "tokenLaunched flipped false");
                assertEq(info.appToken, token, "appToken changed after launch");
                assertEq(info.bondingCurve, curve, "bondingCurve changed after launch");
            }
        }
    }
}

