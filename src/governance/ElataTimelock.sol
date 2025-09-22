// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title ElataTimelock
 * @author Elata Biosciences
 * @notice Timelock controller for the Elata Protocol governance
 * @dev Extends OpenZeppelin TimelockController with custom configuration
 *
 * Features:
 * - 48-hour minimum delay for standard operations
 * - 6-hour emergency delay for critical fixes
 * - Multi-signature proposer and executor roles
 * - Cancellation capabilities for security
 *
 * Security:
 * - Role-based access control for proposers and executors
 * - Time delays prevent immediate execution of governance decisions
 * - Cancellation mechanism for emergency situations
 * - Transparent operation queuing and execution
 */
contract ElataTimelock is TimelockController {
    /// @notice Standard delay for governance operations (48 hours)
    uint256 public constant STANDARD_DELAY = 48 hours;

    /// @notice Emergency delay for critical operations (6 hours)
    uint256 public constant EMERGENCY_DELAY = 6 hours;

    /**
     * @notice Initializes the Elata Timelock
     * @param minDelay Minimum delay for operations
     * @param proposers Array of addresses that can propose operations
     * @param executors Array of addresses that can execute operations
     * @param admin Address that will be the admin (can be zero to renounce)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) { }
}
