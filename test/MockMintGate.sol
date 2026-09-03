// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMintGate} from "../src/SOTA.sol";

contract MockMintGate is IMintGate {
    mapping(uint256 => address) public ratified;
    function ratify(uint256 seatId, address recipient) external { ratified[seatId] = recipient; }
    function claimSeat(uint256 seatId, address) external view returns (address) { return ratified[seatId]; }
}
