// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UNISWAP_V3_REACTIVE} from "@fee-concentration-index-v2/types/FlagsRegistry.sol";
import {AFTER_ADD_LIQUIDITY} from "./V3ActionTypes.sol";

// hookData layout: FLAG (2) | pool (20) | action (1)

function encodeAfterAddLiquidity(address pool) pure returns (bytes memory) {
    return abi.encodePacked(UNISWAP_V3_REACTIVE, pool, AFTER_ADD_LIQUIDITY);
}

// ── Common decoders (header) ──

function decodePoolAddress(bytes calldata hookData) pure returns (address pool) {
    assembly { pool := shr(96, calldataload(add(hookData.offset, 2))) }
}

function decodeActionType(bytes calldata hookData) pure returns (uint8 action) {
    action = uint8(hookData[22]);
}
