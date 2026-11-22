// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiferaCursorPieces} from "../contracts/RiferaCursorPieces.sol";
import {MockAgentId} from "./MockAgentId.sol";

contract RiferaCursorPiecesTest is Test {
    RiferaCursorPieces pieces;
    MockAgentId registry;
    address owner;
    address alice;
    address bob; // no Agent ID

    string[5] internal NAMES = ["Pointer", "Ember", "Verdant", "Frost", "Void"];

    function setUp() public {
        registry = new MockAgentId();
        pieces = new RiferaCursorPieces(address(registry));
        owner = pieces.owner();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        registry.mintTo(alice);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(owner, 1 ether);
        pieces.setMintOpen(true);
    }

    // ---------- helpers ----------

    function mintNext(address who, uint256 value) internal returns (uint256 tokenId) {
        uint256 before = pieces.totalMinted();
        vm.prank(who);
        pieces.mint{value: value}();
        return before + 1; // tokenIds are sequential from 1
    }

    /// @notice Minimal base64 decoder (test-only, to check tokenURI JSON/SVG).
    function b64decode(string memory data) internal pure returns (bytes memory) {
        bytes memory b = bytes(data);
        require(b.length % 4 == 0, "bad b64");
        bytes memory out = new bytes((b.length / 4) * 3);
        uint256 outLen;
        for (uint256 i; i < b.length; i += 4) {
            uint256 n;
            for (uint256 j; j < 4; j++) {
                uint8 c = uint8(b[i + j]);
                uint256 v;
                if (c >= 65 && c <= 90) v = c - 65;
                else if (c >= 97 && c <= 122) v = c - 71;
                else if (c >= 48 && c <= 57) v = c + 4;
                else if (c == 43) v = 62;
                else if (c == 47) v = 63;
                else v = 0; // '=' padding
                n = (n << 6) | v;
            }
            out[outLen++] = bytes1(uint8(n >> 16));
            out[outLen++] = bytes1(uint8(n >> 8));
            out[outLen++] = bytes1(uint8(n));
        }
        // trim padding
        uint256 pad;
        if (b.length >= 2 && b[b.length - 1] == bytes1("=")) pad++;
        if (b.length >= 2 && b[b.length - 2] == bytes1("=")) pad++;
        bytes memory trimmed = new bytes(outLen - pad);
        for (uint256 i; i < outLen - pad; i++) trimmed[i] = out[i];
        return trimmed;
    }

    function decodeTokenURI(uint256 tokenId) internal view returns (string memory json, string memory svg) {
        string memory uri = pieces.tokenURI(tokenId);
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory u = bytes(uri);
        require(u.length > prefix.length, "bad uri");
        bytes memory tmp = new bytes(u.length - prefix.length);
        string memory b64 = string(tmp);
        bytes memory b64b = bytes(b64);
        for (uint256 i; i < b64b.length; i++) b64b[i] = u[prefix.length + i];
        json = string(b64decode(b64));
        // extract image base64 between "data:image/svg+xml;base64," and '",'
        bytes memory j = bytes(json);
        bytes memory marker = bytes("data:image/svg+xml;base64,");
        uint256 start;
        bool found;
        for (uint256 i; i + marker.length <= j.length; i++) {
            bool ok = true;
            for (uint256 k; k < marker.length; k++) if (j[i + k] != marker[k]) ok = false;
            if (ok) { start = i + marker.length; found = true; break; }
        }
        require(found, "no svg in json");
        uint256 end = start;
        while (end < j.length && j[end] != bytes1('"')) end++;
        bytes memory tmp2 = new bytes(end - start);
        string memory svgB64 = string(tmp2);
        bytes memory s = bytes(svgB64);
        for (uint256 i; i < s.length; i++) s[i] = j[start + i];
        svg = string(b64decode(svgB64));
    }

    function contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) if (h[i + j] != n[j]) ok = false;
            if (ok) return true;
        }
        return false;
    }

    // ---------- quote ----------

    function testQuoteFirstIsFree() public view {
        assertEq(pieces.nextMintQuote(alice), 0);
    }

    function testQuoteSecondIs0002() public {
        mintNext(alice, 0);
        assertEq(pieces.nextMintQuote(alice), 0.002 ether);
    }

    function testQuoteAfterCompleteReverts() public {
        for (uint256 i; i < 5; i++) mintNext(alice, i == 0 ? 0 : 0.002 ether);
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.MaxPiecesMinted.selector, alice));
        pieces.nextMintQuote(alice);
    }

    // ---------- mint: free first, paid next, order ----------

    function testFirstMintFreePointer() public {
        uint256 id = mintNext(alice, 0);
        assertEq(id, 1);
        assertEq(pieces.pieceOf(id), 0);
        assertEq(pieces.ownerOf(id), alice);
        assertEq(pieces.totalMinted(), 1);
        assertEq(address(pieces).balance, 0);
    }

    function testSequentialOrderAllFive() public {
        for (uint256 i; i < 5; i++) {
            uint256 id = mintNext(alice, i == 0 ? 0 : 0.002 ether);
            assertEq(id, i + 1);
            assertEq(pieces.pieceOf(id), uint8(i));
        }
        uint8[] memory owned = pieces.piecesOf(alice);
        assertEq(owned.length, 5);
        for (uint256 i; i < 5; i++) assertEq(owned[i], uint8(i));
        uint256[] memory ids = pieces.tokenIdsOf(alice);
        assertEq(ids.length, 5);
        for (uint256 i; i < 5; i++) assertEq(ids[i], i + 1);
    }

    function testPaidMintForwards100PercentToOwner() public {
        mintNext(alice, 0);
        uint256 ownerBefore = owner.balance;
        mintNext(alice, 0.002 ether);
        assertEq(owner.balance - ownerBefore, 0.002 ether);
        assertEq(address(pieces).balance, 0);
        // all 4 paid mints forward too
        mintNext(alice, 0.002 ether);
        mintNext(alice, 0.002 ether);
        mintNext(alice, 0.002 ether);
        assertEq(owner.balance - ownerBefore, 4 * 0.002 ether);
        assertEq(address(pieces).balance, 0);
    }

    // ---------- mint: reverts ----------

    function testMintClosedReverts() public {
        pieces.setMintOpen(false);
        vm.prank(alice);
        vm.expectRevert(RiferaCursorPieces.MintClosed.selector);
        pieces.mint();
    }

    function testNoAgentIdReverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.NoAgentId.selector, bob));
        pieces.mint();
    }

    function testUnderpayReverts() public {
        mintNext(alice, 0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorPieces.InsufficientPayment.selector, 0.002 ether, 0.001 ether)
        );
        pieces.mint{value: 0.001 ether}();
    }

    function testOverpayReverts() public {
        mintNext(alice, 0);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorPieces.ExcessPayment.selector, 0.002 ether, 0.003 ether)
        );
        pieces.mint{value: 0.003 ether}();
    }

    function testFreeMintWithPaymentReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorPieces.ExcessPayment.selector, 0, 0.002 ether)
        );
        pieces.mint{value: 0.002 ether}();
    }

    function testSixthMintReverts() public {
        for (uint256 i; i < 5; i++) mintNext(alice, i == 0 ? 0 : 0.002 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.MaxPiecesMinted.selector, alice));
        pieces.mint{value: 0.002 ether}();
        assertEq(pieces.totalMinted(), 5);
    }

    function testSecondWalletStartsAtPointerFree() public {
        for (uint256 i; i < 5; i++) mintNext(alice, i == 0 ? 0 : 0.002 ether);
        address carol = makeAddr("carol");
        registry.mintTo(carol);
        vm.deal(carol, 1 ether);
        uint256 id = mintNext(carol, 0);
        assertEq(pieces.pieceOf(id), 0);
        assertEq(pieces.totalMinted(), 6);
    }

    // ---------- complete set ----------

    function testHasCompleteSet() public {
        assertFalse(pieces.hasCompleteSet(alice));
        for (uint256 i; i < 4; i++) {
            mintNext(alice, i == 0 ? 0 : 0.002 ether);
            assertFalse(pieces.hasCompleteSet(alice));
        }
        mintNext(alice, 0.002 ether);
        assertTrue(pieces.hasCompleteSet(alice));
    }

    // ---------- tokenURI / SVG ----------

    function testSvgContainsPieceNameAndShapesDiffer() public {
        string[5] memory svgs;
        for (uint256 i; i < 5; i++) {
            uint256 id = mintNext(alice, i == 0 ? 0 : 0.002 ether);
            (string memory json, string memory svg) = decodeTokenURI(id);
            assertTrue(contains(json, NAMES[i]), "json missing piece name");
            assertTrue(contains(svg, NAMES[i]), "svg missing piece name");
            assertTrue(contains(svg, "<svg"), "svg missing <svg>");
            svgs[i] = svg;
        }
        // every pair of SVGs must differ (different shape, not just colour)
        for (uint256 i; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertFalse(
                    keccak256(bytes(svgs[i])) == keccak256(bytes(svgs[j])),
                    "two pieces share identical SVG"
                );
            }
        }
    }

    function testSvgShapeMarkers() public {
        // Pointer triangle, Verdant staircase rects, Frost wedge, Void fork.
        mintNext(alice, 0);
        (, string memory svg0) = decodeTokenURI(1);
        assertTrue(contains(svg0, "16,2 27,16 5,16"));
        mintNext(alice, 0.002 ether); // Ember
        (, string memory svg1) = decodeTokenURI(2);
        assertTrue(contains(svg1, "22,11 22,16 27,16"));
        mintNext(alice, 0.002 ether); // Verdant
        (, string memory svg2) = decodeTokenURI(3);
        assertTrue(contains(svg2, "<rect"));
        assertTrue(contains(svg2, "x=\"20\" y=\"20\""));
        mintNext(alice, 0.002 ether); // Frost
        (, string memory svg3) = decodeTokenURI(4);
        assertTrue(contains(svg3, "16,3 28,28 4,28"));
        mintNext(alice, 0.002 ether); // Void
        (, string memory svg4) = decodeTokenURI(5);
        assertTrue(contains(svg4, "11,28 7,28"));
        assertTrue(contains(svg4, "25,28 21,28"));
    }

    // ---------- supply cap (1,111 per piece, 5,555 total) ----------

    /// @notice Mint free Pointers for `count` fresh wallets (Agent ID each).
    function fillPointer(uint256 count, uint256 start) internal {
        for (uint256 i; i < count; i++) {
            address w = address(uint160(0x10000 + start + i));
            registry.mintTo(w);
            vm.prank(w);
            pieces.mint();
        }
    }

    function testCapConstants() public view {
        assertEq(pieces.MAX_SUPPLY_PER_PIECE(), 1111);
        assertEq(pieces.MAX_TOTAL_SUPPLY(), 5555);
        for (uint8 p; p < 5; p++) {
            assertEq(pieces.mintedPerPiece(p), 0);
            assertEq(pieces.remainingPerPiece(p), 1111);
        }
    }

    function testMintedPerPieceCounts() public {
        mintNext(alice, 0);
        assertEq(pieces.mintedPerPiece(0), 1);
        assertEq(pieces.remainingPerPiece(0), 1110);
        mintNext(alice, 0.002 ether);
        assertEq(pieces.mintedPerPiece(1), 1);
        assertEq(pieces.remainingPerPiece(1), 1110);
        assertEq(pieces.mintedPerPiece(2), 0);
    }

    function testPointerCapEnforced() public {
        fillPointer(1111, 0);
        assertEq(pieces.mintedPerPiece(0), 1111);
        assertEq(pieces.remainingPerPiece(0), 0);
        assertEq(pieces.totalMinted(), 1111);
        // 1,112th wallet: mint reverts with PieceSoldOut(0) ...
        address dave = makeAddr("dave");
        registry.mintTo(dave);
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.PieceSoldOut.selector, uint8(0)));
        pieces.mint();
        // ... and the quote reverts too (never quote a mint that must fail).
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.PieceSoldOut.selector, uint8(0)));
        pieces.nextMintQuote(dave);
        assertEq(pieces.totalMinted(), 1111);
    }

    function testCapPerPieceIndependent() public {
        // Alice already holds a Pointer before the cap fills.
        mintNext(alice, 0);
        fillPointer(1110, 0); // Pointer now at 1,111 (sold out)
        assertEq(pieces.mintedPerPiece(0), 1111);
        assertEq(pieces.remainingPerPiece(0), 0);
        // Pointer being sold out does NOT block Alice's Ember mint.
        uint256 id = mintNext(alice, 0.002 ether);
        assertEq(pieces.pieceOf(id), 1);
        assertEq(pieces.mintedPerPiece(1), 1);
        assertEq(pieces.remainingPerPiece(1), 1110);
        // But a brand-new wallet cannot start (it must start at Pointer).
        address dave = makeAddr("dave");
        registry.mintTo(dave);
        vm.deal(dave, 1 ether);
        vm.prank(dave);
        vm.expectRevert(abi.encodeWithSelector(RiferaCursorPieces.PieceSoldOut.selector, uint8(0)));
        pieces.mint();
    }

    // ---------- owner controls / withdraw safety net ----------

    function testOnlyOwnerCanOpenClose() public {
        vm.prank(alice);
        vm.expectRevert();
        pieces.setMintOpen(false);
    }

    function testWithdrawSendsStuckBalanceToOwner() public {
        // Simulate stuck ETH (e.g. forced in via selfdestruct): set the
        // contract balance directly — the contract has no receive(), so a
        // plain transfer would revert by design.
        vm.deal(address(pieces), 0.5 ether);
        assertEq(address(pieces).balance, 0.5 ether);
        uint256 before = owner.balance;
        vm.prank(owner);
        pieces.withdraw();
        assertEq(address(pieces).balance, 0);
        assertEq(owner.balance - before, 0.5 ether);
    }

    function testWithdrawOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        pieces.withdraw();
    }

    // allow this test contract to receive ETH in withdraw test setup
    receive() external payable {}
}
