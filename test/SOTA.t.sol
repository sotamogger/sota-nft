// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SOTA} from "../src/SOTA.sol";
import {MockMintGate} from "./MockMintGate.sol";

contract SOTATest is Test {
    SOTA nft;
    MockMintGate gate;
    address treasury = makeAddr("treasury");
    address buyer = makeAddr("buyer");
    address winner = makeAddr("winner");

    function setUp() public {
        gate = new MockMintGate();
        nft = new SOTA(treasury, address(gate), "https://sota.freysa.dev/sota/meta/", "https://render.sota.freysa.dev/img");
        nft.setSeat(1, 0.01 ether, "Demis Hassabis", "Made protein folding a solved problem.");
        string[] memory mods = new string[](3);
        mods[0] = "founder"; mods[1] = "nobel-2024"; mods[2] = "deepmind";
        nft.setModifiers(1, mods);
        vm.deal(buyer, 10 ether);
    }

    function test_name_symbol() public view {
        assertEq(nft.name(), "SOTA (beta)");
        assertEq(nft.symbol(), "SOTA");
    }

    function test_modifiers_stored() public view {
        string[] memory m = nft.modifiersOf(1);
        assertEq(m.length, 3);
        assertEq(m[0], "founder");
        assertEq(m[2], "deepmind");
    }

    function test_gate_reverts_when_not_ratified() public {
        vm.prank(buyer);
        vm.expectRevert("not ratified");
        nft.mint{value: 0.01 ether}(1);
    }

    function test_recipient_gets_seat_and_treasury_paid() public {
        gate.ratify(1, winner);
        uint256 before = treasury.balance;
        vm.prank(buyer);
        nft.mint{value: 0.01 ether}(1);
        assertEq(nft.ownerOf(1), winner);
        assertEq(treasury.balance, before + 0.01 ether);
    }

    function test_tokenuri_uses_metadata_base() public {
        gate.ratify(1, winner);
        vm.prank(buyer);
        nft.mint{value: 0.01 ether}(1);
        assertEq(nft.tokenURI(1), "https://sota.freysa.dev/sota/meta/1");
    }

    function test_services_swappable() public {
        nft.setServices("https://m2/", "https://r2/");
        assertEq(nft.metadataBase(), "https://m2/");
        assertEq(nft.imageService(), "https://r2/");
    }

    function test_price_strict_and_no_double_mint() public {
        gate.ratify(1, winner);
        vm.prank(buyer);
        vm.expectRevert("wrong price");
        nft.mint{value: 0.02 ether}(1);
        vm.prank(buyer);
        nft.mint{value: 0.01 ether}(1);
        gate.ratify(1, winner);
        vm.prank(buyer);
        vm.expectRevert("already minted");
        nft.mint{value: 0.01 ether}(1);
    }

    function test_frozen_after_mint() public {
        gate.ratify(1, winner);
        vm.prank(buyer);
        nft.mint{value: 0.01 ether}(1);
        vm.expectRevert("seat frozen");
        nft.setSeat(1, 1 ether, "x", "y");
        string[] memory m = new string[](1); m[0] = "late";
        vm.expectRevert("seat frozen");
        nft.setModifiers(1, m);
    }

    function test_royalty_targets_treasury() public view {
        (address recv, uint256 amt) = nft.royaltyInfo(1, 1 ether);
        assertEq(recv, treasury);
        assertEq(amt, 0.05 ether);
    }

    function test_treasury_zero_rejected() public {
        vm.expectRevert("treasury=0");
        new SOTA(address(0), address(gate), "m", "r");
    }
}
