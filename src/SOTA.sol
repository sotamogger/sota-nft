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

    mapping(uint256 => Seat) private _seats;
    mapping(uint256 => string[]) private _modifiers; // seatId => modifier list
    address public treasury;
    IMintGate public mintGate;

    // Off-chain services, both swappable. `metadataBase` is the metadata
    // resolver (tokenURI = metadataBase + id); it reads this contract and,
    // for the image, calls `imageService` with the token's modifiers. Kept
    // on-chain so both are canonical and any client can find them.
    string public metadataBase;
    string public imageService;

    event SeatSet(uint256 indexed seatId, uint256 price, string researcher, string thesis);
    event ModifiersSet(uint256 indexed seatId, string[] modifiers);
    event MintGateSet(address indexed gate);
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

    function modifiersOf(uint256 seatId) external view returns (string[] memory) {
        return _modifiers[seatId];
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

    // Modifiers can be re-set while the seat is unminted. Post-mint mutation
    // (e.g. governance appending a new award) is a mechanism to add later.
    function setModifiers(uint256 seatId, string[] calldata mods) external onlyOwner {
        require(seatId < MAX_SEATS, "bad seat");
        require(!_seats[seatId].minted, "seat frozen");
        _modifiers[seatId] = mods;
        emit ModifiersSet(seatId, mods);
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
