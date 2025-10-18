// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AppToken } from "../AppToken.sol";

/**
 * @title AppTokenDeployer
 * @notice Library for deploying AppToken contracts
 * @dev Separated to reduce AppDeploymentLib size
 */
library AppTokenDeployer {
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
        return address(
            new AppToken(
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
            )
        );
    }
}
