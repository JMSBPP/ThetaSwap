// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {console2} from "forge-std/console2.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IFeeConcentrationIndex} from "../../src/fee-concentration-index/interfaces/IFeeConcentrationIndex.sol";
import {
    Scenario,
    Recipe,
    deltaPlusFactory,
    registerV3Pool,
    registerV4Pool,
    poolKey,
    recipeCrowdout,
    crowdoutPhase1,
    crowdoutPhase2,
    crowdoutPhase3,
    DELTA_EQUILIBRIUM,
    DELTA_MILD,
    DELTA_CROWDOUT
} from "../types/Scenario.sol";
import {Accounts, initAccounts} from "../types/Accounts.sol";
import {Protocol} from "../types/Protocol.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {
    Deployments,
    resolveDeployments,
    resolveV3,
    resolveTokens,
    unichainSepoliaFCIHook,
    ethSepoliaFCIHook,
    SEPOLIA,
    UNICHAIN_SEPOLIA
} from "../utils/Deployments.sol";
import "../utils/Constants.sol";


// Broadcasts real transactions to fabricate a target delta-plus on-chain.
// The reactive adapter hears the V3 Mint/Burn/Swap events and updates FCI.
//
// Usage:
//   # Single-block recipes (equilibrium, mild):
//   forge script FeeConcentrationIndexBuilderScript --sig "buildEquilibrium()" --broadcast --rpc-url $SEPOLIA_RPC_URL
//   forge script FeeConcentrationIndexBuilderScript --sig "buildMild()" --broadcast --rpc-url $SEPOLIA_RPC_URL
//
//   # Multi-block recipe (crowdout) — 3 separate invocations:
//   forge script FeeConcentrationIndexBuilderScript --sig "buildCrowdoutPhase1()" --broadcast --rpc-url $SEPOLIA_RPC_URL
//   # ... wait N blocks ...
//   forge script FeeConcentrationIndexBuilderScript --sig "buildCrowdoutPhase2()" --broadcast --rpc-url $SEPOLIA_RPC_URL
//   # ... wait N blocks ...
//   TOKEN_A=<id> forge script FeeConcentrationIndexBuilderScript --sig "buildCrowdoutPhase3()" --broadcast --rpc-url $SEPOLIA_RPC_URL

contract FeeConcentrationIndexBuilderScript is Script, StdAssertions {
    Scenario internal scenario;
    Accounts internal accounts;
    uint256 internal _chainId;
    Protocol internal _protocol;

    IFeeConcentrationIndex internal fciIndex;

    function setUp() public {
        scenario.vm = vm;
        accounts = initAccounts(vm);
        _chainId = block.chainid;

        // Resolve known addresses by chain — V4 path for all chains.
        // V3 direct calls require callback contracts (can't use EOA broadcast).
        _protocol = Protocol.UniswapV4;
        Deployments memory d = resolveDeployments(_chainId, Protocol.UniswapV4);
        (address tokenA, address tokenB) = resolveTokens(_chainId);

        address fciHook;
        if (_chainId == SEPOLIA) {
            fciHook = ethSepoliaFCIHook();
        } else if (_chainId == UNICHAIN_SEPOLIA) {
            fciHook = unichainSepoliaFCIHook();
        }

        (address c0, address c1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 500,
            tickSpacing: int24(TICK_SPACING),
            hooks: IHooks(fciHook)
        });

        registerV4Pool(scenario, _chainId, key, d.positionManager, d.swapRouter);
        fciIndex = d.fciIndex;
    }

    // ── Single-block recipes ──

    function buildEquilibrium() public {
        deltaPlusFactory(
            scenario, _chainId, _protocol,
            accounts.lpPassive.privateKey,
            accounts.lpSophisticated.privateKey,
            accounts.swapper.privateKey,
            DELTA_EQUILIBRIUM
        );
        _logDeltaPlus("equilibrium");
    }

    function buildMild() public {
        deltaPlusFactory(
            scenario, _chainId, _protocol,
            accounts.lpPassive.privateKey,
            accounts.lpSophisticated.privateKey,
            accounts.swapper.privateKey,
            DELTA_MILD
        );
        _logDeltaPlus("mild");
    }

    // ── Multi-block recipe: crowdout (US3-F) ──

    function buildCrowdoutPhase1() public {
        Recipe memory r = recipeCrowdout();
        uint256 tokenA = crowdoutPhase1(
            scenario, _chainId, _protocol,
            accounts.lpPassive.privateKey, r.capitalA
        );
        console2.log("Phase 1 complete. TOKEN_A=%d", tokenA);
        console2.log("Wait for blocks, then run buildCrowdoutPhase2()");
    }

    function buildCrowdoutPhase2() public {
        Recipe memory r = recipeCrowdout();
        uint256 tokenB = crowdoutPhase2(
            scenario, _chainId, _protocol,
            accounts.lpSophisticated.privateKey,
            accounts.swapper.privateKey,
            r.capitalB
        );
        console2.log("Phase 2 complete. TOKEN_B=%d (already burned)", tokenB);
        console2.log("Wait for blocks, then run buildCrowdoutPhase3()");
    }

    function buildCrowdoutPhase3() public {
        Recipe memory r = recipeCrowdout();
        uint256 tokenA = vm.envUint("TOKEN_A");
        crowdoutPhase3(
            scenario, _chainId, _protocol,
            accounts.lpPassive.privateKey,
            accounts.swapper.privateKey,
            tokenA, r.capitalA
        );
        _logDeltaPlus("crowdout");
    }

    // ── Helpers ──

    function assertDeltaPlus(uint128 target, bool reactive) public view {
        PoolKey memory k = poolKey(scenario, _chainId);
        uint128 actual = fciIndex.getDeltaPlus(k, reactive);
        assertApproxEqRel(
            uint256(actual),
            uint256(target),
            0.05e18,
            "deltaPlus diverged from target"
        );
    }

    function _logDeltaPlus(string memory label) internal view {
        PoolKey memory k = poolKey(scenario, _chainId);
        bool reactive = _protocol == Protocol.UniswapV3;
        uint128 dp = fciIndex.getDeltaPlus(k, reactive);
        console2.log("[%s] deltaPlus (reactive=%s) = %d", label, reactive ? "true" : "false", uint256(dp));
    }
}
