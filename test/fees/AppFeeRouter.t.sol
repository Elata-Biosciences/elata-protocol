// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ELTA } from "../../src/token/ELTA.sol";
import { AppFeeRouter } from "../../src/fees/AppFeeRouter.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";

contract MockRewardsDistributor is IRewardsDistributor {
    IERC20 public immutable eltaToken;
    uint256 public totalDeposited;

    constructor(IERC20 _elta) {
        eltaToken = _elta;
    }

    function deposit(uint256 amount) external {
        eltaToken.transferFrom(msg.sender, address(this), amount);
        totalDeposited += amount;
    }

    function depositVeInToken(IERC20 token, uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
    }
}

contract AppFeeRouterTest is Test {
    ELTA public elta;
    AppFeeRouter public feeRouter;
    MockRewardsDistributor public rewardsDistributor;

    address public governance = address(0x1);
    address public trader = address(0x2);
    address public bondingCurve = address(0x3);

    event FeeForwarded(
        address indexed source, address indexed payer, uint256 grossAmount, uint256 fee
    );
    event FeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event GovernanceTransferred(address indexed oldGov, address indexed newGov);

    function setUp() public {
        // Deploy ELTA
        elta = new ELTA("ELTA", "ELTA", governance, governance, 1_000_000 ether, 0);

        // Deploy mock rewards distributor
        rewardsDistributor = new MockRewardsDistributor(elta);

        // Deploy fee router - MockRewardsDistributor implements the IRewardsDistributor interface
        feeRouter =
            new AppFeeRouter(elta, IRewardsDistributor(address(rewardsDistributor)), governance);

        // Fund trader
        vm.prank(governance);
        elta.transfer(trader, 10_000 ether);

        // Approve fee router
        vm.prank(trader);
        elta.approve(address(feeRouter), type(uint256).max);
    }

    function test_InitialState() public view {
        assertEq(address(feeRouter.ELTA()), address(elta));
        assertEq(address(feeRouter.rewardsDistributor()), address(rewardsDistributor));
        assertEq(feeRouter.governance(), governance);
        assertEq(feeRouter.feeBps(), 100); // 1%
        assertEq(feeRouter.MAX_FEE_BPS(), 500); // 5%
    }

    function test_TakeAndForwardFee() public {
        uint256 grossAmount = 1000 ether;
        uint256 expectedFee = (grossAmount * 100) / 10_000; // 1% = 10 ether

        vm.expectEmit(true, true, false, true);
        emit FeeForwarded(bondingCurve, trader, grossAmount, expectedFee);

        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, grossAmount);

        assertEq(rewardsDistributor.totalDeposited(), expectedFee);
        assertEq(elta.balanceOf(trader), 10_000 ether - expectedFee);
    }

    function test_TakeAndForwardFee_SmallAmount() public {
        uint256 traderBalanceBefore = elta.balanceOf(trader);
        uint256 grossAmount = 9 ether;
        uint256 expectedFee = (grossAmount * 100) / 10_000; // 0.09 ELTA

        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, grossAmount);

        assertEq(rewardsDistributor.totalDeposited(), expectedFee);
        assertEq(elta.balanceOf(trader), traderBalanceBefore - expectedFee);
    }

    function test_SetFeeBps() public {
        vm.expectEmit(false, false, false, true);
        emit FeeBpsUpdated(100, 250);

        vm.prank(governance);
        feeRouter.setFeeBps(250); // 2.5%

        assertEq(feeRouter.feeBps(), 250);

        // Verify new fee rate works
        uint256 grossAmount = 1000 ether;
        uint256 expectedFee = (grossAmount * 250) / 10_000; // 2.5% = 25 ether

        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, grossAmount);

        assertEq(rewardsDistributor.totalDeposited(), expectedFee);
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

        // Fund trader if needed
        uint256 expectedFee = (grossAmount * feeRouter.feeBps()) / 10_000;
        if (expectedFee == 0) return;

        if (elta.balanceOf(trader) < expectedFee) {
            vm.prank(governance);
            elta.transfer(trader, expectedFee);
            vm.prank(trader);
            elta.approve(address(feeRouter), expectedFee);
        }

        uint256 traderBalanceBefore = elta.balanceOf(trader);

        vm.prank(bondingCurve);
        feeRouter.takeAndForwardFee(trader, grossAmount);

        assertEq(elta.balanceOf(trader), traderBalanceBefore - expectedFee);
        assertEq(rewardsDistributor.totalDeposited(), expectedFee);
    }

    function testFuzz_SetFeeBps(uint256 newBps) public {
        newBps = bound(newBps, 0, feeRouter.MAX_FEE_BPS());

        vm.prank(governance);
        feeRouter.setFeeBps(newBps);

        assertEq(feeRouter.feeBps(), newBps);
    }
}
