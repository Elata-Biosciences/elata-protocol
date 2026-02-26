// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IFeeSwapper} from "./IFeeSwapper.sol";

/// @notice Legacy alias kept for older imports; the concrete implementation is now `FeeSwapper`.
interface IFeeRouterV2 is IFeeSwapper {}

