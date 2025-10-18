// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAppFeeRouter } from "../../src/interfaces/IAppFeeRouter.sol";
import { IAppRewardsDistributor } from "../../src/interfaces/IAppRewardsDistributor.sol";
import { IElataXP } from "../../src/interfaces/IElataXP.sol";
import { IRewardsDistributor } from "../../src/interfaces/IRewardsDistributor.sol";

/**
 * @title MockAppFeeRouter
 * @notice Mock fee router for testing
 */
contract MockAppFeeRouter is IAppFeeRouter {
    uint256 public override feeBps = 100; // 1%

    function takeAndForwardFee(address, uint256) external pure override {
        // Do nothing in mock
    }

    function calculateFee(uint256 amount) external view override returns (uint256) {
        return (amount * feeBps) / 10_000;
    }
}

/**
 * @title MockAppRewardsDistributor
 * @notice Mock rewards distributor for testing
 */
contract MockAppRewardsDistributor is IAppRewardsDistributor {
    address[] public registered;

    function registerApp(address vault) external override {
        registered.push(vault);
    }

    function registerApp(address vault, address) external override {
        registered.push(vault);
    }

    function distribute(uint256) external pure override {
        // Do nothing in mock
    }

    function depositForApp(IERC20, uint256) external pure override {
        // Do nothing in mock
    }

    function claim(address, uint256) external pure override {
        // Do nothing in mock
    }

    function claimToken(address, IERC20, uint256) external pure override {
        // Do nothing in mock
    }

    function getRegisteredCount() external view returns (uint256) {
        return registered.length;
    }
}

/**
 * @title MockElataXP
 * @notice Mock ElataXP contract for testing
 */
contract MockElataXP is IElataXP {
    mapping(address => uint256) public balances;

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }
}

/**
 * @title MockRewardsDistributor
 * @notice Mock RewardsDistributor for testing
 */
contract MockRewardsDistributor is IRewardsDistributor {
    function depositVeInToken(IERC20, uint256) external pure override {
        // Do nothing in mock
    }

    function deposit(uint256) external pure override {
        // Do nothing in mock
    }
}
