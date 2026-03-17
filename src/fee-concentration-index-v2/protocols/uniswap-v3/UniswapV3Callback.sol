// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IReactive} from "reactive-lib/interfaces/IReactive.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {V3MintData, V3SwapData, V3BurnData} from "reactive-hooks/types/ReactiveCallbackDataMod.sol";
import {fromUniswapV3PoolToPoolKey} from "./libraries/UniswapV3PoolKeyLib.sol";
import {
    encodeAfterAddLiquidity, encodeBeforeSwap, encodeAfterSwap,
    encodeBeforeRemoveLiquidity, encodeAfterRemoveLiquidity,
    decodeV3MintFromLog, decodeV3SwapFromLog, decodeV3BurnFromLog
} from "./libraries/V3HookDataLib.sol";
import {V3_MINT_SIG, V3_SWAP_SIG, V3_BURN_SIG} from "./libraries/EventSignatures.sol";

/// @title UniswapV3Callback
/// @dev Receives reactive callbacks from the Reactive Network callback proxy.
/// Decodes V3 event data, builds V4-shaped calldata with hookData,
/// and calls FCI V2's hook functions.
/// Uses V1-proven authorizedCallers pattern for callback authentication.
contract UniswapV3Callback {
    IHooks immutable fci;
    address public rvmId;
    address immutable owner;
    mapping(address => bool) public authorizedCallers;

    error OnlyOwner();
    error InvalidRvmId();
    error NotAuthorized();
    error InsufficientFunds();
    error TransferFailed();

    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    event RvmIdUpdated(address indexed oldRvmId, address indexed newRvmId);

    constructor(address fci_, address callbackProxy_, address rvmId_) payable {
        fci = IHooks(fci_);
        owner = msg.sender;
        rvmId = rvmId_;
        authorizedCallers[callbackProxy_] = true;
    }

    function setRvmId(address rvmId_) external {
        if (msg.sender != owner) revert OnlyOwner();
        address old = rvmId;
        rvmId = rvmId_;
        emit RvmIdUpdated(old, rvmId_);
    }

    function setAuthorized(address caller, bool authorized) external {
        if (msg.sender != owner) revert OnlyOwner();
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {}

    function unlockCallbackReactive(address rvmSender, bytes calldata data) external {
        if (!authorizedCallers[msg.sender]) revert NotAuthorized();
        if (rvmSender != rvmId) revert InvalidRvmId();

        (IReactive.LogRecord memory log, int24 tickBefore) = abi.decode(data, (IReactive.LogRecord, int24));
        uint256 sig = log.topic_0;

        if (sig == V3_MINT_SIG) {
            _handleMint(decodeV3MintFromLog(log));
        } else if (sig == V3_SWAP_SIG) {
            V3SwapData memory swapData = decodeV3SwapFromLog(log);
            swapData.tickBefore = tickBefore;
            _handleSwap(swapData);
        } else if (sig == V3_BURN_SIG) {
            _handleBurn(decodeV3BurnFromLog(log));
        }
    }

    function pay(uint256 amount) external {
        if (!authorizedCallers[msg.sender]) revert NotAuthorized();
        if (address(this).balance < amount) revert InsufficientFunds();
        if (amount > 0) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        }
    }

    receive() external payable {}

    function _handleMint(V3MintData memory data) internal {
        PoolKey memory key = fromUniswapV3PoolToPoolKey(data.pool, fci);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: data.tickLower,
            tickUpper: data.tickUpper,
            liquidityDelta: int256(uint256(data.liquidity)),
            salt: bytes32(0)
        });

        fci.afterAddLiquidity(
            data.owner, key, params,
            BalanceDelta.wrap(0), BalanceDelta.wrap(0),
            encodeAfterAddLiquidity(address(data.pool))
        );
    }

    function _handleSwap(V3SwapData memory data) internal {
        PoolKey memory key = fromUniswapV3PoolToPoolKey(data.pool, fci);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 0,
            sqrtPriceLimitX96: 0
        });

        fci.beforeSwap(address(0), key, params, encodeBeforeSwap(address(data.pool), data.tickBefore));
        fci.afterSwap(address(0), key, params, BalanceDelta.wrap(0), encodeAfterSwap(address(data.pool), data.tickBefore));
    }

    function _handleBurn(V3BurnData memory data) internal {
        if (data.liquidity == 0) return;

        PoolKey memory key = fromUniswapV3PoolToPoolKey(data.pool, fci);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: data.tickLower,
            tickUpper: data.tickUpper,
            liquidityDelta: -int256(uint256(data.liquidity)),
            salt: bytes32(0)
        });

        fci.beforeRemoveLiquidity(data.owner, key, params, encodeBeforeRemoveLiquidity(address(data.pool)));
        fci.afterRemoveLiquidity(
            data.owner, key, params,
            BalanceDelta.wrap(0), BalanceDelta.wrap(0),
            encodeAfterRemoveLiquidity(address(data.pool))
        );
    }
}
