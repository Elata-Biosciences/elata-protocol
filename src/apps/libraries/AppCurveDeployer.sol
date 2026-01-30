// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAppFeeRouter} from "../../interfaces/IAppFeeRouter.sol";
import {IElataPoints} from "../../interfaces/IElataPoints.sol";
import {IUniswapV2Router02} from "../../interfaces/IUniswapV2Router02.sol";
import {AppBondingCurve} from "../AppBondingCurve.sol";
import {AppToken} from "../AppToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        IElataPoints elataPoints,
        address governance,
        uint256 activationDelay,
        uint256 maxDuration,
        address feeCollector,
        address referralRegistry
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
                elataPoints,
                governance,
                activationDelay,
                maxDuration,
                creator,
                feeCollector,
                referralRegistry
            )
        );
    }
}
