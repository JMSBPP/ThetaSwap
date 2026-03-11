// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FciTokenVaultHarness} from "./helpers/FciTokenVaultHarness.sol";
import {LONG, SHORT} from "@fci-token-vault/modules/FciTokenVaultMod.sol";
import {SqrtPriceLibrary} from "foundational-hooks/src/libraries/SqrtPriceLibrary.sol";

contract FciTokenVaultModTest is Test {
    FciTokenVaultHarness vault;
    address alice = makeAddr("alice");

    function setUp() public {
        vault = new FciTokenVaultHarness();
        vault.harness_initVault(
            uint160(SqrtPriceLibrary.Q96), // strike = 1.0
            14 days,                        // halfLife
            block.timestamp + 30 days       // expiry
        );
    }

    /// @dev INV-012: deposit mints equal LONG + SHORT
    function test_deposit_mints_equal_pair() public {
        vault.harness_deposit(alice, 100e18);

        assertEq(vault.harness_balanceOf(alice, LONG), 100e18);
        assertEq(vault.harness_balanceOf(alice, SHORT), 100e18);
    }

    /// @dev INV-015: settle reverts if vault not expired
    function test_settle_reverts_before_expiry() public {
        vault.harness_deposit(alice, 100e18);

        vm.expectRevert();
        vault.harness_settle();
    }

    /// @dev INV-016: settle after expiry succeeds, sets settled + longPayoutPerToken
    function test_settle_after_expiry() public {
        vault.harness_deposit(alice, 100e18);

        // Set HWM above strike, timestamp near expiry so minimal decay
        uint256 expiry = block.timestamp + 30 days;
        vault.harness_setHWM(uint160(SqrtPriceLibrary.Q96) * 2, expiry - 1);

        // Warp past expiry
        vm.warp(expiry);
        vault.harness_settle();

        (,,,,, , bool settled, uint256 longPayout) = vault.harness_getVaultStorage();
        assertTrue(settled);
        assertGt(longPayout, 0);
    }

    /// @dev INV-017: redeem reverts if vault not settled
    function test_redeem_reverts_before_settle() public {
        vault.harness_deposit(alice, 100e18);

        vm.expectRevert();
        vault.harness_redeem(alice, 100e18);
    }

    /// @dev INV-012 + INV-013: redeem burns equal LONG + SHORT, decreases totalDeposits
    function test_redeem_burns_pair() public {
        vault.harness_deposit(alice, 100e18);

        // Set HWM near expiry, warp, settle
        uint256 expiry = block.timestamp + 30 days;
        vault.harness_setHWM(uint160(SqrtPriceLibrary.Q96) * 2, expiry - 1);
        vm.warp(expiry);
        vault.harness_settle();

        vault.harness_redeem(alice, 100e18);

        assertEq(vault.harness_balanceOf(alice, LONG), 0);
        assertEq(vault.harness_balanceOf(alice, SHORT), 0);

        (,,,, uint256 totalDeposits,,, ) = vault.harness_getVaultStorage();
        assertEq(totalDeposits, 0);
    }

    /// @dev deposit reverts if vault already settled
    function test_deposit_reverts_after_settle() public {
        vault.harness_deposit(alice, 100e18);

        uint256 expiry = block.timestamp + 30 days;
        vault.harness_setHWM(uint160(SqrtPriceLibrary.Q96), expiry - 1);
        vm.warp(expiry);
        vault.harness_settle();

        vm.expectRevert();
        vault.harness_deposit(alice, 50e18);
    }
}
