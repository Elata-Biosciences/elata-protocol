// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "../../../src/token/ELTA.sol";
import {VeELTA} from "../../../src/staking/VeELTA.sol";
import {ElataGovernor} from "../../../src/governance/ElataGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title GovernanceHandler
 * @notice Handler contract for governance invariant testing
 * @dev Exposes governance actions with ghost variable tracking
 */
contract GovernanceHandler is Test {
    ELTA public elta;
    VeELTA public veElta;
    ElataGovernor public governor;

    // Actors
    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking
    uint256 public ghost_totalLocked;
    uint256 public ghost_totalDelegated;
    uint256 public ghost_lockCount;
    uint256 public ghost_delegateCount;
    uint256 public ghost_proposeCount;
    uint256 public ghost_voteCount;
    uint256 public ghost_callCount;

    // Track proposals
    uint256[] public proposalIds;
    mapping(uint256 => bool) public proposalCreated;

    // Track delegation
    mapping(address => address) public delegatedTo;

    constructor(ELTA _elta, VeELTA _veElta, ElataGovernor _governor) {
        elta = _elta;
        veElta = _veElta;
        governor = _governor;

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[actorIndexSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    function createLock(uint256 actorSeed, uint256 amount, uint256 durationSeed) external useActor(actorSeed) {
        ghost_callCount++;

        // Skip if actor already has a lock
        (uint128 principal,) = veElta.locks(currentActor);
        if (principal > 0) return;

        // Bound amount to actor's balance
        uint256 balance = elta.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        // Bound duration
        uint64 duration = uint64(bound(durationSeed, 8 days, 730 days));
        uint64 unlockTime = uint64(block.timestamp) + duration;

        // Execute lock
        elta.approve(address(veElta), amount);
        try veElta.lock(amount, unlockTime) {
            ghost_totalLocked += amount;
            ghost_lockCount++;
        } catch {
            // Lock failed
        }
    }

    function delegate(uint256 actorSeed, uint256 toSeed) external useActor(actorSeed) {
        ghost_callCount++;

        // Bound to another actor
        address to = actors[toSeed % actors.length];

        try veElta.delegate(to) {
            delegatedTo[currentActor] = to;
            ghost_delegateCount++;
        } catch {
            // Delegation failed
        }
    }

    function propose(uint256 actorSeed) external useActor(actorSeed) {
        ghost_callCount++;

        // Check if actor has enough voting power
        uint256 threshold = governor.proposalThreshold();
        if (threshold > 0) {
            vm.roll(block.number + 1);
            uint256 votes = veElta.getPastVotes(currentActor, block.number - 1);
            if (votes < threshold) return;
        }

        // Create simple proposal
        address[] memory targets = new address[](1);
        targets[0] = address(veElta);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = "";

        string memory description = string(abi.encodePacked("Proposal ", ghost_proposeCount));

        try governor.propose(targets, values, calldatas, description) returns (uint256 proposalId) {
            proposalIds.push(proposalId);
            proposalCreated[proposalId] = true;
            ghost_proposeCount++;
        } catch {
            // Proposal failed
        }
    }

    function vote(uint256 actorSeed, uint256 proposalIndexSeed, uint8 support) external useActor(actorSeed) {
        ghost_callCount++;

        if (proposalIds.length == 0) return;

        uint256 proposalId = proposalIds[proposalIndexSeed % proposalIds.length];

        // Check proposal state
        IGovernor.ProposalState state = governor.state(proposalId);
        if (state != IGovernor.ProposalState.Active) return;

        // Check if already voted
        if (governor.hasVoted(proposalId, currentActor)) return;

        // Bound support to valid values
        support = support % 3; // 0 = Against, 1 = For, 2 = Abstain

        try governor.castVote(proposalId, support) {
            ghost_voteCount++;
        } catch {
            // Vote failed
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIME MANIPULATION
    // ═══════════════════════════════════════════════════════════════════════════

    function warpTime(uint256 timeDelta) external {
        ghost_callCount++;
        timeDelta = bound(timeDelta, 1, 30 days);
        vm.warp(block.timestamp + timeDelta);
        vm.roll(block.number + timeDelta / 12); // Approximate blocks
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function getActorCount() external view returns (uint256) {
        return actors.length;
    }

    function getActor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function getProposalCount() external view returns (uint256) {
        return proposalIds.length;
    }

    function getTotalVotingPower() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            total += veElta.getVotes(actors[i]);
        }
    }

    function getTotalPrincipalLocked() external view returns (uint256 total) {
        for (uint256 i = 0; i < actors.length; i++) {
            (uint128 principal,) = veElta.locks(actors[i]);
            total += principal;
        }
    }
}
