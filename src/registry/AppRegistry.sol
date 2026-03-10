// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppRegistry} from "../interfaces/IAppRegistry.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title AppRegistry
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Canonical mapping from appId -> ownerSafe + contributorSplit (+ optional token/curve).
 * @dev The registry does NOT generate appIds; factories assign them and register them here.
 */
contract AppRegistry is IAppRegistry {
    error OnlyGovernance();
    error OnlyAppFactory();
    error OnlyOwnerSafe();
    error AppNotFound();
    error AlreadyRegistered();
    error TokenAlreadyLaunched();

    address public override appFactory;
    address public override governance;

    mapping(uint256 => AppInfo) internal _apps;
    mapping(uint256 => bool) internal _exists;

    constructor(address _governance, address _appFactory) {
        if (_governance == address(0) || _appFactory == address(0)) revert Errors.ZeroAddress();
        governance = _governance;
        appFactory = _appFactory;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    modifier onlyAppFactory() {
        if (msg.sender != appFactory) revert OnlyAppFactory();
        _;
    }

    modifier onlyOwnerSafe(uint256 appId) {
        address safe = _apps[appId].ownerSafe;
        if (safe == address(0)) revert AppNotFound();
        if (msg.sender != safe) revert OnlyOwnerSafe();
        _;
    }

    function getApp(uint256 appId) external view override returns (AppInfo memory) {
        return _apps[appId];
    }

    function ownerSafeOf(uint256 appId) external view override returns (address) {
        return _apps[appId].ownerSafe;
    }

    function contributorSplitOf(uint256 appId) external view override returns (address) {
        return _apps[appId].contributorSplit;
    }

    function registerApp(uint256 appId, address ownerSafe, address contributorSplit, string calldata metadataURI)
        external
        override
        onlyAppFactory
    {
        if (_exists[appId]) revert AlreadyRegistered();
        if (ownerSafe == address(0) || contributorSplit == address(0)) revert Errors.ZeroAddress();

        _exists[appId] = true;
        _apps[appId] = AppInfo({
            ownerSafe: ownerSafe,
            contributorSplit: contributorSplit,
            appToken: address(0),
            bondingCurve: address(0),
            metadataURI: metadataURI,
            tokenLaunched: false,
            paused: false
        });

        emit AppRegistered(appId, ownerSafe, contributorSplit, metadataURI);
    }

    function setTokenAndCurve(uint256 appId, address appToken, address bondingCurve) external override onlyAppFactory {
        if (!_exists[appId]) revert AppNotFound();
        if (appToken == address(0) || bondingCurve == address(0)) revert Errors.ZeroAddress();

        AppInfo storage info = _apps[appId];
        if (info.tokenLaunched) revert TokenAlreadyLaunched();
        info.appToken = appToken;
        info.bondingCurve = bondingCurve;
        info.tokenLaunched = true;

        emit AppTokenLaunched(appId, appToken, bondingCurve);
    }

    function setPaused(uint256 appId, bool paused) external override onlyGovernance {
        if (!_exists[appId]) revert AppNotFound();
        _apps[appId].paused = paused;
        emit AppPaused(appId, paused);
    }

    function setOwnerSafe(uint256 appId, address newOwnerSafe) external override onlyOwnerSafe(appId) {
        if (newOwnerSafe == address(0)) revert Errors.ZeroAddress();
        address old = _apps[appId].ownerSafe;
        _apps[appId].ownerSafe = newOwnerSafe;
        emit AppOwnerUpdated(appId, old, newOwnerSafe);
    }

    function setMetadataURI(uint256 appId, string calldata newURI) external override onlyOwnerSafe(appId) {
        string memory old = _apps[appId].metadataURI;
        _apps[appId].metadataURI = newURI;
        emit AppMetadataURIUpdated(appId, old, newURI);
    }

    function setContributorSplit(uint256 appId, address newContributorSplit) external override onlyOwnerSafe(appId) {
        if (newContributorSplit == address(0)) revert Errors.ZeroAddress();
        address old = _apps[appId].contributorSplit;
        _apps[appId].contributorSplit = newContributorSplit;
        emit AppContributorSplitUpdated(appId, old, newContributorSplit);
    }

    function setAppFactory(address newFactory) external override onlyGovernance {
        if (newFactory == address(0)) revert Errors.ZeroAddress();
        address old = appFactory;
        appFactory = newFactory;
        emit AppFactoryUpdated(old, newFactory);
    }

    function transferGovernance(address newGovernance) external override onlyGovernance {
        if (newGovernance == address(0)) revert Errors.ZeroAddress();
        address old = governance;
        governance = newGovernance;
        emit GovernanceTransferred(old, newGovernance);
    }
}

