// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AppToken} from "../../src/apps/AppToken.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mock rewards distributor for testing
contract MockRewardsDistributor {
    receive() external payable {}
}

/**
 * @title LP-Keyed Transfer Tax Tests
 * @notice TDD tests for LP-keyed transfer taxation in AppToken
 * @dev Tests that fees only apply to LP transfers, not wallet-to-wallet
 *
 * Key Requirements from Protocol Changes:
 * - Tax only applies when: neither side is exempt AND (isLiquidityPool[from] || isLiquidityPool[to])
 * - Router must be exempt to avoid taxing swap internals
 * - LP addresses are allowlisted, not auto-detected
 * - Tax goes to FeeCollector with per-app accounting
 */
contract LPKeyedTransferTaxTest is Test {
    AppToken public token;
    FeeCollector public feeCollector;

    address public admin = makeAddr("admin");
    address public creator = makeAddr("creator");
    address public governance = makeAddr("governance");
    address public treasury = makeAddr("treasury");
    address public feeManager = makeAddr("feeManager");
    address public feeSwapper = makeAddr("feeSwapper");

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public lpAddress = makeAddr("lpAddress");
    address public router = makeAddr("router");

    MockRewardsDistributor public appRewards;
    MockRewardsDistributor public veRewards;

    uint256 public constant APP_ID = 1;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;

    event LPAddressUpdated(address indexed lp, bool isLP);
    event TransferTaxCollected(uint256 indexed appId, address indexed token, uint256 amount, address from, address to);

    function setUp() public {
        // Deploy mock rewards distributors
        appRewards = new MockRewardsDistributor();
        veRewards = new MockRewardsDistributor();

        // Deploy FeeCollector
        // We need a mock ELTA for FeeCollector
        MockELTA mockElta = new MockELTA();
        feeCollector = new FeeCollector(address(mockElta), admin, feeManager, feeSwapper);

        // Deploy AppToken with LP-keyed tax support
        token = new AppToken(
            AppToken.InitParams({
                name: "Test App Token",
                symbol: "TAT",
                decimals: 18,
                maxSupply: INITIAL_SUPPLY,
                creator: creator,
                admin: admin,
                governance: governance,
                appRewardsDistributor: address(appRewards),
                rewardsDistributor: address(veRewards),
                treasury: treasury
            })
        );

        // Set up token with FeeCollector and app ID
        vm.startPrank(admin);
        token.setFeeCollector(address(feeCollector), APP_ID);
        // Mint tokens to users for testing
        token.mint(user1, 100_000 ether);
        token.mint(user2, 100_000 ether);
        vm.stopPrank();

        // Set router as exempt (important for LP operations)
        vm.prank(governance);
        token.setTransferFeeExempt(router, true);
    }

    // =========== LP Address Management Tests ===========

    function test_SetLPAddress() public {
        assertFalse(token.isLiquidityPool(lpAddress));

        vm.prank(governance);
        vm.expectEmit(true, true, true, true);
        emit LPAddressUpdated(lpAddress, true);
        token.setLiquidityPool(lpAddress, true);

        assertTrue(token.isLiquidityPool(lpAddress));
    }

    function test_RemoveLPAddress() public {
        vm.startPrank(governance);
        token.setLiquidityPool(lpAddress, true);
        assertTrue(token.isLiquidityPool(lpAddress));

        vm.expectEmit(true, true, true, true);
        emit LPAddressUpdated(lpAddress, false);
        token.setLiquidityPool(lpAddress, false);
        vm.stopPrank();

        assertFalse(token.isLiquidityPool(lpAddress));
    }

    function test_RevertWhen_NonGovernanceSetsLP() public {
        vm.prank(user1);
        vm.expectRevert(AppToken.OnlyGovernance.selector);
        token.setLiquidityPool(lpAddress, true);
    }

    function test_AdminCanSetLP() public {
        vm.prank(admin);
        token.setLiquidityPool(lpAddress, true);
        assertTrue(token.isLiquidityPool(lpAddress));
    }

    // =========== LP-Keyed Tax Tests ===========

    function test_NoTaxOnWalletToWalletTransfer() public {
        uint256 amount = 1000 ether;
        uint256 user1Before = token.balanceOf(user1);
        uint256 user2Before = token.balanceOf(user2);

        // Wallet-to-wallet transfer should NOT be taxed
        vm.prank(user1);
        token.transfer(user2, amount);

        // User2 should receive full amount (no tax)
        assertEq(token.balanceOf(user2), user2Before + amount);
        assertEq(token.balanceOf(user1), user1Before - amount);
    }

    function test_TaxOnTransferToLP() public {
        uint256 amount = 10_000 ether;

        // Set LP address
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        uint256 user1Before = token.balanceOf(user1);
        uint256 lpBefore = token.balanceOf(lpAddress);
        uint256 collectorBefore = token.balanceOf(address(feeCollector));

        // Transfer TO LP should be taxed (1% default)
        vm.prank(user1);
        token.transfer(lpAddress, amount);

        uint256 expectedFee = (amount * 100) / 10_000; // 1%
        uint256 expectedNet = amount - expectedFee;

        assertEq(token.balanceOf(lpAddress), lpBefore + expectedNet);
        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
        assertEq(token.balanceOf(user1), user1Before - amount);
    }

    function test_TaxOnTransferFromLP() public {
        uint256 amount = 10_000 ether;

        // Set LP address and give it tokens
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        vm.prank(admin);
        token.mint(lpAddress, 100_000 ether);

        uint256 lpBefore = token.balanceOf(lpAddress);
        uint256 user2Before = token.balanceOf(user2);
        uint256 collectorBefore = token.balanceOf(address(feeCollector));

        // Transfer FROM LP should be taxed
        vm.prank(lpAddress);
        token.transfer(user2, amount);

        uint256 expectedFee = (amount * 100) / 10_000;
        uint256 expectedNet = amount - expectedFee;

        assertEq(token.balanceOf(user2), user2Before + expectedNet);
        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
        assertEq(token.balanceOf(lpAddress), lpBefore - amount);
    }

    function test_NoTaxWhenLPIsExempt() public {
        uint256 amount = 10_000 ether;

        // Set LP address but also exempt it
        vm.startPrank(governance);
        token.setLiquidityPool(lpAddress, true);
        token.setTransferFeeExempt(lpAddress, true);
        vm.stopPrank();

        uint256 user1Before = token.balanceOf(user1);
        uint256 lpBefore = token.balanceOf(lpAddress);

        // Transfer TO exempt LP - no tax
        vm.prank(user1);
        token.transfer(lpAddress, amount);

        assertEq(token.balanceOf(lpAddress), lpBefore + amount); // Full amount
        assertEq(token.balanceOf(user1), user1Before - amount);
    }

    function test_NoTaxWhenSenderIsExempt() public {
        uint256 amount = 10_000 ether;

        // Set LP address
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        // Exempt user1
        vm.prank(governance);
        token.setTransferFeeExempt(user1, true);

        uint256 user1Before = token.balanceOf(user1);
        uint256 lpBefore = token.balanceOf(lpAddress);

        // Transfer from exempt user to LP - no tax
        vm.prank(user1);
        token.transfer(lpAddress, amount);

        assertEq(token.balanceOf(lpAddress), lpBefore + amount);
        assertEq(token.balanceOf(user1), user1Before - amount);
    }

    function test_RouterExemptFromTax() public {
        uint256 amount = 10_000 ether;

        // Set LP address
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        // Give router some tokens
        vm.prank(admin);
        token.mint(router, 100_000 ether);

        uint256 routerBefore = token.balanceOf(router);
        uint256 lpBefore = token.balanceOf(lpAddress);

        // Router transferring to LP - no tax (router is exempt)
        vm.prank(router);
        token.transfer(lpAddress, amount);

        assertEq(token.balanceOf(lpAddress), lpBefore + amount);
        assertEq(token.balanceOf(router), routerBefore - amount);
    }

    // =========== Tax Configuration Tests ===========

    function test_ZeroTaxDisablesTaxation() public {
        uint256 amount = 10_000 ether;

        // Set LP address
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        // Set fee to 0
        vm.prank(governance);
        token.setTransferFeeBps(0);

        uint256 user1Before = token.balanceOf(user1);
        uint256 lpBefore = token.balanceOf(lpAddress);

        // Transfer to LP with 0% fee - no tax
        vm.prank(user1);
        token.transfer(lpAddress, amount);

        assertEq(token.balanceOf(lpAddress), lpBefore + amount);
        assertEq(token.balanceOf(user1), user1Before - amount);
    }

    function test_CustomTaxRate() public {
        uint256 amount = 10_000 ether;

        // Set LP address
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        // Set fee to 2% (max)
        vm.prank(governance);
        token.setTransferFeeBps(200);

        uint256 user1Before = token.balanceOf(user1);
        uint256 lpBefore = token.balanceOf(lpAddress);
        uint256 collectorBefore = token.balanceOf(address(feeCollector));

        // Transfer to LP with 2% fee
        vm.prank(user1);
        token.transfer(lpAddress, amount);

        uint256 expectedFee = (amount * 200) / 10_000; // 2%
        uint256 expectedNet = amount - expectedFee;

        assertEq(token.balanceOf(lpAddress), lpBefore + expectedNet);
        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
    }

    // =========== FeeCollector Integration Tests ===========

    function test_TaxRoutedToFeeCollector() public {
        uint256 amount = 10_000 ether;

        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        uint256 collectorBefore = token.balanceOf(address(feeCollector));

        vm.prank(user1);
        token.transfer(lpAddress, amount);

        uint256 expectedFee = (amount * 100) / 10_000;
        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
    }

    // =========== Edge Cases ===========

    function test_LPToLPTransferIsTaxed() public {
        address lp2 = makeAddr("lp2");
        uint256 amount = 10_000 ether;

        // Set both as LP addresses
        vm.startPrank(governance);
        token.setLiquidityPool(lpAddress, true);
        token.setLiquidityPool(lp2, true);
        vm.stopPrank();

        // Give first LP tokens
        vm.prank(admin);
        token.mint(lpAddress, 100_000 ether);

        uint256 lpBefore = token.balanceOf(lpAddress);
        uint256 lp2Before = token.balanceOf(lp2);
        uint256 collectorBefore = token.balanceOf(address(feeCollector));

        // LP to LP transfer - should still be taxed
        vm.prank(lpAddress);
        token.transfer(lp2, amount);

        uint256 expectedFee = (amount * 100) / 10_000;
        uint256 expectedNet = amount - expectedFee;

        assertEq(token.balanceOf(lp2), lp2Before + expectedNet);
        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
    }

    function test_MintToLPNotTaxed() public {
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        uint256 lpBefore = token.balanceOf(lpAddress);

        // Minting to LP should not be taxed (from == address(0))
        vm.prank(admin);
        token.mint(lpAddress, 10_000 ether);

        assertEq(token.balanceOf(lpAddress), lpBefore + 10_000 ether);
    }

    function test_BurnFromLPNotTaxed() public {
        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        vm.prank(admin);
        token.mint(lpAddress, 10_000 ether);

        uint256 lpBefore = token.balanceOf(lpAddress);

        // Burning from LP should not be taxed (to == address(0))
        vm.prank(lpAddress);
        token.burn(5_000 ether);

        assertEq(token.balanceOf(lpAddress), lpBefore - 5_000 ether);
    }

    // =========== Fuzz Tests ===========

    function testFuzz_LPTaxCalculation(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        vm.prank(governance);
        token.setLiquidityPool(lpAddress, true);

        uint256 collectorBefore = token.balanceOf(address(feeCollector));
        uint256 lpBefore = token.balanceOf(lpAddress);

        vm.prank(user1);
        token.transfer(lpAddress, amount);

        uint256 expectedFee = (amount * 100) / 10_000;
        uint256 expectedNet = amount - expectedFee;

        assertEq(token.balanceOf(address(feeCollector)), collectorBefore + expectedFee);
        assertEq(token.balanceOf(lpAddress), lpBefore + expectedNet);
    }

    function testFuzz_WalletToWalletNoTax(uint256 amount) public {
        amount = bound(amount, 1, 100_000 ether);

        uint256 user2Before = token.balanceOf(user2);

        vm.prank(user1);
        token.transfer(user2, amount);

        // Full amount transferred (no tax)
        assertEq(token.balanceOf(user2), user2Before + amount);
    }
}

/// @notice Mock ELTA for FeeCollector tests
contract MockELTA is ERC20 {
    constructor() ERC20("Mock ELTA", "ELTA") {
        _mint(msg.sender, 77_000_000 ether);
    }
}
