// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiferaCursorPieces} from "../contracts/RiferaCursorPieces.sol";
import {RiferaCursorStake} from "../contracts/RiferaCursorStake.sol";
import {MockAgentId} from "./MockAgentId.sol";

contract RiferaCursorStakeTest is Test {
    RiferaCursorPieces pieces;
    RiferaCursorStake stake;
    MockAgentId registry;
    address owner;
    address alice;
    address bob;

    function setUp() public {
        registry = new MockAgentId();
        pieces = new RiferaCursorPieces(address(registry));
        owner = pieces.owner();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        registry.mintTo(alice);
        registry.mintTo(bob);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(owner, 100 ether);
        pieces.setMintOpen(true);
        stake = new RiferaCursorStake(address(pieces), owner);
    }

    // ---------- helpers ----------

    /// @notice Mint a full set (Pointer..Void, 0 + 4 x 0.002 BNB) for `who`.
    function mintSet(address who) internal returns (uint256[5] memory ids) {
        for (uint256 i; i < 5; i++) {
            uint256 before = pieces.totalMinted();
            vm.prank(who);
            pieces.mint{value: i == 0 ? 0 : 0.002 ether}();
            ids[i] = before + 1;
        }
    }

    /// @notice Approve + stake `ids` as `who`.
    function stakeAs(address who, uint256[5] memory ids) internal {
        vm.startPrank(who);
        for (uint256 i; i < 5; i++) pieces.approve(address(stake), ids[i]);
        stake.stake(ids);
        vm.stopPrank();
    }

    // ---------- stake: success ----------

    function testStakeSuccess() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        assertEq(stake.stakedSets(), 1);
        assertTrue(stake.hasStake(alice));
        uint256[5] memory held = stake.stakedBy(alice);
        for (uint256 i; i < 5; i++) {
            assertEq(held[i], ids[i]);
            assertEq(pieces.ownerOf(ids[i]), address(stake));
        }
        assertEq(stake.pendingReward(alice), 0);
    }

    function testStakeConstants() public view {
        assertEq(stake.DAILY_RELEASE_BPS(), 1000);
        assertEq(stake.poolBalance(), 0);
        assertEq(stake.accRewardPerSet(), 0);
        assertEq(stake.stakedSets(), 0);
    }

    // ---------- stake: reverts ----------

    function testStakeNotOwnerReverts() public {
        uint256[5] memory ids = mintSet(alice);
        // Bob owns none of these; piece order is right, ownership is not.
        // No approval needed: the ownership check fires before any transfer.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorStake.NotTokenOwner.selector, ids[0], alice)
        );
        stake.stake(ids);
    }

    function testStakeWrongOrderReverts() public {
        uint256[5] memory ids = mintSet(alice);
        uint256[5] memory reversed = [ids[4], ids[3], ids[2], ids[1], ids[0]];
        vm.startPrank(alice);
        for (uint256 i; i < 5; i++) pieces.approve(address(stake), ids[i]);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiferaCursorStake.WrongPiece.selector, ids[4], uint8(0), uint8(4)
            )
        );
        stake.stake(reversed);
        vm.stopPrank();
    }

    function testStakeDuplicatePieceReverts() public {
        uint256[5] memory ids = mintSet(alice);
        // ids[1] twice: slot 1 expects Ember but gets Pointer (piece 0).
        uint256[5] memory dup = [ids[0], ids[0], ids[2], ids[3], ids[4]];
        vm.startPrank(alice);
        for (uint256 i; i < 5; i++) pieces.approve(address(stake), ids[i]);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiferaCursorStake.WrongPiece.selector, ids[0], uint8(1), uint8(0)
            )
        );
        stake.stake(dup);
        vm.stopPrank();
    }

    function testStakeNonexistentTokenReverts() public {
        uint256[5] memory ids = mintSet(alice);
        uint256[5] memory bad = [ids[0], ids[1], ids[2], ids[3], 999];
        vm.startPrank(alice);
        for (uint256 i; i < 5; i++) pieces.approve(address(stake), ids[i]);
        vm.expectRevert(); // pieceOf(999) reverts (ERC721NonexistentToken)
        stake.stake(bad);
        vm.stopPrank();
    }

    function testStakeTwiceReverts() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorStake.AlreadyStaked.selector, alice)
        );
        stake.stake(ids);
        assertEq(stake.stakedSets(), 1);
    }

    function testStakeWithoutApprovalReverts() public {
        uint256[5] memory ids = mintSet(alice);
        vm.prank(alice);
        vm.expectRevert(); // safeTransferFrom without approval reverts
        stake.stake(ids);
    }

    // ---------- fund + rewards ----------

    function testOneDayPendingIs10Percent() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        assertEq(stake.poolBalance(), 10 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(stake.pendingReward(alice), 1 ether);
    }

    function testTwoDayCompoundingIs19Percent() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 2 days);
        // Day 1 releases 10% of 10 = 1; day 2 releases 10% of 9 = 0.9.
        assertEq(stake.pendingReward(alice), 1.9 ether);
        assertEq(stake.poolBalance(), 10 ether); // pool only moves on interaction
    }

    function testClaimPaysExactAndSecondClaimIsZero() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 1 days);
        uint256 before = alice.balance;
        vm.prank(alice);
        stake.claim();
        assertEq(alice.balance - before, 1 ether);
        assertEq(stake.pendingReward(alice), 0);
        // Second claim right after pays 0 (no revert).
        vm.prank(alice);
        stake.claim();
        assertEq(alice.balance - before, 1 ether);
        assertEq(stake.pendingReward(alice), 0);
        // Stake is untouched by claiming.
        assertTrue(stake.hasStake(alice));
        assertEq(pieces.ownerOf(ids[0]), address(stake));
    }

    function testTwoStakersSplitEvenly() public {
        uint256[5] memory a = mintSet(alice);
        uint256[5] memory b = mintSet(bob);
        stakeAs(alice, a);
        stakeAs(bob, b);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 1 days);
        assertEq(stake.pendingReward(alice), 0.5 ether);
        assertEq(stake.pendingReward(bob), 0.5 ether);
    }

    function testLateStakerGetsNoRetroactiveRewards() public {
        uint256[5] memory a = mintSet(alice);
        uint256[5] memory b = mintSet(bob);
        stakeAs(alice, a);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 1 days);
        assertEq(stake.pendingReward(alice), 1 ether);
        // Bob joins on day 1: his debt is set to the current acc, so day 1
        // is Alice's alone.
        stakeAs(bob, b);
        vm.warp(block.timestamp + 1 days);
        // Day 2 releases 10% of 9 = 0.9, split 2 ways = 0.45 each.
        assertEq(stake.pendingReward(alice), 1.45 ether);
        assertEq(stake.pendingReward(bob), 0.45 ether);
    }

    function testFundPoolByAnyone() public {
        vm.prank(bob);
        stake.fundPool{value: 2 ether}();
        assertEq(stake.poolBalance(), 2 ether);
    }

    function testFundPoolZeroReverts() public {
        vm.prank(owner);
        vm.expectRevert(RiferaCursorStake.ZeroFund.selector);
        stake.fundPool{value: 0}();
    }

    // ---------- unstake ----------

    function testUnstakeReturnsNftsAndPaysReward() public {
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 1 days);
        uint256 before = alice.balance;
        vm.prank(alice);
        stake.unstake();
        assertEq(alice.balance - before, 1 ether);
        assertEq(stake.stakedSets(), 0);
        assertFalse(stake.hasStake(alice));
        assertEq(stake.pendingReward(alice), 0);
        for (uint256 i; i < 5; i++) assertEq(pieces.ownerOf(ids[i]), alice);
        // Can stake again after unstaking.
        stakeAs(alice, ids);
        assertEq(stake.stakedSets(), 1);
    }

    function testUnstakeWithoutStakeReverts() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorStake.NotStaked.selector, bob)
        );
        stake.unstake();
    }

    function testClaimWithoutStakeReverts() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(RiferaCursorStake.NotStaked.selector, bob)
        );
        stake.claim();
    }

    // ---------- no stakers: pool untouched ----------

    function testNoStakerPoolUntouched() public {
        vm.prank(owner);
        stake.fundPool{value: 10 ether}();
        vm.warp(block.timestamp + 30 days);
        assertEq(stake.poolBalance(), 10 ether);
        assertEq(stake.accRewardPerSet(), 0);
        // Staking after the idle period: rewards start from now, nothing
        // retroactive for the 30 idle days.
        uint256[5] memory ids = mintSet(alice);
        stakeAs(alice, ids);
        assertEq(stake.poolBalance(), 10 ether);
        vm.warp(block.timestamp + 1 days);
        assertEq(stake.pendingReward(alice), 1 ether);
    }

    // allow this test contract to receive ETH if needed
    receive() external payable {}
}
