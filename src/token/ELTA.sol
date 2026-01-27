// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title ELTA Token
 * @notice Fixed-supply base token of the Elata ecosystem.
 * @dev Minted once at deployment. No roles, no upgrades, no admin keys.
 *      Governance power comes from VeELTA (vote-escrowed ELTA).
 */
contract ELTA is ERC20, ERC20Burnable, ERC20Permit {
    uint256 public constant MAX_SUPPLY = 77_000_000e18;

    constructor(address treasury) ERC20("Elata", "ELTA") ERC20Permit("Elata") {
        require(treasury != address(0), "ELTA: zero address");
        _mint(treasury, MAX_SUPPLY);
    }
}
