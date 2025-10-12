// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRewardsDistributor } from "../interfaces/IRewardsDistributor.sol";

/**
 * @title AppFeeRouter
 * @author Elata Protocol
 * @notice Global fee collection router that forwards trading fees to RewardsDistributor
 * @dev Single instance used by all bonding curves for consistent fee handling
 *
 * Key Features:
 * - Collects ELTA fees from bonding curve trades
 * - Forwards immediately to RewardsDistributor for 70/15/15 split
 * - Configurable fee rate (capped at 5%)
 * - Governance-controlled adjustments
 *
 * Usage:
 * 1. Bonding curve computes fee from trade amount
 * 2. Bonding curve calls takeAndForwardFee()
 * 3. Router pulls fee and deposits to RewardsDistributor
 * 4. RewardsDistributor splits 70% app / 15% veELTA / 15% treasury
 */
contract AppFeeRouter {
    using SafeERC20 for IERC20;

    error OnlyGovernance();
    error FeeTooHigh();

    IERC20 public immutable ELTA;
    IRewardsDistributor public immutable rewardsDistributor;
    address public governance;

    /// @notice Fee rate in basis points (100 = 1.00%)
    uint256 public feeBps = 100;

    /// @notice Maximum allowed fee (500 = 5%)
    uint256 public constant MAX_FEE_BPS = 500;

    event FeeForwarded(
        address indexed source, address indexed payer, uint256 grossAmount, uint256 fee
    );
    event FeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);

    /**
     * @notice Initialize fee router
     * @param _elta ELTA token address
     * @param _rewardsDistributor RewardsDistributor address for depositing fees
     * @param _governance Governance address for fee adjustments
     */
    constructor(IERC20 _elta, IRewardsDistributor _rewardsDistributor, address _governance) {
        require(address(_elta) != address(0), "Zero ELTA");
        require(address(_rewardsDistributor) != address(0), "Zero RD");
        require(_governance != address(0), "Zero gov");

        ELTA = _elta;
        rewardsDistributor = _rewardsDistributor;
        governance = _governance;
    }

    /**
     * @notice Collect fee from payer and forward to RewardsDistributor
     * @dev Called by bonding curve after computing gross trade amount
     * @param payer Address paying the fee (typically the trader)
     * @param grossAmount Gross trade amount (used for fee calculation context)
     */
    function takeAndForwardFee(address payer, uint256 grossAmount) external {
        uint256 fee = (grossAmount * feeBps) / 10_000;
        if (fee == 0) return;

        ELTA.safeTransferFrom(payer, address(this), fee);
        ELTA.approve(address(rewardsDistributor), fee);
        rewardsDistributor.deposit(fee);

        emit FeeForwarded(msg.sender, payer, grossAmount, fee);
    }

    /**
     * @notice Update fee rate (governance only)
     * @param newBps New fee rate in basis points
     */
    function setFeeBps(uint256 newBps) external {
        if (msg.sender != governance) revert OnlyGovernance();
        if (newBps > MAX_FEE_BPS) revert FeeTooHigh();

        emit FeeBpsUpdated(feeBps, newBps);
        feeBps = newBps;
    }

    /**
     * @notice Transfer governance to new address
     * @param newGovernance New governance address
     */
    function transferGovernance(address newGovernance) external {
        if (msg.sender != governance) revert OnlyGovernance();
        require(newGovernance != address(0), "Zero address");

        emit GovernanceTransferred(governance, newGovernance);
        governance = newGovernance;
    }

    /**
     * @notice Calculate fee for a given amount
     * @param amount Amount to calculate fee for
     * @return fee Fee amount
     */
    function calculateFee(uint256 amount) external view returns (uint256 fee) {
        fee = (amount * feeBps) / 10_000;
    }
}
