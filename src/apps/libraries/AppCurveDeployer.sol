// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Router02 } from "../../interfaces/IUniswapV2Router02.sol";
import { IAppFeeRouter } from "../../interfaces/IAppFeeRouter.sol";
import { IElataXP } from "../../interfaces/IElataXP.sol";
import { AppToken } from "../AppToken.sol";
import { AppBondingCurve } from "../AppBondingCurve.sol";

/**
 * @title AppCurveDeployer
 * @notice Library for deploying AppBondingCurve contracts
 * @dev Separated to reduce AppDeploymentLib size
 */
library AppCurveDeployer {
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
        return address(
            new AppBondingCurve(
                appId,
                factory,
                elta,
                AppToken(token),
                router,
                targetRaised,
                lpLockDuration,
                creator,
                treasury,
                appFeeRouter,
                elataXP,
                governance
            )
        );
    }
}
