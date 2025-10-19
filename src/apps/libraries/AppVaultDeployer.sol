// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AppStakingVault } from "../AppStakingVault.sol";

/**
 * @title AppVaultDeployer
 * @notice Library for deploying AppStakingVault contracts
 * @dev Separated to reduce AppDeploymentLib size
 */
library AppVaultDeployer {
    function deployVault(string calldata name, string calldata symbol, address token, address owner)
        external
        returns (address)
    {
        return address(new AppStakingVault(name, symbol, IERC20(token), owner));
    }
}
