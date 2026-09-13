// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {USDT} from "../src/USDT.sol";

contract USDTTest is Test {
    USDT internal usdt;
    address internal owner = makeAddr("owner");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");

    function setUp() public {
        USDT impl = new USDT();
        usdt = USDT(address(new ERC1967Proxy(address(impl), abi.encodeCall(USDT.initialize, (owner)))));
    }

    // ---------- positive ----------

    function test_metadata() public view {
        assertEq(usdt.name(), "USDT");
        assertEq(usdt.symbol(), "USDT");
        assertEq(usdt.decimals(), 6, "stablecoin convention is 6 decimals");
        assertEq(usdt.owner(), owner);
    }

    function test_ownerCanMint() public {
        vm.prank(owner);
        usdt.mint(alice, 500e6);
        assertEq(usdt.balanceOf(alice), 500e6);
        assertEq(usdt.totalSupply(), 500e6);
    }

    function test_approvedMinterCanMint() public {
        vm.prank(owner);
        usdt.setMinter(minter, true);
        vm.prank(minter);
        usdt.mint(alice, 7e6);
        assertEq(usdt.balanceOf(alice), 7e6);
    }

    function test_faucetDispensesTheFixedAmount() public {
        vm.prank(alice);
        usdt.faucet();
        assertEq(usdt.balanceOf(alice), usdt.FAUCET_AMOUNT());
    }

    function test_faucetWorksAgainAfterTheCooldown() public {
        vm.prank(alice);
        usdt.faucet();
        vm.warp(block.timestamp + usdt.FAUCET_COOLDOWN());
        vm.prank(alice);
        usdt.faucet();
        assertEq(usdt.balanceOf(alice), usdt.FAUCET_AMOUNT() * 2);
    }

    // ---------- edge ----------

    function test_faucetExactlyAtTheCooldownBoundaryIsAllowed() public {
        vm.prank(alice);
        usdt.faucet();
        uint256 t = usdt.lastFaucet(alice);
        vm.warp(t + usdt.FAUCET_COOLDOWN());
        vm.prank(alice);
        usdt.faucet(); // must not revert
    }

    function test_revokedMinterLosesAccess() public {
        vm.startPrank(owner);
        usdt.setMinter(minter, true);
        usdt.setMinter(minter, false);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectRevert(USDT.NotMinter.selector);
        usdt.mint(alice, 1);
    }

    // ---------- negative ----------

    function test_revert_strangerCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(USDT.NotMinter.selector);
        usdt.mint(alice, 1e6);
    }

    function test_revert_strangerCannotSetMinter() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        usdt.setMinter(minter, true);
    }

    function test_revert_faucetTwiceInsideTheCooldown() public {
        vm.startPrank(alice);
        usdt.faucet();
        vm.warp(block.timestamp + usdt.FAUCET_COOLDOWN() - 1);
        vm.expectRevert(USDT.FaucetCooldown.selector);
        usdt.faucet();
        vm.stopPrank();
    }

    function test_revert_initializeTwice() public {
        vm.expectRevert();
        usdt.initialize(alice);
    }

    function test_revert_implementationCannotBeInitialized() public {
        USDT impl = new USDT();
        vm.expectRevert();
        impl.initialize(alice);
    }
}
