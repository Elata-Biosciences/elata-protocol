// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ElataTimelock} from "../../src/governance/ElataTimelock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import "forge-std/Test.sol";

/**
 * @title ElataTimelock Security Tests
 * @notice Security tests for the ElataTimelock governance contract
 * @dev Tests role-based access control, time delays, and attack vectors
 */
contract TimelockSecurityTest is Test {
    ElataTimelock public timelock;

    address public admin = makeAddr("admin");
    address public proposer = makeAddr("proposer");
    address public executor = makeAddr("executor");
    address public attacker = makeAddr("attacker");
    address public target = makeAddr("target");

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);
    event Cancelled(bytes32 indexed id);

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        // STANDARD_DELAY = 48 hours
        timelock = new ElataTimelock(48 hours, proposers, executors, admin);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CONSTANTS TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Constants() public view {
        assertEq(timelock.STANDARD_DELAY(), 48 hours);
        assertEq(timelock.EMERGENCY_DELAY(), 6 hours);
        assertEq(timelock.getMinDelay(), 48 hours);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ROLE-BASED ACCESS CONTROL TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_InitialRoles() public view {
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, executor));
        assertTrue(timelock.hasRole(DEFAULT_ADMIN_ROLE, admin));

        // Proposers also get canceller role by default
        assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer));
    }

    function test_Security_UnauthorizedCannotSchedule() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        uint256 minDelay = timelock.getMinDelay();

        vm.expectRevert();
        vm.prank(attacker);
        timelock.schedule(target, 0, data, bytes32(0), bytes32("salt"), minDelay);
    }

    function test_Security_UnauthorizedCannotExecute() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        // First schedule as proposer
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, minDelay);

        // Wait for delay
        vm.warp(block.timestamp + minDelay + 1);

        // Attacker tries to execute
        vm.expectRevert();
        vm.prank(attacker);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function test_Security_UnauthorizedCannotCancel() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        // Schedule as proposer
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, minDelay);

        bytes32 id = timelock.hashOperation(target, 0, data, bytes32(0), salt);

        // Attacker tries to cancel
        vm.expectRevert();
        vm.prank(attacker);
        timelock.cancel(id);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // TIME DELAY ENFORCEMENT TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotExecuteBeforeDelay() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, minDelay);

        // Try to execute immediately (before delay)
        vm.expectRevert();
        vm.prank(executor);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function test_Security_CannotScheduleBelowMinDelay() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 tooShortDelay = timelock.getMinDelay() - 1;

        vm.expectRevert();
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, tooShortDelay);
    }

    function test_Security_ExecutionWorksAfterDelay() public {
        // Deploy a simple contract to test execution
        MockTarget mockTarget = new MockTarget();

        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        // Schedule
        vm.prank(proposer);
        timelock.schedule(address(mockTarget), 0, data, bytes32(0), salt, minDelay);

        // Warp past delay
        vm.warp(block.timestamp + minDelay + 1);

        // Execute should succeed
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data, bytes32(0), salt);

        assertEq(mockTarget.value(), 42);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // CANCELLATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ProposerCanCancel() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, minDelay);

        bytes32 id = timelock.hashOperation(target, 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(id));

        // Proposer cancels
        vm.prank(proposer);
        timelock.cancel(id);

        assertFalse(timelock.isOperationPending(id));
    }

    function test_Security_CannotExecuteCancelledOperation() public {
        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        // Schedule
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, minDelay);

        // Cancel
        bytes32 id = timelock.hashOperation(target, 0, data, bytes32(0), salt);
        vm.prank(proposer);
        timelock.cancel(id);

        // Warp past delay
        vm.warp(block.timestamp + minDelay + 1);

        // Try to execute cancelled operation
        vm.expectRevert();
        vm.prank(executor);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // REPLAY ATTACK TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_CannotReplayExecutedOperation() public {
        MockTarget mockTarget = new MockTarget();
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        bytes32 salt = bytes32("salt");
        uint256 minDelay = timelock.getMinDelay();

        // Schedule
        vm.prank(proposer);
        timelock.schedule(address(mockTarget), 0, data, bytes32(0), salt, minDelay);

        // Warp and execute
        vm.warp(block.timestamp + minDelay + 1);
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data, bytes32(0), salt);

        // Try to replay the same execution
        vm.expectRevert();
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data, bytes32(0), salt);
    }

    function test_Security_UniqueOperationIds() public view {
        bytes memory data1 = abi.encodeWithSignature("setValue(uint256)", 1);
        bytes memory data2 = abi.encodeWithSignature("setValue(uint256)", 2);
        bytes32 salt = bytes32("salt");

        bytes32 id1 = timelock.hashOperation(target, 0, data1, bytes32(0), salt);
        bytes32 id2 = timelock.hashOperation(target, 0, data2, bytes32(0), salt);

        assertTrue(id1 != id2, "Different operations should have different IDs");
    }

    // ────────────────────────────────────────────────────────────────────────────
    // BATCH OPERATION TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_BatchOperationExecution() public {
        MockTarget mockTarget = new MockTarget();

        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(mockTarget);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory payloads = new bytes[](2);
        payloads[0] = abi.encodeWithSignature("setValue(uint256)", 10);
        payloads[1] = abi.encodeWithSignature("increment()");

        bytes32 salt = bytes32("batch-salt");
        uint256 minDelay = timelock.getMinDelay();

        // Schedule batch
        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), salt, minDelay);

        // Warp past delay
        vm.warp(block.timestamp + minDelay + 1);

        // Execute batch
        vm.prank(executor);
        timelock.executeBatch(targets, values, payloads, bytes32(0), salt);

        // Value should be 11 (set to 10, then incremented)
        assertEq(mockTarget.value(), 11);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // EDGE CASES
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_ExecuteWithValue() public {
        MockTarget mockTarget = new MockTarget();

        bytes memory data = abi.encodeWithSignature("payableFunction()");
        bytes32 salt = bytes32("value-salt");
        uint256 value = 1 ether;
        uint256 minDelay = timelock.getMinDelay();

        // Fund timelock
        vm.deal(address(timelock), value);

        // Schedule with value
        vm.prank(proposer);
        timelock.schedule(address(mockTarget), value, data, bytes32(0), salt, minDelay);

        // Warp past delay
        vm.warp(block.timestamp + minDelay + 1);

        // Execute with value
        vm.prank(executor);
        timelock.execute(address(mockTarget), value, data, bytes32(0), salt);

        assertEq(address(mockTarget).balance, value);
    }

    function test_Security_PredecessorDependency() public {
        MockTarget mockTarget = new MockTarget();

        bytes memory data1 = abi.encodeWithSignature("setValue(uint256)", 100);
        bytes memory data2 = abi.encodeWithSignature("increment()");
        bytes32 salt1 = bytes32("salt1");
        bytes32 salt2 = bytes32("salt2");
        uint256 minDelay = timelock.getMinDelay();

        // Calculate first operation ID
        bytes32 id1 = timelock.hashOperation(address(mockTarget), 0, data1, bytes32(0), salt1);

        // Schedule first operation
        vm.prank(proposer);
        timelock.schedule(address(mockTarget), 0, data1, bytes32(0), salt1, minDelay);

        // Schedule second operation with first as predecessor
        vm.prank(proposer);
        timelock.schedule(address(mockTarget), 0, data2, id1, salt2, minDelay);

        // Warp past delay
        vm.warp(block.timestamp + minDelay + 1);

        // Try to execute second before first (should fail)
        vm.expectRevert();
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data2, id1, salt2);

        // Execute first
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data1, bytes32(0), salt1);

        // Now second should work
        vm.prank(executor);
        timelock.execute(address(mockTarget), 0, data2, id1, salt2);

        assertEq(mockTarget.value(), 101);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // ADMIN TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function test_Security_AdminCanGrantRoles() public {
        address newProposer = makeAddr("newProposer");

        vm.prank(admin);
        timelock.grantRole(PROPOSER_ROLE, newProposer);

        assertTrue(timelock.hasRole(PROPOSER_ROLE, newProposer));
    }

    function test_Security_AdminCanRevokeRoles() public {
        vm.prank(admin);
        timelock.revokeRole(PROPOSER_ROLE, proposer);

        assertFalse(timelock.hasRole(PROPOSER_ROLE, proposer));
    }

    function test_Security_NonAdminCannotGrantRoles() public {
        address newProposer = makeAddr("newProposer");

        vm.expectRevert();
        vm.prank(attacker);
        timelock.grantRole(PROPOSER_ROLE, newProposer);
    }

    // ────────────────────────────────────────────────────────────────────────────
    // FUZZ TESTS
    // ────────────────────────────────────────────────────────────────────────────

    function testFuzz_DelayEnforcement(uint256 delay) public {
        // Bound to reasonable range above minimum
        delay = bound(delay, timelock.getMinDelay(), 365 days);

        bytes memory data = abi.encodeWithSignature("someFunction()");
        bytes32 salt = keccak256(abi.encode(delay));

        // Schedule with custom delay
        vm.prank(proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, delay);

        bytes32 id = timelock.hashOperation(target, 0, data, bytes32(0), salt);
        uint256 readyTime = timelock.getTimestamp(id);

        // Ready time should be block.timestamp + delay
        assertEq(readyTime, block.timestamp + delay);
    }
}

/**
 * @notice Mock contract for timelock testing
 */
contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function increment() external {
        value += 1;
    }

    function payableFunction() external payable {}

    function someFunction() external {}
}
