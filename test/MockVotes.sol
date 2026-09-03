// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ISotaVotes} from "../src/ModifierGate.sol";

contract MockVotes is ISotaVotes {
    mapping(address => uint256) public votes;
    uint256 public total;
    function setVotes(address a, uint256 w) external { votes[a] = w; }
    function setTotal(uint256 t) external { total = t; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return votes[a]; }
    function getPastTotalSupply(uint256) external view returns (uint256) { return total; }
    function clock() external view returns (uint48) { return uint48(block.timestamp); }
}
