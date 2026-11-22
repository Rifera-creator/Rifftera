// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Binance Agent ID registry interface — same pattern as
/// RiferaFirstTake (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) and
/// TalvioScanNFT: only `balanceOf` is used, and a wallet must hold >= 1
/// Agent ID to mint. No other registry function is called.
interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

/// @title Rifera Cursor Pieces
/// @notice ERC721 collection of the 5 pieces that build one First Cursor:
/// 0 Pointer, 1 Ember, 2 Verdant, 3 Frost, 4 Void. One single contract.
/// Minting is strictly sequential per wallet: a wallet's 1st mint is always
/// Pointer, 2nd Ember, 3rd Verdant, 4th Frost, 5th Void — one of each,
/// max 5 per wallet (one complete set, no duplicates, no 6th mint).
/// First mint per wallet is FREE (gas only); mints 2-5 cost 0.002 BNB each.
/// Minting requires holding a Binance Agent ID (balanceOf > 0).
/// Supply is capped: 1,111 per piece (1,111 Pointer, 1,111 Ember, 1,111
/// Verdant, 1,111 Frost, 1,111 Void), 5,555 total — one piece type selling
/// out does not change any other piece's cap, but a wallet always starts
/// at Pointer, so once Pointer is sold out no new wallet can start.
/// 100% of paid mint BNB goes straight to the owner (project wallet) in the
/// same transaction — nothing is kept in this contract. Payment must be
/// EXACT: underpayment and overpayment both revert (no refund path).
/// Artwork is fully on-chain: each piece is drawn as a distinct pixel shard
/// of the Rifera arrow cursor (different SHAPE per piece, not just colour),
/// shown over a faint full-arrow silhouette so it reads as a fragment.
contract RiferaCursorPieces is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant PIECE_PRICE = 0.002 ether;
    uint8 public constant MAX_PIECES_PER_WALLET = 5;

    /// @notice Supply cap per piece: 1,111 of each piece (Pointer, Ember,
    /// Verdant, Frost, Void). 1,111 sets max, 5,555 NFTs total.
    uint256 public constant MAX_SUPPLY_PER_PIECE = 1111;
    /// @notice Total supply cap across all 5 pieces: 5 x 1,111 = 5,555.
    uint256 public constant MAX_TOTAL_SUPPLY = 5555;

    /// @notice Binance Agent ID NFT contract (BNB Chain mainnet).
    IAgentId public immutable agentId;

    /// @notice Mint starts CLOSED. Nobody can mint until the owner opens it
    /// with setMintOpen(true). The owner can close it again at any time.
    bool public mintOpen;

    uint256 public nextTokenId = 1;
    uint256 public totalMinted;

    /// @notice Pieces minted per piece index (0-4). Public getter:
    /// mintedPerPiece(piece) — the web reads this to show remaining supply.
    mapping(uint8 => uint256) public mintedPerPiece;

    /// @notice Pieces minted by a wallet (0-5). Next piece = this count.
    mapping(address => uint256) public mintsByWallet;
    /// @notice Piece index (0-4) of a token.
    mapping(uint256 => uint8) private _pieceOf;
    /// @notice Token ids held by a wallet, in mint order (max 5).
    mapping(address => uint256[5]) private _walletTokens;

    event PieceMinted(address indexed minter, uint256 indexed tokenId, uint8 indexed piece, uint256 pricePaid);
    event MintOpenChanged(bool open);

    error MintClosed();
    error NoAgentId(address wallet);
    error MaxPiecesMinted(address wallet);
    error PieceSoldOut(uint8 piece);
    error InsufficientPayment(uint256 required, uint256 sent);
    error ExcessPayment(uint256 required, uint256 sent);
    error WithdrawFailed();

    constructor(address agentId_) ERC721("Rifera Cursor Pieces", "RPIECE") Ownable(msg.sender) {
        require(agentId_ != address(0), "agent id is zero address");
        agentId = IAgentId(agentId_);
    }

    /// @notice Open or close minting. Owner only. Mint is closed at deploy.
    function setMintOpen(bool open_) external onlyOwner {
        mintOpen = open_;
        emit MintOpenChanged(open_);
    }

    /// @notice Exact price of a wallet's next mint: 0 for the first
    /// (Pointer, free), 0.002 BNB for mints 2-5. Reverts if the wallet
    /// already holds a complete set (no next mint exists), or if the next
    /// piece type is sold out (cap 1,111 reached) — never quote a mint
    /// that is guaranteed to fail.
    function nextMintQuote(address wallet) external view returns (uint256) {
        uint256 count = mintsByWallet[wallet];
        if (count >= MAX_PIECES_PER_WALLET) revert MaxPiecesMinted(wallet);
        uint8 piece = uint8(count);
        if (mintedPerPiece[piece] >= MAX_SUPPLY_PER_PIECE) revert PieceSoldOut(piece);
        return count == 0 ? 0 : PIECE_PRICE;
    }

    /// @notice Remaining supply of a piece: cap minus minted (0 when sold out).
    function remainingPerPiece(uint8 piece) external view returns (uint256) {
        return MAX_SUPPLY_PER_PIECE - mintedPerPiece[piece];
    }

    /// @notice Mint the next piece in sequence for the caller. Payable,
    /// exact payment only. 100% of a paid mint goes to the owner in this
    /// same transaction.
    function mint() external payable nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (agentId.balanceOf(msg.sender) < 1) revert NoAgentId(msg.sender);
        uint256 count = mintsByWallet[msg.sender];
        if (count >= MAX_PIECES_PER_WALLET) revert MaxPiecesMinted(msg.sender);

        uint8 piece = uint8(count); // 0 Pointer, 1 Ember, 2 Verdant, 3 Frost, 4 Void
        if (mintedPerPiece[piece] >= MAX_SUPPLY_PER_PIECE) revert PieceSoldOut(piece);

        uint256 price = count == 0 ? 0 : PIECE_PRICE;
        if (msg.value < price) revert InsufficientPayment(price, msg.value);
        if (msg.value > price) revert ExcessPayment(price, msg.value);

        uint256 tokenId = nextTokenId++;
        _pieceOf[tokenId] = piece;
        _walletTokens[msg.sender][count] = tokenId;
        mintsByWallet[msg.sender] = count + 1;
        mintedPerPiece[piece] += 1;
        totalMinted += 1;
        _safeMint(msg.sender, tokenId);
        emit PieceMinted(msg.sender, tokenId, piece, price);

        if (price > 0) {
            (bool ok, ) = payable(owner()).call{value: price}("");
            if (!ok) revert WithdrawFailed();
        }
    }

    /// @notice Piece index (0-4) of a token. Reverts for unminted tokens.
    function pieceOf(uint256 tokenId) external view returns (uint8) {
        _requireOwned(tokenId);
        return _pieceOf[tokenId];
    }

    /// @notice Piece indexes held by a wallet, in mint order (e.g. [0,1]).
    function piecesOf(address wallet) external view returns (uint8[] memory) {
        uint256 count = mintsByWallet[wallet];
        uint8[] memory pieces = new uint8[](count);
        for (uint256 i; i < count; i++) {
            pieces[i] = _pieceOf[_walletTokens[wallet][i]];
        }
        return pieces;
    }

    /// @notice Token ids held by a wallet, in mint order.
    function tokenIdsOf(address wallet) external view returns (uint256[] memory) {
        uint256 count = mintsByWallet[wallet];
        uint256[] memory ids = new uint256[](count);
        for (uint256 i; i < count; i++) {
            ids[i] = _walletTokens[wallet][i];
        }
        return ids;
    }

    /// @notice True once a wallet holds all 5 pieces (one complete set).
    function hasCompleteSet(address wallet) external view returns (bool) {
        return mintsByWallet[wallet] >= MAX_PIECES_PER_WALLET;
    }

    /// @notice Withdraw any BNB stuck in the contract (normally zero: paid
    /// mint BNB is forwarded to the owner in the same transaction). Owner only.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool ok, ) = payable(owner()).call{value: balance}("");
        if (!ok) revert WithdrawFailed();
    }

    // ── On-chain artwork ─────────────────────────────────────────────────
    // Each piece is a DIFFERENT SHAPE cut from the Rifera arrow cursor,
    // drawn over a faint full-arrow silhouette so it reads as a fragment:
    //  Pointer (white)  — sharp triangle tip
    //  Ember   (red)    — jagged notched block (teeth on both sides)
    //  Verdant (green)  — diagonal staircase of three squares
    //  Frost   (blue)   — widening wedge
    //  Void    (purple) — forked tail, two legs
    // Each piece is a DIFFERENT SHAPE cut from the Rifera arrow cursor,
    // drawn over a faint full-arrow silhouette so it reads as a fragment:
    function _pieceName(uint8 piece) internal pure returns (string memory) {
        if (piece == 0) return "Pointer";
        if (piece == 1) return "Ember";
        if (piece == 2) return "Verdant";
        if (piece == 3) return "Frost";
        return "Void";
    }

    function _pieceColor(uint8 piece) internal pure returns (string memory) {
        if (piece == 0) return "#F5F5F5"; // Pointer — white
        if (piece == 1) return "#E5484D"; // Ember — red
        if (piece == 2) return "#3DDC84"; // Verdant — green
        if (piece == 3) return "#35C4DC"; // Frost — blue
        return "#8B7CFF"; // Void — purple
    }

    /// @notice The shard shape itself — different geometry per piece.
    function _pieceArt(uint8 piece) internal pure returns (string memory) {
        string memory color = _pieceColor(piece);
        if (piece == 0) {
            // Pointer: sharp triangle tip.
            return string.concat(
                "<polygon points=\"16,2 27,16 5,16\" fill=\"", color,
                "\" stroke=\"#000000\" stroke-width=\"1\"/>"
            );
        }
        if (piece == 1) {
            // Ember: jagged notched block — teeth cut into both sides.
            return string.concat(
                "<polygon points=\"5,6 27,6 27,11 22,11 22,16 27,16 27,21 22,21 22,26 5,26 5,21 10,21 10,16 5,16 5,11 10,11 10,6\" fill=\"",
                color, "\" stroke=\"#000000\" stroke-width=\"1\"/>"
            );
        }
        if (piece == 2) {
            // Verdant: diagonal staircase — three squares stepping down-right.
            return string.concat(
                "<rect x=\"4\" y=\"4\" width=\"8\" height=\"8\" fill=\"", color, "\" stroke=\"#000000\"/>",
                "<rect x=\"12\" y=\"12\" width=\"8\" height=\"8\" fill=\"", color, "\" stroke=\"#000000\"/>",
                "<rect x=\"20\" y=\"20\" width=\"8\" height=\"8\" fill=\"", color, "\" stroke=\"#000000\"/>"
            );
        }
        if (piece == 3) {
            // Frost: widening wedge, narrow at the top, wide at the base.
            return string.concat(
                "<polygon points=\"16,3 28,28 4,28\" fill=\"", color,
                "\" stroke=\"#000000\" stroke-width=\"1\"/>"
            );
        }
        // Void: forked tail — two legs.
        return string.concat(
            "<polygon points=\"5,4 13,4 13,16 11,28 7,28 5,16\" fill=\"", color, "\" stroke=\"#000000\" stroke-width=\"1\"/>",
            "<polygon points=\"19,4 27,4 27,16 25,28 21,28 19,16\" fill=\"", color, "\" stroke=\"#000000\" stroke-width=\"1\"/>"
        );
    }

    function _svg(uint8 piece) internal pure returns (string memory) {
        return string.concat(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 32 40\" shape-rendering=\"crispEdges\">",
            "<rect width=\"32\" height=\"40\" fill=\"#0A0908\"/>",
            "<polygon points=\"4,3 4,27 10,21 13,28 16,26.5 13,19.5 20,19.5\" fill=\"#26262E\"/>",
            _pieceArt(piece),
            "<text x=\"16\" y=\"38\" font-family=\"monospace\" font-size=\"5\" fill=\"#E8E8E8\" text-anchor=\"middle\">",
            _pieceName(piece),
            "</text></svg>"
        );
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint8 piece = _pieceOf[tokenId];
        string memory svg = Base64.encode(bytes(_svg(piece)));
        string memory json = Base64.encode(
            bytes(
                string.concat(
                    "{\"name\":\"Rifera Cursor Piece #",
                    tokenId.toString(),
                    " - ",
                    _pieceName(piece),
                    "\",\"description\":\"One of the 5 pieces that build a First Cursor: Pointer, Ember, Verdant, Frost, Void. First piece free, the rest 0.002 BNB each. Agent ID required.\",",
                    "\"image\":\"data:image/svg+xml;base64,",
                    svg,
                    "\",\"attributes\":[",
                    "{\"trait_type\":\"Piece\",\"value\":\"",
                    _pieceName(piece),
                    "\"},",
                    "{\"trait_type\":\"Piece Index\",\"value\":",
                    uint256(piece).toString(),
                    "},",
                    "{\"trait_type\":\"Color\",\"value\":\"",
                    _pieceColor(piece),
                    "\"}",
                    "]}"
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }
}
