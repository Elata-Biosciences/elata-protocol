// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title ElataTimelock
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Timelock controller enforcing execution delays on governance proposals.
 * @dev Wraps OpenZeppelin TimelockController with protocol-specific delay constants. Standard
 *      operations require a 48-hour delay; critical fixes may use a 6-hour emergency path.
 *      Proposer and executor roles are assigned at deployment, typically to the Governor and
 *      a multisig. Operations can be cancelled before execution if a security issue is discovered.
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
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
