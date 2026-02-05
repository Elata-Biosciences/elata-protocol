// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppToken} from "../AppToken.sol";

/**
 * @title AppTokenDeployer
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Library for deploying AppToken contracts.
 * @dev Separated to reduce AppDeploymentLib bytecode size.
 */
library AppTokenDeployer {
    function deployToken(AppToken.InitParams memory params) external returns (address) {
        return address(new AppToken(params));
    }
}
