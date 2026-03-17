// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {ISubscriptionService} from "reactive-lib/interfaces/ISubscriptionService.sol";
import {coverDebt, depositToSystem} from "reactive-hooks/modules/DebtMod.sol";
import {SYSTEM_CONTRACT} from "reactive-hooks/libraries/DebtLib.sol";
import {requireVM, reactVmStorage} from "reactive-hooks/modules/ReactVMMod.sol";
import {ReactVm} from "reactive-hooks/types/ReactVM.sol";
import {REACTIVE_IGNORE} from "reactive-hooks/libraries/SubscriptionLib.sol";
import {POOL_ADDED_SIG} from "@fee-concentration-index-v2/libraries/PoolAddedSig.sol";
import {handlePoolAdded, dispatchEvent} from "@fee-concentration-index-v2/modules/ReactiveDispatchMod.sol";

/// @title UniswapV3Reactive
/// @dev Reactive Network contract for V3 reactive integration.
/// Dual-instance: RN subscribes to PoolAdded from facet on origin chain,
/// ReactVM auto-subscribes to V3 pool events via EDT + dispatches to callback.
contract UniswapV3Reactive {
    ISubscriptionService immutable service;

    error OnlyReactVM();

    constructor(uint256 originChainId, address facetAddress) payable {
        service = ISubscriptionService(SYSTEM_CONTRACT);

        // Initialize ReactVM storage for requireVM() checks
        // size == 0 → ReactVM instance (SystemContract has no code)
        // size > 0  → RN instance (SystemContract exists)
        uint256 size;
        assembly { size := extcodesize(0x0000000000000000000000000000000000fffFfF) }
        reactVmStorage().reactVm = ReactVm.wrap(size == 0);

        // RN instance: subscribe to PoolAdded from facet on origin chain
        if (size > 0) {
            service.subscribe(originChainId, facetAddress, POOL_ADDED_SIG, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            depositToSystem(address(this));
        }
    }

    function react(IReactive.LogRecord calldata log) external {
        requireVM();

        if (log.topic_0 == POOL_ADDED_SIG) {
            handlePoolAdded(log, service);
            return;
        }

        dispatchEvent(log);
    }

    function fund() external payable {
        depositToSystem(address(this));
    }

    receive() external payable {
        coverDebt(address(this));
    }
}
