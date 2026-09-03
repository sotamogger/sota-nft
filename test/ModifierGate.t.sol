// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SOTA} from "../src/SOTA.sol";
import {ModifierGate} from "../src/ModifierGate.sol";
import {MockMintGate} from "./MockMintGate.sol";
import {MockVotes} from "./MockVotes.sol";

contract ModifierGateTest is Test {
    SOTA nft;
    ModifierGate gate;
    MockVotes votes;
    MockMintGate mintGate;
    address treasury = makeAddr("treasury");
    address whale = makeAddr("whale");    // 60/100
    address mid = makeAddr("mid");        // 55/100
    address minnow = makeAddr("minnow");  // 40/100
    address winner = makeAddr("winner");
    address buyer = makeAddr("buyer");

    function setUp() public {
        votes = new MockVotes();
        votes.setTotal(100e18);
        votes.setVotes(whale, 60e18);
        votes.setVotes(mid, 55e18);
        votes.setVotes(minnow, 40e18);
        mintGate = new MockMintGate();
        nft = new SOTA(treasury, address(mintGate), "https://sota.freysa.dev/sota/meta/", "https://render/img");
        nft.setSeat(1, 0.01 ether, "Demis Hassabis", "Solved protein folding.");
        gate = new ModifierGate(address(votes), address(nft));
        nft.setModifierGate(address(gate));
        vm.deal(buyer, 10 ether);
        vm.warp(block.timestamp + 1);
    }

    function _mintSeat1() internal {
        mintGate.ratify(1, winner);
        vm.prank(buyer);
        nft.mint{value: 0.01 ether}(1);
    }

    function test_append_via_vote() public {
        _mintSeat1();
        vm.prank(whale);
        uint256 id = gate.propose(1, "hot-streak", 0, 5000);
        vm.warp(block.timestamp + 1);
        vm.prank(whale);
        gate.sign(id);
        string[] memory active = nft.activeModifiers(1);
        assertEq(active.length, 1);
        assertEq(active[0], "hot-streak");
    }

    function test_expiry_decays() public {
        _mintSeat1();
        vm.prank(whale);
        uint256 id = gate.propose(1, "hot-streak", uint48(block.timestamp + 30 days), 5000);
        vm.warp(block.timestamp + 1);
        vm.prank(whale);
        gate.sign(id);
        assertEq(nft.activeModifiers(1).length, 1);
        vm.warp(block.timestamp + 31 days);
        assertEq(nft.activeModifiers(1).length, 0);
        assertEq(nft.modifiersOf(1).length, 1); // still in history
    }

    function test_supermajority_blocks_bare_majority() public {
        _mintSeat1();
        // negative modifier needs 6667 bps; mid holds 55% — a majority but not super
        vm.prank(mid);
        uint256 id = gate.propose(1, "cancelled", 0, 6667);
        vm.warp(block.timestamp + 1);
        vm.prank(mid);
        gate.sign(id);
        (,,,,,, bool passed) = gate.proposals(id);
        assertFalse(passed); // 55% < 66.67%
        assertEq(nft.activeModifiers(1).length, 0);

        // a real supermajority (mid 55% + minnow 40% = 95%) clears it
        vm.prank(minnow);
        gate.sign(id);
        (,,,,,, bool passed2) = gate.proposals(id);
        assertTrue(passed2);
        assertEq(nft.activeModifiers(1)[0], "cancelled");
    }

    function test_majority_below_threshold_fails() public {
        _mintSeat1();
        vm.prank(minnow); // 40% < 50%
        uint256 id = gate.propose(1, "award", 0, 5000);
        vm.warp(block.timestamp + 1);
        vm.prank(minnow);
        gate.sign(id);
        (,,,,,, bool passed) = gate.proposals(id);
        assertFalse(passed);
    }

    function test_threshold_bounds() public {
        vm.prank(whale);
        vm.expectRevert("bad threshold");
        gate.propose(1, "x", 0, 4999); // below majority floor
        vm.prank(whale);
        vm.expectRevert("bad threshold");
        gate.propose(1, "x", 0, 10001); // above 100%
    }

    function test_empty_value_and_bad_seat() public {
        vm.prank(whale);
        vm.expectRevert("empty value");
        gate.propose(1, "", 0, 5000);
        vm.prank(whale);
        vm.expectRevert("bad seat");
        gate.propose(128, "x", 0, 5000);
    }

    function test_only_gate_can_append() public {
        _mintSeat1();
        vm.expectRevert("not modifier gate");
        nft.appendModifier(1, "sneaky", 0);
    }

    function test_vote_expiry() public {
        vm.prank(whale);
        uint256 id = gate.propose(1, "late", 0, 5000);
        vm.warp(block.timestamp + 3 days + 2);
        vm.prank(whale);
        vm.expectRevert("vote expired");
        gate.sign(id);
    }
}
