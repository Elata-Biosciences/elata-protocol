// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {AppToken} from "../../../src/apps/AppToken.sol";

/**
 * @title AppTokenTaxHandler
 * @notice Handler for AppToken LP-keyed transfer tax invariant testing
 * @dev Tests per Protocol Changes 21.2:
 *      - wallet-to-wallet transfer: no tax
 *      - wallet-to-LP transfer: tax applied
 *      - router-exempt swaps do not self-tax
 *      - changing LP allowlist changes tax behavior immediately
 */
contract AppTokenTaxHandler is CommonBase, StdCheats, StdUtils {
    AppToken public appToken;
    address public admin;
    address public governance;

    // Test addresses
    address[] public wallets;
    address[] public liquidityPools;
    address[] public exemptAddresses;

    // Ghost variables
    uint256 public ghost_walletToWalletTransfers;
    uint256 public ghost_walletToLpTransfers;
    uint256 public ghost_lpToWalletTransfers;
    uint256 public ghost_exemptTransfers;
    uint256 public ghost_totalTaxCollected;
    uint256 public ghost_lpAllowlistChanges;

    // Track expected vs actual tax for verification
    uint256 public ghost_expectedTax;
    uint256 public ghost_actualTax;

    // Tracking for tax accounting
    mapping(address => uint256) public lastBalances;

    constructor(AppToken _appToken, address _admin, address _governance) {
        appToken = _appToken;
        admin = _admin;
        governance = _governance;

        // Create test wallets
        for (uint256 i = 0; i < 5; i++) {
            address wallet = makeAddr(string(abi.encodePacked("wallet", i)));
            wallets.push(wallet);
        }

        // Create test LP addresses
        for (uint256 i = 0; i < 3; i++) {
            address lp = makeAddr(string(abi.encodePacked("lp", i)));
            liquidityPools.push(lp);
        }
    }

    // =========== Transfer Actions ===========

    /**
     * @notice Transfer between two wallets (should NOT be taxed)
     */
    function walletToWalletTransfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        fromIndex = bound(fromIndex, 0, wallets.length - 1);
        toIndex = bound(toIndex, 0, wallets.length - 1);
        if (fromIndex == toIndex) toIndex = (toIndex + 1) % wallets.length;

        address from = wallets[fromIndex];
        address to = wallets[toIndex];

        uint256 fromBalance = appToken.balanceOf(from);
        if (fromBalance == 0) return;

        amount = bound(amount, 1, fromBalance);

        uint256 toBalanceBefore = appToken.balanceOf(to);

        vm.prank(from);
        appToken.transfer(to, amount);

        uint256 toBalanceAfter = appToken.balanceOf(to);
        uint256 received = toBalanceAfter - toBalanceBefore;

        // Wallet-to-wallet should NOT have tax
        // received should equal amount sent
        ghost_walletToWalletTransfers++;

        // If tax was applied (shouldn't happen), track it
        if (received < amount) {
            ghost_actualTax += (amount - received);
        }
    }

    /**
     * @notice Transfer from wallet to LP (SHOULD be taxed)
     */
    function walletToLpTransfer(uint256 walletIndex, uint256 lpIndex, uint256 amount) external {
        walletIndex = bound(walletIndex, 0, wallets.length - 1);
        lpIndex = bound(lpIndex, 0, liquidityPools.length - 1);

        address from = wallets[walletIndex];
        address to = liquidityPools[lpIndex];

        // Ensure LP is registered
        if (!appToken.isLiquidityPool(to)) {
            vm.prank(governance);
            appToken.setLiquidityPool(to, true);
            ghost_lpAllowlistChanges++;
        }

        uint256 fromBalance = appToken.balanceOf(from);
        if (fromBalance == 0) return;

        amount = bound(amount, 1, fromBalance);

        uint256 toBalanceBefore = appToken.balanceOf(to);
        uint16 feeBps = appToken.transferFeeBps();
        uint256 expectedFee = (amount * feeBps) / 10_000;

        vm.prank(from);
        appToken.transfer(to, amount);

        uint256 toBalanceAfter = appToken.balanceOf(to);
        uint256 received = toBalanceAfter - toBalanceBefore;

        ghost_walletToLpTransfers++;
        ghost_expectedTax += expectedFee;
        ghost_actualTax += (amount - received);
        ghost_totalTaxCollected += (amount - received);
    }

    /**
     * @notice Transfer from LP to wallet (SHOULD be taxed)
     */
    function lpToWalletTransfer(uint256 lpIndex, uint256 walletIndex, uint256 amount) external {
        lpIndex = bound(lpIndex, 0, liquidityPools.length - 1);
        walletIndex = bound(walletIndex, 0, wallets.length - 1);

        address from = liquidityPools[lpIndex];
        address to = wallets[walletIndex];

        // Ensure LP is registered
        if (!appToken.isLiquidityPool(from)) {
            vm.prank(governance);
            appToken.setLiquidityPool(from, true);
            ghost_lpAllowlistChanges++;
        }

        uint256 fromBalance = appToken.balanceOf(from);
        if (fromBalance == 0) return;

        amount = bound(amount, 1, fromBalance);

        uint256 toBalanceBefore = appToken.balanceOf(to);
        uint16 feeBps = appToken.transferFeeBps();
        uint256 expectedFee = (amount * feeBps) / 10_000;

        vm.prank(from);
        appToken.transfer(to, amount);

        uint256 toBalanceAfter = appToken.balanceOf(to);
        uint256 received = toBalanceAfter - toBalanceBefore;

        ghost_lpToWalletTransfers++;
        ghost_expectedTax += expectedFee;
        ghost_actualTax += (amount - received);
        ghost_totalTaxCollected += (amount - received);
    }

    /**
     * @notice Transfer from exempt address (should NOT be taxed regardless of LP)
     */
    function exemptTransfer(uint256 lpIndex, uint256 amount) external {
        lpIndex = bound(lpIndex, 0, liquidityPools.length - 1);
        address to = liquidityPools[lpIndex];

        // Use governance as exempt sender
        address from = governance;

        uint256 fromBalance = appToken.balanceOf(from);
        if (fromBalance == 0) return;

        amount = bound(amount, 1, fromBalance);

        // Ensure LP is registered
        if (!appToken.isLiquidityPool(to)) {
            vm.prank(governance);
            appToken.setLiquidityPool(to, true);
            ghost_lpAllowlistChanges++;
        }

        uint256 toBalanceBefore = appToken.balanceOf(to);

        vm.prank(from);
        appToken.transfer(to, amount);

        uint256 toBalanceAfter = appToken.balanceOf(to);
        uint256 received = toBalanceAfter - toBalanceBefore;

        ghost_exemptTransfers++;

        // Exempt transfer should NOT have tax
        if (received < amount) {
            ghost_actualTax += (amount - received);
        }
    }

    // =========== LP Allowlist Actions ===========

    /**
     * @notice Add address to LP allowlist
     */
    function addLiquidityPool(uint256 lpIndex) external {
        lpIndex = bound(lpIndex, 0, liquidityPools.length - 1);
        address lp = liquidityPools[lpIndex];

        vm.prank(governance);
        appToken.setLiquidityPool(lp, true);
        ghost_lpAllowlistChanges++;
    }

    /**
     * @notice Remove address from LP allowlist
     */
    function removeLiquidityPool(uint256 lpIndex) external {
        lpIndex = bound(lpIndex, 0, liquidityPools.length - 1);
        address lp = liquidityPools[lpIndex];

        vm.prank(governance);
        appToken.setLiquidityPool(lp, false);
        ghost_lpAllowlistChanges++;
    }

    /**
     * @notice Change transfer fee BPS
     */
    function setTransferFeeBps(uint16 newBps) external {
        newBps = uint16(bound(newBps, 0, 200)); // Max 2%

        vm.prank(governance);
        appToken.setTransferFeeBps(newBps);
    }

    // =========== View Helpers ===========

    function getWallet(uint256 index) external view returns (address) {
        require(index < wallets.length, "Index out of bounds");
        return wallets[index];
    }

    function getLiquidityPool(uint256 index) external view returns (address) {
        require(index < liquidityPools.length, "Index out of bounds");
        return liquidityPools[index];
    }

    function getWalletCount() external view returns (uint256) {
        return wallets.length;
    }

    function getLiquidityPoolCount() external view returns (uint256) {
        return liquidityPools.length;
    }

    function isLpRegistered(uint256 lpIndex) external view returns (bool) {
        if (lpIndex >= liquidityPools.length) return false;
        return appToken.isLiquidityPool(liquidityPools[lpIndex]);
    }
}
