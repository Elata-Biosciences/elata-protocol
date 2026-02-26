// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeKind} from "../fees/FeeKind.sol";
import {IContributorSplit} from "../interfaces/IContributorSplit.sol";
import {Errors} from "../utils/Errors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ContributorSplit
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Pull-based revenue split for a bounded set of app contributors.
 * @dev To avoid complex historical accounting bugs, contributors can be reconfigured only
 *      until the first payment is received. For later changes, deploy a new split and update
 *      AppRegistry to point to it for future revenues.
 */
contract ContributorSplit is IContributorSplit {
    using SafeERC20 for IERC20;

    error OnlyOwnerSafe();
    error OnlyFeeRouter();
    error AlreadyInitialized();
    error NotInitialized();
    error ContributorsLocked();
    error DuplicateContributor();
    error NoShares();

    uint256 public override appId;
    address public override ownerSafe;
    address public override feeRouter;

    uint256 public override maxContributors;
    uint256 internal _contributorCount;

    uint64 public override totalShares;
    mapping(address => uint64) internal _shares;

    // PaymentSplitter-style accounting per ERC20 asset
    mapping(address => uint256) internal _totalReleased; // asset -> total released
    mapping(address => mapping(address => uint256)) internal _released; // asset -> account -> released

    // Contributor list for cleanup on reconfigure
    address[] internal _contributors;

    // Duplicate detection for setContributors()
    uint256 internal _configNonce;
    mapping(address => uint256) internal _seenAtNonce;

    bool internal _initialized;
    bool internal _contributorsLocked;

    modifier onlyOwnerSafe() {
        if (!_initialized) revert NotInitialized();
        if (msg.sender != ownerSafe) revert OnlyOwnerSafe();
        _;
    }

    modifier onlyFeeRouter() {
        if (!_initialized) revert NotInitialized();
        if (msg.sender != feeRouter) revert OnlyFeeRouter();
        _;
    }

    function initialize(
        uint256 _appId,
        address _ownerSafe,
        address _feeRouter,
        uint256 _maxContributors,
        Contributor[] calldata initialContributors
    ) external {
        if (_initialized) revert AlreadyInitialized();
        if (_ownerSafe == address(0) || _feeRouter == address(0)) revert Errors.ZeroAddress();
        if (_maxContributors == 0) revert Errors.InvalidAmount();

        _initialized = true;
        appId = _appId;
        ownerSafe = _ownerSafe;
        feeRouter = _feeRouter;
        maxContributors = _maxContributors;

        if (initialContributors.length > 0) {
            _setContributors(initialContributors);
        }
    }

    function contributorCount() external view override returns (uint256) {
        return _contributorCount;
    }

    function sharesOf(address account) external view override returns (uint64) {
        return _shares[account];
    }

    function setOwnerSafe(address newOwnerSafe) external onlyOwnerSafe {
        if (newOwnerSafe == address(0)) revert Errors.ZeroAddress();
        address old = ownerSafe;
        ownerSafe = newOwnerSafe;
        emit OwnerSafeUpdated(appId, old, newOwnerSafe);
    }

    function setFeeRouter(address newFeeRouter) external onlyOwnerSafe {
        if (newFeeRouter == address(0)) revert Errors.ZeroAddress();
        address old = feeRouter;
        feeRouter = newFeeRouter;
        emit FeeRouterUpdated(appId, old, newFeeRouter);
    }

    function setContributors(Contributor[] calldata contributors) external override onlyOwnerSafe {
        if (_contributorsLocked) revert ContributorsLocked();
        _setContributors(contributors);
    }

    function _setContributors(Contributor[] calldata contributors) internal {
        if (contributors.length == 0) revert Errors.InvalidAmount();
        if (contributors.length > maxContributors) revert Errors.CapExceeded();

        // Clear prior set
        uint256 oldLen = _contributors.length;
        for (uint256 i; i < oldLen; ++i) {
            _shares[_contributors[i]] = 0;
        }
        delete _contributors;

        _configNonce++;
        uint256 nonce = _configNonce;

        uint64 sumShares;
        uint256 len = contributors.length;
        for (uint256 i; i < len; ++i) {
            address account = contributors[i].account;
            uint64 shares_ = contributors[i].shares;

            if (account == address(0)) revert Errors.ZeroAddress();
            if (shares_ == 0) revert NoShares();
            if (_seenAtNonce[account] == nonce) revert DuplicateContributor();
            _seenAtNonce[account] = nonce;

            _shares[account] = shares_;
            _contributors.push(account);
            sumShares += shares_;

            emit ContributorSet(appId, account, shares_);
        }

        totalShares = sumShares;
        _contributorCount = len;
        emit ContributorsReconfigured(appId, len);
    }

    function onFeeReceived(FeeKind kind, address asset, uint256 amount, address from) external override onlyFeeRouter {
        if (amount > 0) {
            _contributorsLocked = true;
        }
        emit PaymentReceived(appId, kind, asset, amount, from);
    }

    function releasable(address asset, address account) external view override returns (uint256) {
        uint64 shares_ = _shares[account];
        if (shares_ == 0 || totalShares == 0) return 0;

        uint256 totalReceived = _totalReceived(asset);
        uint256 alreadyReleased = _released[asset][account];
        uint256 payment = (totalReceived * uint256(shares_)) / uint256(totalShares);

        if (payment <= alreadyReleased) return 0;
        return payment - alreadyReleased;
    }

    function release(address asset, address account) external override {
        uint64 shares_ = _shares[account];
        if (shares_ == 0 || totalShares == 0) return;

        uint256 totalReceived = _totalReceived(asset);
        uint256 alreadyReleased = _released[asset][account];
        uint256 payment = (totalReceived * uint256(shares_)) / uint256(totalShares);

        if (payment <= alreadyReleased) return;
        uint256 due = payment - alreadyReleased;

        _released[asset][account] = alreadyReleased + due;
        _totalReleased[asset] += due;

        IERC20(asset).safeTransfer(account, due);
        emit PaymentReleased(appId, asset, account, due);
    }

    function _totalReceived(address asset) internal view returns (uint256) {
        // PaymentSplitter invariant: totalReceived = currentBalance + totalReleased
        return IERC20(asset).balanceOf(address(this)) + _totalReleased[asset];
    }
}

