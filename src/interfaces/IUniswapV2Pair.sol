// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUniswapV2Pair {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
}
