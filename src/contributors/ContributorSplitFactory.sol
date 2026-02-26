// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IContributorSplit} from "../interfaces/IContributorSplit.sol";
import {ContributorSplit} from "./ContributorSplit.sol";
import {Errors} from "../utils/Errors.sol";

/**
 * @title ContributorSplitFactory
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Deploys per-app ContributorSplit instances as EIP-1167 minimal clones.
 */
contract ContributorSplitFactory {
    error OnlyGovernance();
    error OnlyAppFactory();

    address public governance;
    address public appFactory;
    address public immutable implementation;

    uint256 public maxContributors = 200;

    event GovernanceTransferred(address indexed oldGov, address indexed newGov);
    event AppFactoryUpdated(address indexed oldFactory, address indexed newFactory);
    event MaxContributorsUpdated(uint256 oldMax, uint256 newMax);
    event ContributorSplitCreated(uint256 indexed appId, address indexed ownerSafe, address indexed split);

    constructor(address _governance, address _appFactory) {
        if (_governance == address(0) || _appFactory == address(0)) revert Errors.ZeroAddress();
        governance = _governance;
        appFactory = _appFactory;
        implementation = address(new ContributorSplit());
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    modifier onlyAppFactory() {
        if (msg.sender != appFactory) revert OnlyAppFactory();
        _;
    }

    function createSplit(
        uint256 appId,
        address ownerSafe,
        address feeRouter,
        IContributorSplit.Contributor[] calldata initialContributors
    ) external onlyAppFactory returns (address split) {
        if (ownerSafe == address(0) || feeRouter == address(0)) revert Errors.ZeroAddress();

        split = Clones.clone(implementation);
        ContributorSplit(split).initialize(appId, ownerSafe, feeRouter, maxContributors, initialContributors);
        emit ContributorSplitCreated(appId, ownerSafe, split);
    }

    function setMaxContributors(uint256 newMax) external onlyGovernance {
        if (newMax == 0) revert Errors.InvalidAmount();
        uint256 old = maxContributors;
        maxContributors = newMax;
        emit MaxContributorsUpdated(old, newMax);
    }

    function setAppFactory(address newFactory) external onlyGovernance {
        if (newFactory == address(0)) revert Errors.ZeroAddress();
        address old = appFactory;
        appFactory = newFactory;
        emit AppFactoryUpdated(old, newFactory);
    }

    function transferGovernance(address newGov) external onlyGovernance {
        if (newGov == address(0)) revert Errors.ZeroAddress();
        address old = governance;
        governance = newGov;
        emit GovernanceTransferred(old, newGov);
    }
}

