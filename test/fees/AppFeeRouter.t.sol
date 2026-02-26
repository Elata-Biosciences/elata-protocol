// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppFeeRouter} from "../../src/fees/AppFeeRouter.sol";
import {ELTA} from "elta/ELTA.sol";
import "forge-std/Test.sol";

contract AppFeeRouterTest is Test {
    ELTA public elta;
    AppFeeRouter public feeRouter;

    address public governance = address(0x1);
    address public trader = address(0x2);
    address public bondingCurve = address(0x3);

    event FeeForwarded(address indexed source, address indexed payer, uint256 grossAmount, uint256 fee);
    event FeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA(governance);

        // Deploy fee router (feeBps config only; no yield distribution)
        feeRouter = new AppFeeRouter(elta, governance);

        // Fund trader
        vm.prank(governance);
        elta.transfer(trader, 10_000 ether);

        // Approve fee router
        vm.prank(trader);
        elta.approve(address(feeRouter), type(uint256).max);
    }

    function test_InitialState() public view {
        assertEq(address(feeRouter.ELTA()), address(elta));
        assertEq(feeRouter.governance(), governance);
        assertEq(feeRouter.feeBps(), 100); // 1%
        assertEq(feeRouter.MAX_FEE_BPS(), 500); // 5%
    }

    function test_TakeAndForwardFee() public {
        uint256 grossAmount = 1000 ether;
        vm.prank(bondingCurve);
        vm.expectRevert(AppFeeRouter.Deprecated.selector);
        feeRouter.takeAndForwardFee(trader, grossAmount);
    }

    function test_TakeAndForwardFee_SmallAmount() public {
        uint256 grossAmount = 9 ether;
        vm.prank(bondingCurve);
        vm.expectRevert(AppFeeRouter.Deprecated.selector);
        feeRouter.takeAndForwardFee(trader, grossAmount);
    }

    function test_SetFeeBps() public {
        vm.expectEmit(false, false, false, true);
        emit FeeBpsUpdated(100, 250);

        vm.prank(governance);
        feeRouter.setFeeBps(250); // 2.5%

        assertEq(feeRouter.feeBps(), 250);
    }

    function test_SetFeeBps_RevertIfNotGovernance() public {
        vm.prank(trader);
        vm.expectRevert(AppFeeRouter.OnlyGovernance.selector);
        feeRouter.setFeeBps(200);
    }

    function test_SetFeeBps_RevertIfTooHigh() public {
        vm.prank(governance);
        vm.expectRevert(AppFeeRouter.FeeTooHigh.selector);
        feeRouter.setFeeBps(501); // > 5%
    }

    function test_SetFeeBps_MaxAllowed() public {
        vm.prank(governance);
        feeRouter.setFeeBps(500); // Exactly 5%

        assertEq(feeRouter.feeBps(), 500);
    }

    function test_TransferGovernance() public {
        address newGov = address(0x99);

        vm.expectEmit(true, true, false, false);
        emit GovernanceTransferred(governance, newGov);

        vm.prank(governance);
        feeRouter.transferGovernance(newGov);

        assertEq(feeRouter.governance(), newGov);

        // Old governance can't set fee anymore
        vm.prank(governance);
        vm.expectRevert(AppFeeRouter.OnlyGovernance.selector);
        feeRouter.setFeeBps(200);

        // New governance can
        vm.prank(newGov);
        feeRouter.setFeeBps(200);
        assertEq(feeRouter.feeBps(), 200);
    }

    function test_TransferGovernance_RevertZeroAddress() public {
        vm.prank(governance);
        vm.expectRevert("Zero address");
        feeRouter.transferGovernance(address(0));
    }

    function test_CalculateFee() public view {
        uint256 amount = 1000 ether;
        uint256 fee = feeRouter.calculateFee(amount);
        assertEq(fee, 10 ether); // 1% of 1000 = 10

        assertEq(feeRouter.calculateFee(0), 0);
        assertEq(feeRouter.calculateFee(9 ether), 0.09 ether); // 1% of 9 = 0.09
        assertEq(feeRouter.calculateFee(10 ether), 0.1 ether);
    }

    function testFuzz_TakeAndForwardFee(uint256 grossAmount) public {
        grossAmount = bound(grossAmount, 1, 1_000_000 ether);

        vm.prank(bondingCurve);
        vm.expectRevert(AppFeeRouter.Deprecated.selector);
        feeRouter.takeAndForwardFee(trader, grossAmount);
    }

    function testFuzz_SetFeeBps(uint256 newBps) public {
        newBps = bound(newBps, 0, feeRouter.MAX_FEE_BPS());

        vm.prank(governance);
        feeRouter.setFeeBps(newBps);

        assertEq(feeRouter.feeBps(), newBps);
    }
}
