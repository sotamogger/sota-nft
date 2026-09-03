// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// SOTA (beta) — State of the Art.
//
// The NFT collection Sota Minds is built to seed: one token per researcher who
// pushed the field's state of the art. A token is a *researcher plus a set of
// modifiers* — the modifiers are what make each piece unique (rarity, era,
// awards, and whatever mechanisms governance dreams up). The artwork is not
// stored here: an external render service is called with the token's modifiers
// and returns the image. This contract is the source of truth for who a token
// is and what modifiers it carries; the picture is downstream.
//
// Minting is gated (a seat mints only when the holders ratify it, via the same
// IMintGate seam as before). Proceeds and 5% royalties route to the treasury.
//
// Beta: names, symbols, and mechanisms will change. Do not treat as final.

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface IMintGate {
    function claimSeat(uint256 seatId, address buyer) external view returns (address recipient);
}

contract SOTA is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SEATS = 128;
    uint96 public constant ROYALTY_BPS = 500; // 5%

    struct Seat {
        uint256 price;
        string researcher;   // e.g. "Demis Hassabis"
        string thesis;       // one-line why-they-matter
        bool minted;
    }

    // A modifier is a string plus an optional expiry (0 = permanent). Decay is
    // enforced downstream: activeModifiers() and the render service drop any
    // whose expiresAt has passed, so a "hot streak" fades on its own.
    struct Modifier {
        string value;
        uint48 expiresAt;
    }

    mapping(uint256 => Seat) private _seats;
    mapping(uint256 => Modifier[]) private _modifiers; // seatId => modifiers
    address public treasury;
    IMintGate public mintGate;
    // The contract allowed to append modifiers to minted seats — the modifier
    // gate (holders vote a value in; on pass the gate calls appendModifier).
    address public modifierGate;

    // Off-chain services, both swappable. `metadataBase` is the metadata
    // resolver (tokenURI = metadataBase + id); it reads this contract and,
    // for the image, calls `imageService` with the token's modifiers. Kept
    // on-chain so both are canonical and any client can find them.
    string public metadataBase;
    string public imageService;

    event SeatSet(uint256 indexed seatId, uint256 price, string researcher, string thesis);
    event ModifiersSet(uint256 indexed seatId, string[] modifiers);
    event ModifierAppended(uint256 indexed seatId, string value, uint48 expiresAt);
    event MintGateSet(address indexed gate);
    event ModifierGateSet(address indexed gate);
    event TreasurySet(address indexed treasury);
    event ServicesSet(string metadataBase, string imageService);
    event Minted(uint256 indexed seatId, address indexed recipient, uint256 paid);

    constructor(address treasury_, address gate_, string memory metadataBase_, string memory imageService_)
        ERC721("SOTA (beta)", "SOTA")
        Ownable(msg.sender)
    {
        require(treasury_ != address(0), "treasury=0");
        treasury = treasury_;
        mintGate = IMintGate(gate_);
        metadataBase = metadataBase_;
        imageService = imageService_;
        _setDefaultRoyalty(treasury_, ROYALTY_BPS);
    }

    // ---- reads ----
    function seatInfo(uint256 seatId) external view returns (uint256 price, string memory researcher, string memory thesis, bool minted) {
        Seat storage s = _seats[seatId];
        return (s.price, s.researcher, s.thesis, s.minted);
    }

    // Every modifier ever set, expired or not (for auditing / history).
    function modifiersOf(uint256 seatId) external view returns (Modifier[] memory) {
        return _modifiers[seatId];
    }

    // Only the currently-live modifier strings — what the render service draws.
    function activeModifiers(uint256 seatId) external view returns (string[] memory active) {
        Modifier[] storage all = _modifiers[seatId];
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].expiresAt == 0 || all[i].expiresAt > block.timestamp) ++n;
        }
        active = new string[](n);
        uint256 j;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].expiresAt == 0 || all[i].expiresAt > block.timestamp) active[j++] = all[i].value;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return metadataBase;
    }

    // ---- admin: seat setup (frozen once minted) ----
    function setSeat(uint256 seatId, uint256 price, string calldata researcher, string calldata thesis) external onlyOwner {
        require(seatId < MAX_SEATS, "bad seat");
        require(!_seats[seatId].minted, "seat frozen");
        Seat storage s = _seats[seatId];
        s.price = price;
        s.researcher = researcher;
        s.thesis = thesis;
        emit SeatSet(seatId, price, researcher, thesis);
    }

    // Owner seeds the starting modifiers (all permanent) while the seat is
    // unminted. After mint, only the modifier gate may add more.
    function setModifiers(uint256 seatId, string[] calldata mods) external onlyOwner {
        require(seatId < MAX_SEATS, "bad seat");
        require(!_seats[seatId].minted, "seat frozen");
        delete _modifiers[seatId];
        for (uint256 i; i < mods.length; ++i) {
            _modifiers[seatId].push(Modifier(mods[i], 0));
        }
        emit ModifiersSet(seatId, mods);
    }

    // The living loop: the modifier gate appends a value the holders voted in.
    // `expiresAt` of 0 is permanent; a future timestamp decays on its own.
    function appendModifier(uint256 seatId, string calldata value, uint48 expiresAt) external {
        require(msg.sender == modifierGate, "not modifier gate");
        require(seatId < MAX_SEATS, "bad seat");
        _modifiers[seatId].push(Modifier(value, expiresAt));
        emit ModifierAppended(seatId, value, expiresAt);
    }

    function setModifierGate(address gate_) external onlyOwner {
        modifierGate = gate_;
        emit ModifierGateSet(gate_);
    }

    function setMintGate(address gate_) external onlyOwner {
        mintGate = IMintGate(gate_);
        emit MintGateSet(gate_);
    }

    function setTreasury(address treasury_) external onlyOwner {
        require(treasury_ != address(0), "treasury=0");
        treasury = treasury_;
        _setDefaultRoyalty(treasury_, ROYALTY_BPS);
        emit TreasurySet(treasury_);
    }

    function setServices(string calldata metadataBase_, string calldata imageService_) external onlyOwner {
        metadataBase = metadataBase_;
        imageService = imageService_;
        emit ServicesSet(metadataBase_, imageService_);
    }

    // ---- mint: pay exact price, gate picks the recipient, ETH -> treasury ----
    function mint(uint256 seatId) external payable nonReentrant returns (address recipient) {
        Seat storage s = _seats[seatId];
        require(s.price > 0, "seat not for sale");
        require(!s.minted, "already minted");
        require(msg.value == s.price, "wrong price");
        require(address(mintGate) != address(0), "no gate");

        recipient = mintGate.claimSeat(seatId, msg.sender);
        require(recipient != address(0), "not ratified");
        require(recipient != address(this), "recipient=self");

        s.minted = true;
        _safeMint(recipient, seatId);

        (bool ok,) = treasury.call{value: msg.value}("");
        require(ok, "treasury transfer failed");
        emit Minted(seatId, recipient, msg.value);
    }

    function supportsInterface(bytes4 id) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(id);
    }
}
