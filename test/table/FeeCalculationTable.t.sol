// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title FeeCalculationTable
 * @notice Table-driven tests for fee calculations with known expected outputs
 * @dev Systematically tests fee math across a comprehensive matrix of inputs
 *
 * Table testing ensures:
 * - All boundary conditions are covered
 * - Known edge cases are explicitly tested
 * - Regression testing for specific scenarios
 */
contract FeeCalculationTable is Test {
    // =========== Fee Split Tests ===========

    struct FeeSplitTestCase {
        string name;
        uint256 totalAmount;
        uint256 appStakersBps;
        uint256 veEltaBps;
        uint256 creatorBps;
        uint256 treasuryBps;
        uint256 referralBps;
        uint256 expectedAppStakers;
        uint256 expectedVeElta;
        uint256 expectedCreator;
        uint256 expectedTreasury;
        uint256 expectedReferral;
    }

    function getFeeSplitTestCases() internal pure returns (FeeSplitTestCase[] memory) {
        FeeSplitTestCase[] memory cases = new FeeSplitTestCase[](8);

        // Case 1: Standard 30/25/20/15/10 split with 1000 ELTA
        cases[0] = FeeSplitTestCase({
            name: "Standard split 1000 ELTA",
            totalAmount: 1000e18,
            appStakersBps: 3000,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 1500,
            referralBps: 1000,
            expectedAppStakers: 300e18,
            expectedVeElta: 250e18,
            expectedCreator: 200e18,
            expectedTreasury: 150e18,
            expectedReferral: 100e18
        });

        // Case 2: Minimum amount (1 wei)
        cases[1] = FeeSplitTestCase({
            name: "Minimum amount 1 wei",
            totalAmount: 1,
            appStakersBps: 3000,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 1500,
            referralBps: 1000,
            expectedAppStakers: 0, // 1 * 3000 / 10000 = 0
            expectedVeElta: 0,
            expectedCreator: 0,
            expectedTreasury: 0,
            expectedReferral: 0
        });

        // Case 3: Large amount (1M ELTA)
        cases[2] = FeeSplitTestCase({
            name: "Large amount 1M ELTA",
            totalAmount: 1_000_000e18,
            appStakersBps: 3000,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 1500,
            referralBps: 1000,
            expectedAppStakers: 300_000e18,
            expectedVeElta: 250_000e18,
            expectedCreator: 200_000e18,
            expectedTreasury: 150_000e18,
            expectedReferral: 100_000e18
        });

        // Case 4: No referral (referralBps = 0)
        cases[3] = FeeSplitTestCase({
            name: "No referral split",
            totalAmount: 1000e18,
            appStakersBps: 3500,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 2000,
            referralBps: 0,
            expectedAppStakers: 350e18,
            expectedVeElta: 250e18,
            expectedCreator: 200e18,
            expectedTreasury: 200e18,
            expectedReferral: 0
        });

        // Case 5: All to treasury
        cases[4] = FeeSplitTestCase({
            name: "All to treasury",
            totalAmount: 1000e18,
            appStakersBps: 0,
            veEltaBps: 0,
            creatorBps: 0,
            treasuryBps: 10000,
            referralBps: 0,
            expectedAppStakers: 0,
            expectedVeElta: 0,
            expectedCreator: 0,
            expectedTreasury: 1000e18,
            expectedReferral: 0
        });

        // Case 6: Even split
        cases[5] = FeeSplitTestCase({
            name: "Even 5-way split",
            totalAmount: 1000e18,
            appStakersBps: 2000,
            veEltaBps: 2000,
            creatorBps: 2000,
            treasuryBps: 2000,
            referralBps: 2000,
            expectedAppStakers: 200e18,
            expectedVeElta: 200e18,
            expectedCreator: 200e18,
            expectedTreasury: 200e18,
            expectedReferral: 200e18
        });

        // Case 7: Odd amount with rounding
        cases[6] = FeeSplitTestCase({
            name: "Odd amount 333 tokens",
            totalAmount: 333e18,
            appStakersBps: 3000,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 1500,
            referralBps: 1000,
            expectedAppStakers: 99900000000000000000, // 333 * 3000 / 10000 = 99.9
            expectedVeElta: 83250000000000000000, // 333 * 2500 / 10000 = 83.25
            expectedCreator: 66600000000000000000, // 333 * 2000 / 10000 = 66.6
            expectedTreasury: 49950000000000000000, // 333 * 1500 / 10000 = 49.95
            expectedReferral: 33300000000000000000 // 333 * 1000 / 10000 = 33.3
        });

        // Case 8: Zero amount
        cases[7] = FeeSplitTestCase({
            name: "Zero amount",
            totalAmount: 0,
            appStakersBps: 3000,
            veEltaBps: 2500,
            creatorBps: 2000,
            treasuryBps: 1500,
            referralBps: 1000,
            expectedAppStakers: 0,
            expectedVeElta: 0,
            expectedCreator: 0,
            expectedTreasury: 0,
            expectedReferral: 0
        });

        return cases;
    }

    function test_Table_FeeSplits() public pure {
        FeeSplitTestCase[] memory cases = getFeeSplitTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            FeeSplitTestCase memory tc = cases[i];

            // Calculate splits
            uint256 appStakers = (tc.totalAmount * tc.appStakersBps) / 10000;
            uint256 veElta = (tc.totalAmount * tc.veEltaBps) / 10000;
            uint256 creator = (tc.totalAmount * tc.creatorBps) / 10000;
            uint256 treasury = (tc.totalAmount * tc.treasuryBps) / 10000;
            uint256 referral = (tc.totalAmount * tc.referralBps) / 10000;

            // Assert each split
            assertEq(appStakers, tc.expectedAppStakers, string.concat(tc.name, ": appStakers mismatch"));
            assertEq(veElta, tc.expectedVeElta, string.concat(tc.name, ": veElta mismatch"));
            assertEq(creator, tc.expectedCreator, string.concat(tc.name, ": creator mismatch"));
            assertEq(treasury, tc.expectedTreasury, string.concat(tc.name, ": treasury mismatch"));
            assertEq(referral, tc.expectedReferral, string.concat(tc.name, ": referral mismatch"));

            // Verify splits sum to total (accounting for rounding loss)
            uint256 totalSplit = appStakers + veElta + creator + treasury + referral;
            assertLe(totalSplit, tc.totalAmount, string.concat(tc.name, ": splits exceed total"));
        }
    }

    // =========== Transfer Fee Tests ===========

    struct TransferFeeTestCase {
        string name;
        uint256 amount;
        uint16 feeBps;
        uint256 expectedFee;
        uint256 expectedNet;
    }

    function getTransferFeeTestCases() internal pure returns (TransferFeeTestCase[] memory) {
        TransferFeeTestCase[] memory cases = new TransferFeeTestCase[](10);

        // Case 1: Standard 1% fee
        cases[0] = TransferFeeTestCase({
            name: "1% fee on 1000 tokens", amount: 1000e18, feeBps: 100, expectedFee: 10e18, expectedNet: 990e18
        });

        // Case 2: Maximum fee (2%)
        cases[1] = TransferFeeTestCase({
            name: "Max 2% fee on 1000 tokens", amount: 1000e18, feeBps: 200, expectedFee: 20e18, expectedNet: 980e18
        });

        // Case 3: Zero fee
        cases[2] =
            TransferFeeTestCase({name: "Zero fee", amount: 1000e18, feeBps: 0, expectedFee: 0, expectedNet: 1000e18});

        // Case 4: Minimum amount with fee
        cases[3] = TransferFeeTestCase({
            name: "Minimum amount 1 wei",
            amount: 1,
            feeBps: 100,
            expectedFee: 0, // 1 * 100 / 10000 = 0
            expectedNet: 1
        });

        // Case 5: Large amount
        cases[4] = TransferFeeTestCase({
            name: "Large amount 10M tokens",
            amount: 10_000_000e18,
            feeBps: 100,
            expectedFee: 100_000e18,
            expectedNet: 9_900_000e18
        });

        // Case 6: 0.5% fee
        cases[5] = TransferFeeTestCase({
            name: "0.5% fee", amount: 1000e18, feeBps: 50, expectedFee: 5e18, expectedNet: 995e18
        });

        // Case 7: 1.5% fee
        cases[6] = TransferFeeTestCase({
            name: "1.5% fee", amount: 1000e18, feeBps: 150, expectedFee: 15e18, expectedNet: 985e18
        });

        // Case 8: Minimum non-zero fee (1 bps = 0.01%)
        cases[7] = TransferFeeTestCase({
            name: "Minimum 0.01% fee", amount: 10000e18, feeBps: 1, expectedFee: 1e18, expectedNet: 9999e18
        });

        // Case 9: Odd amount
        cases[8] = TransferFeeTestCase({
            name: "Odd amount 1337 tokens",
            amount: 1337e18,
            feeBps: 100,
            expectedFee: 13370000000000000000, // 1337 * 100 / 10000 = 13.37
            expectedNet: 1323630000000000000000 // 1337 - 13.37 = 1323.63
        });

        // Case 10: Zero amount
        cases[9] = TransferFeeTestCase({name: "Zero amount", amount: 0, feeBps: 100, expectedFee: 0, expectedNet: 0});

        return cases;
    }

    function test_Table_TransferFees() public pure {
        TransferFeeTestCase[] memory cases = getTransferFeeTestCases();

        for (uint256 i = 0; i < cases.length; i++) {
            TransferFeeTestCase memory tc = cases[i];

            // Calculate fee
            uint256 fee = (tc.amount * tc.feeBps) / 10000;
            uint256 net = tc.amount - fee;

            // Assert results
            assertEq(fee, tc.expectedFee, string.concat(tc.name, ": fee mismatch"));
            assertEq(net, tc.expectedNet, string.concat(tc.name, ": net mismatch"));
        }
    }

    // =========== Rewards Distribution Split Tests ===========

    struct RewardsSplitTestCase {
        string name;
        uint256 revenue;
        uint256 expectedApp; // 70%
        uint256 expectedVeElta; // 15%
        uint256 expectedTreasury; // 15%
    }

    function getRewardsSplitTestCases() internal pure returns (RewardsSplitTestCase[] memory) {
        RewardsSplitTestCase[] memory cases = new RewardsSplitTestCase[](6);

        // Case 1: Standard 1000 ELTA
        cases[0] = RewardsSplitTestCase({
            name: "1000 ELTA revenue",
            revenue: 1000e18,
            expectedApp: 700e18,
            expectedVeElta: 150e18,
            expectedTreasury: 150e18
        });

        // Case 2: Large revenue
        cases[1] = RewardsSplitTestCase({
            name: "1M ELTA revenue",
            revenue: 1_000_000e18,
            expectedApp: 700_000e18,
            expectedVeElta: 150_000e18,
            expectedTreasury: 150_000e18
        });

        // Case 3: Minimum amount
        cases[2] = RewardsSplitTestCase({
            name: "Minimum 1 wei",
            revenue: 1,
            expectedApp: 0, // 1 * 7000 / 10000 = 0
            expectedVeElta: 0, // 1 * 1500 / 10000 = 0
            expectedTreasury: 0
        });

        // Case 4: Amount that divides evenly
        cases[3] = RewardsSplitTestCase({
            name: "Evenly divisible 10000 ELTA",
            revenue: 10000e18,
            expectedApp: 7000e18,
            expectedVeElta: 1500e18,
            expectedTreasury: 1500e18
        });

        // Case 5: Odd amount
        cases[4] = RewardsSplitTestCase({
            name: "Odd amount 777 ELTA",
            revenue: 777e18,
            expectedApp: 543900000000000000000, // 777 * 7000 / 10000 = 543.9
            expectedVeElta: 116550000000000000000, // 777 * 1500 / 10000 = 116.55
            expectedTreasury: 116550000000000000000
        });

        // Case 6: Zero revenue
        cases[5] = RewardsSplitTestCase({
            name: "Zero revenue", revenue: 0, expectedApp: 0, expectedVeElta: 0, expectedTreasury: 0
        });

        return cases;
    }

    function test_Table_RewardsSplit() public pure {
        RewardsSplitTestCase[] memory cases = getRewardsSplitTestCases();

        uint256 BIPS_APP = 7000;
        uint256 BIPS_VEELTA = 1500;
        uint256 BIPS_TREASURY = 1500;

        for (uint256 i = 0; i < cases.length; i++) {
            RewardsSplitTestCase memory tc = cases[i];

            // Calculate splits
            uint256 appShare = (tc.revenue * BIPS_APP) / 10000;
            uint256 veEltaShare = (tc.revenue * BIPS_VEELTA) / 10000;
            uint256 treasuryShare = (tc.revenue * BIPS_TREASURY) / 10000;

            // Assert results
            assertEq(appShare, tc.expectedApp, string.concat(tc.name, ": app share mismatch"));
            assertEq(veEltaShare, tc.expectedVeElta, string.concat(tc.name, ": veElta share mismatch"));
            assertEq(treasuryShare, tc.expectedTreasury, string.concat(tc.name, ": treasury share mismatch"));

            // Verify sum doesn't exceed revenue
            uint256 total = appShare + veEltaShare + treasuryShare;
            assertLe(total, tc.revenue, string.concat(tc.name, ": total exceeds revenue"));
        }
    }
}
