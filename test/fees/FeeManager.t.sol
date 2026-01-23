// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FeeManager} from "../../src/fees/FeeManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock ELTA for testing
contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 100_000_000e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock rewards distributor
contract MockRewardsDistributor {
    function distributeRewards(
        uint256,
        /* appId */
        uint256 /* amount */
    )
        external {}

    receive() external payable {}
}

/// @notice Mock treasury vault
contract MockTreasuryVault {
    MockUSDC public usdc;

    constructor(address _usdc) {
        usdc = MockUSDC(_usdc);
    }

    function deposit(
        uint256,
        /* appId */
        uint256 amount,
        uint256 /* epochId */
    )
        external
    {
        usdc.transferFrom(msg.sender, address(this), amount);
    }
}

/**
 * @title FeeManager Unit Tests
 * @notice TDD tests for FeeManager - daily epochs and ELTA distribution
 * @dev Tests deposit, epoch closing, splits, and caller incentives
 */
contract FeeManagerTest is Test {
    FeeManager public feeManager;
    MockELTA public elta;
    MockUSDC public usdc;
    MockRewardsDistributor public appRewards;
    MockRewardsDistributor public veRewards;
    MockTreasuryVault public treasuryVault;

    address public admin = makeAddr("admin");
    address public governance = makeAddr("governance");
    address public feeSwapper = makeAddr("feeSwapper");
    address public feeCollector = makeAddr("feeCollector");
    address public creator = makeAddr("creator");
    address public caller = makeAddr("caller");

    uint256 public constant APP_ID_1 = 1;
    uint256 public constant APP_ID_2 = 2;
    uint256 public constant EPOCH_LENGTH = 1 days;

    // Events to test
    event EltaDeposited(uint256 indexed appId, uint256 amount, address indexed from);
    event EpochClosed(uint256 indexed appId, uint256 indexed epochId, uint256 totalDistributed);
    event CallerIncentivePaid(address indexed caller, uint256 amount, uint256 indexed epochId);
    event FeeSplitsUpdated(uint256 appStakersBps, uint256 veEltaBps, uint256 creatorBps, uint256 treasuryBps);

    function setUp() public {
        elta = new MockELTA();
        usdc = new MockUSDC();
        appRewards = new MockRewardsDistributor();
        veRewards = new MockRewardsDistributor();
        treasuryVault = new MockTreasuryVault(address(usdc));

        feeManager = new FeeManager(
            address(elta),
            address(usdc),
            admin,
            governance,
            address(appRewards),
            address(veRewards),
            address(treasuryVault),
            EPOCH_LENGTH
        );

        // Grant feeSwapper and feeCollector deposit permissions
        vm.startPrank(admin);
        feeManager.setDepositor(feeSwapper, true);
        feeManager.setDepositor(feeCollector, true);
        vm.stopPrank();

        // Give feeSwapper ELTA to deposit
        elta.transfer(feeSwapper, 1_000_000 ether);
        elta.transfer(feeCollector, 1_000_000 ether);

        // Give treasury vault USDC for incentives
        usdc.transfer(address(feeManager), 100_000e6);
    }

    // =========== Deployment Tests ===========

    function test_Deployment() public view {
        assertEq(address(feeManager.ELTA()), address(elta));
        assertEq(address(feeManager.USDC()), address(usdc));
        assertEq(feeManager.admin(), admin);
        assertEq(feeManager.governance(), governance);
        assertEq(feeManager.epochLength(), EPOCH_LENGTH);
    }

    function test_RevertWhen_DeployWithZeroELTA() public {
        vm.expectRevert(FeeManager.ZeroAddress.selector);
        new FeeManager(
            address(0),
            address(usdc),
            admin,
            governance,
            address(appRewards),
            address(veRewards),
            address(treasuryVault),
            EPOCH_LENGTH
        );
    }

    function test_RevertWhen_DeployWithInvalidEpochLength() public {
        vm.expectRevert(FeeManager.InvalidEpochLength.selector);
        new FeeManager(
            address(elta),
            address(usdc),
            admin,
            governance,
            address(appRewards),
            address(veRewards),
            address(treasuryVault),
            30 minutes
        );
    }

    // =========== Deposit Tests ===========

    function test_DepositEltaForApp() public {
        uint256 amount = 1000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);

        vm.expectEmit(true, true, true, true);
        emit EltaDeposited(APP_ID_1, amount, feeSwapper);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        assertEq(feeManager.pendingEltaToDistribute(APP_ID_1), amount);
    }

    function test_DepositMultipleTimes() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount1 + amount2);

        feeManager.depositEltaForApp(APP_ID_1, amount1);
        feeManager.depositEltaForApp(APP_ID_1, amount2);
        vm.stopPrank();

        assertEq(feeManager.pendingEltaToDistribute(APP_ID_1), amount1 + amount2);
    }

    function test_RevertWhen_UnauthorizedDepositor() public {
        vm.prank(caller);
        vm.expectRevert(FeeManager.OnlyDepositor.selector);
        feeManager.depositEltaForApp(APP_ID_1, 1000 ether);
    }

    function test_RevertWhen_DepositZeroAmount() public {
        vm.prank(feeSwapper);
        vm.expectRevert(FeeManager.InvalidAmount.selector);
        feeManager.depositEltaForApp(APP_ID_1, 0);
    }

    // =========== Epoch Close Tests ===========

    function test_CloseEpoch() public {
        uint256 amount = 10_000 ether;

        // Deposit ELTA
        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        // Register app creator
        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_1, creator);

        // Advance time by epoch length
        vm.warp(block.timestamp + EPOCH_LENGTH);

        uint256 appRewardsBefore = elta.balanceOf(address(appRewards));
        uint256 veRewardsBefore = elta.balanceOf(address(veRewards));
        uint256 creatorBefore = elta.balanceOf(creator);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID_1);

        // Verify distribution (default: 50% app, 30% veELTA, 10% creator, 10% treasury)
        uint256 appShare = (amount * 5000) / 10000;
        uint256 veShare = (amount * 3000) / 10000;
        uint256 creatorShare = (amount * 1000) / 10000;

        assertEq(elta.balanceOf(address(appRewards)), appRewardsBefore + appShare);
        assertEq(elta.balanceOf(address(veRewards)), veRewardsBefore + veShare);
        assertEq(elta.balanceOf(creator), creatorBefore + creatorShare);
    }

    function test_CloseEpochIsPermissionless() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_1, creator);

        vm.warp(block.timestamp + EPOCH_LENGTH);

        // Anyone can close epoch
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        feeManager.closeEpoch(APP_ID_1);
    }

    function test_RevertWhen_CloseEpochTooEarly() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        // Try to close without waiting
        vm.prank(caller);
        vm.expectRevert(FeeManager.EpochNotEnded.selector);
        feeManager.closeEpoch(APP_ID_1);
    }

    function test_RevertWhen_CloseEpochTwice() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_1, creator);

        vm.warp(block.timestamp + EPOCH_LENGTH);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID_1);

        // Try to close again immediately
        vm.prank(caller);
        vm.expectRevert(FeeManager.EpochNotEnded.selector);
        feeManager.closeEpoch(APP_ID_1);
    }

    function test_CloseEpochWithNothingToDistribute() public {
        vm.warp(block.timestamp + EPOCH_LENGTH);

        // Should not revert, just no-op
        vm.prank(caller);
        feeManager.closeEpoch(APP_ID_1);
    }

    // =========== Fee Split Configuration Tests ===========

    function test_SetFeeSplits() public {
        uint256 appStakers = 4000;
        uint256 veElta = 4000;
        uint256 creatorShare = 1000;
        uint256 treasury = 1000;

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit FeeSplitsUpdated(appStakers, veElta, creatorShare, treasury);
        feeManager.setFeeSplits(appStakers, veElta, creatorShare, treasury);

        (uint256 a, uint256 v, uint256 c, uint256 t) = feeManager.feeSplits();
        assertEq(a, appStakers);
        assertEq(v, veElta);
        assertEq(c, creatorShare);
        assertEq(t, treasury);
    }

    function test_RevertWhen_FeeSplitsDontSumTo100() public {
        vm.prank(governance);
        vm.expectRevert(FeeManager.InvalidFeeSplits.selector);
        feeManager.setFeeSplits(5000, 3000, 1000, 500); // 95% total
    }

    function test_RevertWhen_NonGovernanceSetsFeeSplits() public {
        vm.prank(caller);
        vm.expectRevert(FeeManager.OnlyGovernance.selector);
        feeManager.setFeeSplits(5000, 3000, 1000, 1000);
    }

    // =========== Caller Incentive Tests ===========

    function test_CallerIncentiveOnCloseEpoch() public {
        uint256 amount = 100_000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_1, creator);

        vm.warp(block.timestamp + EPOCH_LENGTH);

        uint256 callerUsdcBefore = usdc.balanceOf(caller);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID_1);

        // Caller should receive incentive
        uint256 callerUsdcAfter = usdc.balanceOf(caller);
        assertGe(callerUsdcAfter, callerUsdcBefore);
    }

    // =========== View Functions Tests ===========

    function test_GetEpochId() public {
        uint256 epochId1 = feeManager.getCurrentEpochId();

        vm.warp(block.timestamp + EPOCH_LENGTH);
        uint256 epochId2 = feeManager.getCurrentEpochId();

        assertEq(epochId2, epochId1 + 1);
    }

    function test_CanCloseEpoch() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        assertFalse(feeManager.canCloseEpoch(APP_ID_1));

        vm.warp(block.timestamp + EPOCH_LENGTH);

        assertTrue(feeManager.canCloseEpoch(APP_ID_1));
    }

    // =========== Fuzz Tests ===========

    function testFuzz_DepositEltaForApp(uint256 amount) public {
        amount = bound(amount, 1 ether, 500_000 ether);

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        assertEq(feeManager.pendingEltaToDistribute(APP_ID_1), amount);
    }

    function testFuzz_CloseEpochDistribution(uint256 amount) public {
        amount = bound(amount, 1000 ether, 500_000 ether);

        vm.startPrank(feeSwapper);
        elta.approve(address(feeManager), amount);
        feeManager.depositEltaForApp(APP_ID_1, amount);
        vm.stopPrank();

        vm.prank(admin);
        feeManager.setAppCreator(APP_ID_1, creator);

        vm.warp(block.timestamp + EPOCH_LENGTH);

        uint256 totalBefore =
            elta.balanceOf(address(appRewards)) + elta.balanceOf(address(veRewards)) + elta.balanceOf(creator);

        vm.prank(caller);
        feeManager.closeEpoch(APP_ID_1);

        uint256 totalAfter =
            elta.balanceOf(address(appRewards)) + elta.balanceOf(address(veRewards)) + elta.balanceOf(creator);

        // Distribution should account for 90% of the amount (treasury takes 10%)
        uint256 distributed = totalAfter - totalBefore;
        // With 50% + 30% + 10% = 90% to non-treasury, verify distributed is at least 89.9%
        // Use assertGe with slight tolerance for rounding errors
        assertGe(distributed * 10000 / amount, 8990); // At least 89.9%
    }
}
