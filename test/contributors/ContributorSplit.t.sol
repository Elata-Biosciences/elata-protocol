// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ContributorSplit} from "../../src/contributors/ContributorSplit.sol";
import {FeeKind} from "../../src/fees/FeeKind.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ContributorSplitTest is Test {
    ContributorSplit split;
    MockToken token;
    MockToken token2;

    address ownerSafe = makeAddr("ownerSafe");
    address feeRouter = makeAddr("feeRouter");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        split = new ContributorSplit();
        token = new MockToken();
        token2 = new MockToken();

        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](2);
        contributors[0] = IContributorSplit.Contributor({account: alice, shares: 60});
        contributors[1] = IContributorSplit.Contributor({account: bob, shares: 40});

        split.initialize(1, ownerSafe, feeRouter, 200, contributors);
    }

    function test_ReleasableAndReleaseSplitsProRata() public {
        token.mint(address(split), 1000 ether);

        assertEq(split.releasable(address(token), alice), 600 ether);
        assertEq(split.releasable(address(token), bob), 400 ether);

        split.release(address(token), alice);
        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(split.releasable(address(token), alice), 0);

        split.release(address(token), bob);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token.balanceOf(address(split)), 0);
    }

    function test_SetContributorsOnlyBeforeFirstPayment() public {
        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](1);
        contributors[0] = IContributorSplit.Contributor({account: alice, shares: 100});

        vm.prank(ownerSafe);
        split.setContributors(contributors);
        assertEq(split.totalShares(), 100);

        // First payment locks contributor reconfiguration.
        vm.prank(feeRouter);
        split.onFeeReceived(FeeKind.CONTENT_SALE, address(token), 1, address(this));

        vm.prank(ownerSafe);
        vm.expectRevert(ContributorSplit.ContributorsLocked.selector);
        split.setContributors(contributors);
    }

    function test_ReleaseAccountingIsIndependentPerAsset() public {
        token.mint(address(split), 1000 ether);
        token2.mint(address(split), 2000 ether);

        // token: 60/40 split
        assertEq(split.releasable(address(token), alice), 600 ether);
        assertEq(split.releasable(address(token), bob), 400 ether);

        // token2: 60/40 split
        assertEq(split.releasable(address(token2), alice), 1200 ether);
        assertEq(split.releasable(address(token2), bob), 800 ether);

        split.release(address(token), alice);
        split.release(address(token2), alice);

        assertEq(token.balanceOf(alice), 600 ether);
        assertEq(token2.balanceOf(alice), 1200 ether);

        // Bob can still withdraw his share for each asset.
        split.release(address(token), bob);
        split.release(address(token2), bob);
        assertEq(token.balanceOf(bob), 400 ether);
        assertEq(token2.balanceOf(bob), 800 ether);
    }

    function test_RevertWhen_OnFeeReceivedNotCalledByFeeRouter() public {
        vm.prank(ownerSafe);
        vm.expectRevert(ContributorSplit.OnlyFeeRouter.selector);
        split.onFeeReceived(FeeKind.CONTENT_SALE, address(token), 1, address(this));
    }
}

