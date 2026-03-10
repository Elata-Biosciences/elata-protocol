// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AppStakingVault} from "../AppStakingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AppVaultDeployer
 * @author Elata Biosciences
 * @custom:security-contact security@elata.bio
 * @notice Library for deploying AppStakingVault contracts.
 * @dev Separated to reduce AppDeploymentLib bytecode size.
 */
library AppVaultDeployer {
    function deployVault(string calldata name, string calldata symbol, address token, address owner)
        external
        returns (address)
    {
        return address(new AppStakingVault(name, symbol, IERC20(token), owner));
    }
}
