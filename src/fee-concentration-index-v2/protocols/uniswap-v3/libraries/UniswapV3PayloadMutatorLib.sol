// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {V3_SWAP_SIG} from "./EventSignatures.sol";
import {
    getLastTick, setLastTick
} from "../modules/UniswapV3ReactVMStorageMod.sol";

/// @dev Enriches raw V3 log data before callback emission.
/// Swap events get tickBefore injected from ReactVM shadow state.
/// Returns: abi.encode(IReactive.LogRecord, int24 tickBefore)
function mutateV3Payload(IReactive.LogRecord memory log) returns (bytes memory) {
    uint256 sig = log.topic_0;

    if (sig == V3_SWAP_SIG) {
        uint256 chainId_ = log.chain_id;
        address pool = log._contract;

        // Decode post-swap tick from log data
        // Swap data: (int256 amount0, int256 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick)
        (,,,, int24 tickAfter) = abi.decode(log.data, (int256, int256, uint160, uint128, int24));

        // Inject pre-swap tick from shadow state
        (int24 prevTick, bool isSet) = getLastTick(chainId_, pool);
        int24 tickBefore = isSet ? prevTick : tickAfter;
        setLastTick(chainId_, pool, tickAfter);

        return abi.encode(log, tickBefore);
    }

    // Non-swap: no enrichment needed
    return abi.encode(log, int24(0));
}
