// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";

/// @dev Enriches raw V3 log data before callback emission.
/// Open extension point — other protocols implement their own mutator.
///
/// Returns: abi.encode(IReactive.LogRecord, bytes enrichment)
/// where enrichment is empty for now. Future: Swap gets pre-swap tick injection.

function mutateV3Payload(
    IReactive.LogRecord memory log
) returns (bytes memory) {
    return abi.encode(log, "");
}
