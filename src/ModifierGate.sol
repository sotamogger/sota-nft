// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// ModifierGate — the living loop for SOTA.
//
// Holders propose a modifier for a seat (a value, an optional expiry, and the
// threshold it must clear) and sign with their Sota Minds vote weight. The
// moment a proposal clears its threshold of supply, the gate appends the
// modifier to the SOTA token and the art changes downstream.
//
// The threshold is per-proposal in basis points: 5000 = simple majority for an
// ordinary award, 6667 = supermajority for a negative modifier ("cancelled")
// so memes that cut against a seat need real consensus. Standalone, immutable,
// no admin. Reads Sota Minds' ERC20Votes; writes only to the SOTA token.
//
// Design by bird-is-spy; reference implementation.

interface ISotaVotes {
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
    function clock() external view returns (uint48);
}

interface INFTModifiers {
    function appendModifier(uint256 seatId, string calldata value, uint48 expiresAt) external;
}

contract ModifierGate {
    uint256 public constant BPS = 10_000;
    uint256 public constant MIN_THRESHOLD_BPS = 5_000;  // never easier than a majority
    uint256 public constant VOTE_DURATION = 3 days;
    uint256 public constant MAX_SEATS = 128;

    ISotaVotes public immutable sota;
    INFTModifiers public immutable nft;

    struct ModProposal {
        uint256 seatId;
        string value;
        uint48 expiresAt;     // absolute timestamp for the modifier; 0 = permanent
        uint48 snapshot;
        uint256 thresholdBps;
        uint256 votes;
        bool passed;
    }

    ModProposal[] public proposals;
    mapping(uint256 => mapping(address => bool)) public signed;

    event ModProposed(uint256 indexed id, uint256 indexed seatId, string value, uint48 expiresAt, uint256 thresholdBps, uint48 snapshot);
    event ModSigned(uint256 indexed id, address indexed signer, uint256 weight);
    event ModPassed(uint256 indexed id, uint256 indexed seatId, string value);

    constructor(address sota_, address nft_) {
        require(sota_ != address(0) && nft_ != address(0), "zero addr");
        sota = ISotaVotes(sota_);
        nft = INFTModifiers(nft_);
    }

    function proposalCount() external view returns (uint256) {
        return proposals.length;
    }

    function propose(uint256 seatId, string calldata value, uint48 expiresAt, uint256 thresholdBps) external returns (uint256 id) {
        require(seatId < MAX_SEATS, "bad seat");
        require(bytes(value).length > 0, "empty value");
        require(thresholdBps >= MIN_THRESHOLD_BPS && thresholdBps <= BPS, "bad threshold");
        id = proposals.length;
        proposals.push(ModProposal(seatId, value, expiresAt, sota.clock(), thresholdBps, 0, false));
        emit ModProposed(id, seatId, value, expiresAt, thresholdBps, sota.clock());
    }

    function sign(uint256 id) external {
        ModProposal storage p = proposals[id];
        require(block.timestamp <= p.snapshot + VOTE_DURATION, "vote expired");
        require(!p.passed, "already passed");
        require(!signed[id][msg.sender], "already signed");
        uint256 weight = sota.getPastVotes(msg.sender, p.snapshot);
        require(weight > 0, "no votes at snapshot");
        signed[id][msg.sender] = true;
        p.votes += weight;
        emit ModSigned(id, msg.sender, weight);
        if (p.votes * BPS >= p.thresholdBps * sota.getPastTotalSupply(p.snapshot)) {
            p.passed = true;
            nft.appendModifier(p.seatId, p.value, p.expiresAt);
            emit ModPassed(id, p.seatId, p.value);
        }
    }
}
