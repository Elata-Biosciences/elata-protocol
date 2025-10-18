// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router02 } from "../../interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../interfaces/IAppFeeRouter.sol";
import { IElataXP } from "../../interfaces/IElataXP.sol";
import { AppTokenDeployer } from "./AppTokenDeployer.sol";
import { AppVaultDeployer } from "./AppVaultDeployer.sol";
import { AppCurveDeployer } from "./AppCurveDeployer.sol";

/**
 * @title AppDeploymentLib
 * @notice Minimal library for deploying app contracts
 * @dev Delegates to specialized deployer libraries to reduce size
 */
library AppDeploymentLib {
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 supply,
        address creator,
        address factory,
        address governance,
        address appRewardsDistributor,
        address rewardsDistributor,
        address treasury
    ) external returns (address) {
        return AppTokenDeployer.deployToken(
            name,
            symbol,
            decimals,
            supply,
            creator,
            factory,
            governance,
            appRewardsDistributor,
            rewardsDistributor,
            treasury
        );
    }

    function deployVault(string calldata name, string calldata symbol, address token, address owner)
        external
        returns (address)
    {
        return AppVaultDeployer.deployVault(name, symbol, token, owner);
    }

    function deployCurve(
        uint256 appId,
        address factory,
        IERC20 elta,
        address token,
        IUniswapV2Router02 router,
        uint256 targetRaised,
        uint256 lpLockDuration,
        address creator,
        address treasury,
        IAppFeeRouter appFeeRouter,
        IElataXP elataXP,
        address governance
    ) external returns (address) {
        return AppCurveDeployer.deployCurve(
            appId,
            factory,
            elta,
            token,
            router,
            targetRaised,
            lpLockDuration,
            creator,
            treasury,
            appFeeRouter,
            elataXP,
            governance
        );
    }
}
