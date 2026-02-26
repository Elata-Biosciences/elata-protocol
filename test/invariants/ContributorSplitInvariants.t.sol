// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ContributorSplit} from "../../src/contributors/ContributorSplit.sol";
import {IContributorSplit} from "../../src/interfaces/IContributorSplit.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ContributorSplitHandler is Test {
    ContributorSplit public split;
    MockToken public token;

    address public alice;
    address public bob;

    uint256 public ghost_minted;

    constructor(ContributorSplit _split, MockToken _token, address _alice, address _bob) {
        split = _split;
        token = _token;
        alice = _alice;
        bob = _bob;
    }

    function mintToSplit(uint256 amount) external {
        amount = 1 + (amount % (10_000 ether));
        token.mint(address(split), amount);
        ghost_minted += amount;
    }

    function releaseAlice() external {
        split.release(address(token), alice);
    }

    function releaseBob() external {
        split.release(address(token), bob);
    }
}

contract ContributorSplitInvariants is Test {
    ContributorSplit public split;
    MockToken public token;
    ContributorSplitHandler public handler;

    address public ownerSafe = makeAddr("ownerSafe");
    address public feeRouter = makeAddr("feeRouter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        split = new ContributorSplit();
        token = new MockToken();

        IContributorSplit.Contributor[] memory contributors = new IContributorSplit.Contributor[](2);
        contributors[0] = IContributorSplit.Contributor({account: alice, shares: 60});
        contributors[1] = IContributorSplit.Contributor({account: bob, shares: 40});
        split.initialize(1, ownerSafe, feeRouter, 200, contributors);

        handler = new ContributorSplitHandler(split, token, alice, bob);
        targetContract(address(handler));
    }

    function invariant_ConservesTokenBalanceAcrossReleases() public view {
        uint256 total = token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(address(split));
        assertEq(total, handler.ghost_minted(), "Token accounting not conserved");
    }

    function invariant_ReleasableNeverExceedsSplitBalancePlusReleased() public view {
        // A weaker but useful sanity check: releasable amounts can't exceed total minted.
        uint256 relA = split.releasable(address(token), alice);
        uint256 relB = split.releasable(address(token), bob);
        assertLe(relA + relB, handler.ghost_minted(), "Releasable exceeds minted");
    }
}

