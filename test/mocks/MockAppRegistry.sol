// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppRegistry} from "../../src/interfaces/IAppRegistry.sol";

contract MockAppRegistry is IAppRegistry {
    mapping(uint256 => AppInfo) internal _apps;

    function setApp(uint256 appId, address ownerSafe, address contributorSplit, address appToken, bool tokenLaunched)
        external
    {
        _apps[appId] = AppInfo({
            ownerSafe: ownerSafe,
            contributorSplit: contributorSplit,
            appToken: appToken,
            bondingCurve: address(0),
            metadataURI: "",
            tokenLaunched: tokenLaunched,
            paused: false
        });
    }

    function getApp(uint256 appId) external view returns (AppInfo memory) {
        return _apps[appId];
    }

    function ownerSafeOf(uint256 appId) external view returns (address) {
        return _apps[appId].ownerSafe;
    }

    function contributorSplitOf(uint256 appId) external view returns (address) {
        return _apps[appId].contributorSplit;
    }

    // Unused interface members in tests.
    function appFactory() external pure returns (address) {
        return address(0);
    }

    function governance() external pure returns (address) {
        return address(0);
    }

    function setPaused(uint256, bool) external pure {
        revert("not implemented");
    }

    function setAppFactory(address) external pure {
        revert("not implemented");
    }

    function transferGovernance(address) external pure {
        revert("not implemented");
    }

    function setOwnerSafe(uint256, address) external pure {
        revert("not implemented");
    }

    function setMetadataURI(uint256, string calldata) external pure {
        revert("not implemented");
    }

    function setContributorSplit(uint256, address) external pure {
        revert("not implemented");
    }

    function registerApp(uint256, address, address, string calldata) external pure {
        revert("not implemented");
    }

    function setTokenAndCurve(uint256, address, address) external pure {
        revert("not implemented");
    }
}

