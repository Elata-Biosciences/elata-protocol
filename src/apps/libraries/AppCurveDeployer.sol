// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppBondingCurve} from "../AppBondingCurve.sol";

/**
 * @title AppCurveDeployer
 * @notice Library for deploying AppBondingCurve contracts
 * @dev Separated to reduce AppDeploymentLib size
 */
library AppCurveDeployer {
    function deployCurve(AppBondingCurve.InitParams memory params) external returns (address) {
        return address(new AppBondingCurve(params));
    }
}
