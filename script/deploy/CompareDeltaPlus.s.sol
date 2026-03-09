// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IFeeConcentrationIndex} from "../../src/fee-concentration-index/interfaces/IFeeConcentrationIndex.sol";
import {
    resolveTokens,
    resolveV3,
    unichainSepoliaFCIHook,
    sepoliaFCI,
    SEPOLIA,
    UNICHAIN_SEPOLIA
} from "../utils/Deployments.sol";
import {fromV3Pool} from "../../src/reactive-integration/libraries/PoolKeyExtMod.sol";
import "../utils/Constants.sol";

contract CompareDeltaPlusScript is Script, StdAssertions {
    function run() public {
        // ── V4 side: Unichain Sepolia ──
        uint256 v4Fork = vm.createFork(vm.rpcUrl("unichain_sepolia"));
        vm.selectFork(v4Fork);

        (address tA, address tB) = resolveTokens(UNICHAIN_SEPOLIA);
        (address c0, address c1) = tA < tB ? (tA, tB) : (tB, tA);
        address fciHook = unichainSepoliaFCIHook();

        PoolKey memory v4Key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 500,
            tickSpacing: int24(TICK_SPACING),
            hooks: IHooks(fciHook)
        });

        IFeeConcentrationIndex v4Fci = IFeeConcentrationIndex(fciHook);
        uint128 v4Delta = v4Fci.getDeltaPlus(v4Key, false);
        console2.log("[V4] deltaPlus = %d", uint256(v4Delta));

        // ── V3 side: Eth Sepolia ──
        uint256 v3Fork = vm.createFork(vm.rpcUrl("sepolia"));
        vm.selectFork(v3Fork);

        (,, IFeeConcentrationIndex v3Fci) = resolveV3(SEPOLIA);
        (address sA, address sB) = resolveTokens(SEPOLIA);
        (address s0, address s1) = sA < sB ? (sA, sB) : (sB, sA);

        // V3 reactive path uses reactive=true
        PoolKey memory v3Key = PoolKey({
            currency0: Currency.wrap(s0),
            currency1: Currency.wrap(s1),
            fee: 500,
            tickSpacing: int24(TICK_SPACING),
            hooks: IHooks(address(0))
        });

        uint128 v3Delta = v3Fci.getDeltaPlus(v3Key, true);
        console2.log("[V3] deltaPlus (reactive) = %d", uint256(v3Delta));

        // ── Compare ──
        assertEq(
            uint256(v4Delta),
            uint256(v3Delta),
            "deltaPlus mismatch: V4 local vs V3 reactive"
        );
        console2.log("=== PASS: deltaPlus matches ===");
    }
}
