// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title ElataGovernor
 * @author Elata Biosciences
 * @notice Onchain governance contract for the Elata Protocol
 * @dev OpenZeppelin Governor with veELTA voting and timelock execution
 *
 * Features:
 * - Token-weighted voting using veELTA (vote-escrowed ELTA)
 * - Quorum requirements (4% of veELTA supply)
 * - Proposal thresholds and voting delays
 * - Emergency proposal mechanism
 * - Timelock-controlled execution for safety
 * - Delegation support for voting power
 *
 * Governance Parameters:
 * - Voting Delay: 1 day
 * - Voting Period: 7 days
 * - Proposal Threshold: 0.1% of total supply (77K tokens)
 * - Quorum: 4% of veELTA supply
 * - Timelock: 48 hour minimum delay
 */
contract ElataGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Emergency proposal threshold (5% of total supply)
    uint256 public constant EMERGENCY_PROPOSAL_THRESHOLD = 500; // 5%

    /// @notice Emergency voting period (3 days instead of 7)
    uint256 public constant EMERGENCY_VOTING_PERIOD = 3 days;

    /// @notice Mapping to track emergency proposals
    mapping(uint256 => bool) public emergencyProposals;

    /// @notice Mapping to track proposal execution status
    mapping(uint256 => bool) public executed;

    event EmergencyProposalCreated(uint256 indexed proposalId, string description);
    event CustomProposalExecuted(uint256 indexed proposalId);

    /**
     * @notice Initializes the Elata Governor with veELTA voting
     * @param _veELTA Address of the veELTA token (voting token)
     * @param _timelock Address of the timelock controller
     */
    constructor(IVotes _veELTA, address _timelock)
        Governor("Elata Governor")
        GovernorSettings(
            1 days, /* voting delay */
            7 days, /* voting period */
            77000e18 /* proposal threshold (0.1% of 77M) */
        )
        GovernorVotes(_veELTA)
        GovernorVotesQuorumFraction(4) /* 4% quorum */
        GovernorTimelockControl(TimelockController(payable(_timelock)))
    {}

    /**
     * @notice Creates an emergency proposal with expedited voting
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param calldatas Array of function call data
     * @param description Proposal description
     * @return proposalId ID of the created proposal
     */
    function proposeEmergency(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256 proposalId) {
        // Check emergency proposal threshold
        uint256 voterVotes = getVotes(msg.sender, block.number - 1);
        uint256 threshold = _emergencyProposalThreshold();

        if (voterVotes < threshold) revert GovernorInsufficientProposerVotes(msg.sender, voterVotes, threshold);

        proposalId = propose(targets, values, calldatas, description);
        emergencyProposals[proposalId] = true;

        emit EmergencyProposalCreated(proposalId, description);
    }

    /**
     * @notice Executes a successful proposal through timelock
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param calldatas Array of function call data
     * @param descriptionHash Hash of the proposal description
     * @return proposalId ID of the executed proposal
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override(Governor) returns (uint256 proposalId) {
        proposalId = super.execute(targets, values, calldatas, descriptionHash);
        executed[proposalId] = true;
        emit CustomProposalExecuted(proposalId);
    }

    /**
     * @notice Gets the voting period for a proposal (shorter for emergency proposals)
     * @param proposalId ID of the proposal
     * @return Voting period in seconds
     */
    function proposalVotingPeriod(uint256 proposalId) public view returns (uint256) {
        if (emergencyProposals[proposalId]) return EMERGENCY_VOTING_PERIOD;
        return votingPeriod();
    }

    /**
     * @notice Gets the emergency proposal threshold
     * @return Emergency proposal threshold in tokens
     */
    function emergencyProposalThreshold() public view returns (uint256) {
        return _emergencyProposalThreshold();
    }

    /**
     * @notice Checks if a proposal is an emergency proposal
     * @param proposalId ID of the proposal
     * @return Whether the proposal is marked as emergency
     */
    function isEmergencyProposal(uint256 proposalId) public view returns (bool) {
        return emergencyProposals[proposalId];
    }

    /**
     * @notice Checks if a proposal has been executed
     * @param proposalId ID of the proposal
     * @return Whether the proposal has been executed
     */
    function isExecuted(uint256 proposalId) public view returns (bool) {
        return executed[proposalId];
    }

    /**
     * @dev Calculates emergency proposal threshold
     * @return Emergency threshold based on total supply
     */
    function _emergencyProposalThreshold() internal view returns (uint256) {
        return (token().getPastTotalSupply(block.number - 1) * EMERGENCY_PROPOSAL_THRESHOLD) / 10000;
    }

    // Required overrides for multiple inheritance

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    // Timelock-related overrides

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
