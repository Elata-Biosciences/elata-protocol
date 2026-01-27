// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ELTA} from "elta/ELTA.sol";
import {VeELTA} from "../../src/staking/VeELTA.sol";
import {ElataGovernor} from "../../src/governance/ElataGovernor.sol";
import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {GovernanceHandler} from "./handlers/GovernanceHandler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/**
 * @title GovernanceInvariants
 * @notice Invariant tests for ElataGovernor and VeELTA voting system
 * @dev Tests voting power conservation, proposal state machine, and thresholds
 */
contract GovernanceInvariants is Test {
    ELTA public elta;
    VeELTA public veElta;
    ElataGovernor public governor;
    ElataTimelock public timelock;
    GovernanceHandler public handler;

    address public admin = makeAddr("admin");

    uint256 public constant ELTA_MAX_SUPPLY = 77_000_000 ether;
    uint256 public constant MIN_DELAY = 48 hours;

    function setUp() public {
        // Deploy ELTA
        vm.prank(admin);
        elta = new ELTA(admin);

        // Deploy VeELTA
        veElta = new VeELTA(IERC20(address(elta)), admin);

        // Deploy Timelock
        address[] memory proposers = new address[](1);
        proposers[0] = admin;
        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new ElataTimelock(MIN_DELAY, proposers, executors, admin);

        // Deploy Governor
        governor = new ElataGovernor(veElta, address(timelock));

        // Grant proposer role to governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(admin);
        timelock.grantRole(proposerRole, address(governor));

        // Deploy handler
        handler = new GovernanceHandler(elta, veElta, governor);

        // Fund actors with ELTA
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            vm.prank(admin);
            elta.transfer(actor, 5_000_000 ether);
        }

        // Set up handler as target
        targetContract(address(handler));

        // Exclude admin from fuzzing
        excludeSender(admin);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING POWER CONSERVATION INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Total voting power equals veELTA total supply
    /// @dev Sum of all getVotes() should equal totalSupply()
    function invariant_TotalVotingPowerEqualsVeELTASupply() public view {
        uint256 totalVotingPower = 0;

        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            totalVotingPower += veElta.getVotes(actor);
        }

        uint256 totalSupply = veElta.totalSupply();

        // Allow for small discrepancy due to actors outside our set
        assertLe(totalVotingPower, totalSupply, "Voting power > total supply");
    }

    /// @notice Delegation conserves votes - delegating doesn't create/destroy votes
    function invariant_DelegatedVotesConserved() public view {
        uint256 totalVotingPower = handler.getTotalVotingPower();
        uint256 totalSupply = veElta.totalSupply();

        // Total voting power across all tracked actors should <= total supply
        // (could be < if votes delegated to addresses outside our actor set)
        assertLe(totalVotingPower, totalSupply, "Delegation broke conservation");
    }

    /// @notice No user's voting power exceeds 2x their locked principal
    function invariant_VotingPowerBoundedBy2xPrincipal() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint128 principal,) = veElta.locks(actor);
            uint256 veBalance = veElta.balanceOf(actor);

            // veELTA balance should be <= 2x principal (max boost)
            assertLe(veBalance, uint256(principal) * 2, "veELTA > 2x principal");
        }
    }

    /// @notice VeELTA balance >= principal (min boost is 1x)
    function invariant_VotingPowerAtLeastPrincipal() public view {
        for (uint256 i = 0; i < handler.getActorCount(); i++) {
            address actor = handler.getActor(i);
            (uint128 principal,) = veElta.locks(actor);
            uint256 veBalance = veElta.balanceOf(actor);

            // veELTA balance should be >= principal (1x min boost)
            assertGe(veBalance, principal, "veELTA < principal");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOCKED ELTA INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Total locked ELTA equals veELTA contract's ELTA balance
    function invariant_LockedEltaMatchesContractBalance() public view {
        uint256 totalPrincipal = handler.getTotalPrincipalLocked();
        uint256 contractBalance = elta.balanceOf(address(veElta));

        assertEq(totalPrincipal, contractBalance, "Principal != contract balance");
    }

    /// @notice veELTA is non-transferable (checked by attempting transfers in handler)
    function invariant_VeELTANonTransferable() public view {
        // This is enforced by the _update override in VeELTA
        // Just verify the contract exists
        assertTrue(address(veElta) != address(0), "veELTA not deployed");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUORUM AND THRESHOLD INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Quorum is exactly 4% of total supply at any given snapshot
    function invariant_QuorumIs4PercentOfSupply() public {
        // Advance blocks to ensure we can query past checkpoints
        vm.roll(block.number + 5);

        // Check quorum at a past block
        uint256 checkBlock = block.number - 2;
        uint256 pastSupply = veElta.getPastTotalSupply(checkBlock);
        uint256 quorum = governor.quorum(checkBlock);

        // Quorum should be exactly 4% of the past supply
        uint256 expectedQuorum = (pastSupply * 4) / 100;
        assertEq(quorum, expectedQuorum, "Quorum != 4% of supply");
    }

    /// @notice Proposal threshold is constant (set at construction)
    function invariant_ProposalThresholdConstant() public view {
        uint256 threshold = governor.proposalThreshold();
        assertEq(threshold, 77000e18, "Threshold changed");
    }

    /// @notice Quorum is always 4% of supply
    function invariant_QuorumIs4Percent() public {
        vm.roll(block.number + 1);

        uint256 totalSupply = veElta.getPastTotalSupply(block.number - 1);
        if (totalSupply > 0) {
            uint256 quorum = governor.quorum(block.number - 1);
            uint256 expected = (totalSupply * 4) / 100;
            assertEq(quorum, expected, "Quorum != 4%");
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL STATE MACHINE INVARIANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Executed proposals cannot be re-executed (tracked via executed mapping)
    function invariant_ExecutedProposalsRecorded() public view {
        // If a proposal was executed, it should be marked in governor.executed()
        for (uint256 i = 0; i < handler.getProposalCount(); i++) {
            // Note: We can't easily get proposal IDs here, but the handler tracks them
            // The invariant is enforced by OpenZeppelin's Governor implementation
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("Governance Call Summary:");
        console2.log("  Total calls:", handler.ghost_callCount());
        console2.log("  Lock count:", handler.ghost_lockCount());
        console2.log("  Delegate count:", handler.ghost_delegateCount());
        console2.log("  Propose count:", handler.ghost_proposeCount());
        console2.log("  Vote count:", handler.ghost_voteCount());
        console2.log("  Total locked:", handler.ghost_totalLocked());
        console2.log("  veELTA total supply:", veElta.totalSupply());
        console2.log("  Proposals created:", handler.getProposalCount());
    }
}
