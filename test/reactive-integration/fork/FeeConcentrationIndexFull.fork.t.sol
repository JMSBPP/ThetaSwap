// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeConcentrationIndexBuilderScript} from
    "../../../script/reactive-integration/FeeConcentrationIndexBuilder.s.sol";
import {SEPOLIA, UNICHAIN_SEPOLIA} from "../../../script/utils/Deployments.sol";

// Maps chain ID → foundry.toml [rpc_endpoints] alias.
function rpcAlias(uint256 chainId) pure returns (string memory) {
    if (chainId == SEPOLIA) return "sepolia";
    if (chainId == UNICHAIN_SEPOLIA) return "unichain_sepolia";
    revert("unknown chainId");
}

abstract contract FeeConcentrationIndexFullForkBase is Test {
    FeeConcentrationIndexBuilderScript fciScript;

    function _chainId() internal pure virtual returns (uint256);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl(rpcAlias(_chainId())));
        fciScript = new FeeConcentrationIndexBuilderScript();
        fciScript.setUp();
    }

    function test_buildEquilibrium() public {
        fciScript.buildEquilibrium();
        fciScript.assertDeltaPlus(0, true);
    }

    function test_buildMild() public {
        fciScript.buildMild();
    }
}

contract SepoliaForkTest is FeeConcentrationIndexFullForkBase {
    function _chainId() internal pure override returns (uint256) { return SEPOLIA; }
}

contract UnichainSepoliaForkTest is FeeConcentrationIndexFullForkBase {
    function _chainId() internal pure override returns (uint256) { return UNICHAIN_SEPOLIA; }
}
