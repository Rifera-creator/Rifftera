// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal interface of RiferaCursorPieces needed by the stake
/// contract: piece index of a token (reverts for unminted tokens).
interface IRiferaCursorPieces is IERC721 {
    function pieceOf(uint256 tokenId) external view returns (uint8);
}

/// @title Rifera Cursor Stake
/// @notice Stake one complete RPIECE set (exactly one of each piece:
/// Pointer 0, Ember 1, Verdant 2, Frost 3, Void 4) and share the BNB pool.
/// One set per wallet — RPIECE itself caps at 5 pieces per wallet, so this
/// is the natural limit. The 5 NFTs move into this contract while staked
/// and are returned in full on unstake.
///
/// @dev Reward model (Shardblade-style): every full day, 10% of the pool
/// that is still unreleased is released and split evenly between all sets
/// currently staked (accRewardPerSet, MasterChef-style). Rewards only
/// accrue while at least one set is staked — with zero stakers the pool is
/// left completely untouched (only lastUpdate advances). A staker who joins
/// late earns only from distributions after they stake (rewardDebt is set
/// to the current accRewardPerSet at stake time), never retroactively.
///
/// @dev Pool funding is MANUAL ONLY: anyone may call fundPool() (the owner
/// is expected to fund it from mint proceeds). There is NO automatic split
/// from the RPIECE mint contract and NO owner withdraw of the pool — pool
/// BNB leaves this contract only through staker claims. The owner recorded
/// in Ownable has no privileged functions over the pool or anyone's NFTs.
contract RiferaCursorStake is Ownable, ReentrancyGuard, IERC721Receiver {
    IRiferaCursorPieces public immutable rpiece;

    /// @notice 10% of the remaining pool is released per day.
    uint256 public constant DAILY_RELEASE_BPS = 1000;
    uint256 public constant BPS_DENOMINATOR = 10000;
    /// @notice Precision for accRewardPerSet (reward per staked set, x1e18).
    uint256 public constant ACC_PRECISION = 1e18;
    /// @notice Reward accrual is capped at 365 days per update call, so a
    /// long gap between interactions cannot make one call loop forever.
    uint256 public constant MAX_ACCRUAL_DAYS = 365;

    /// @notice Pool BNB not yet released to stakers.
    uint256 public poolBalance;
    /// @notice Cumulative BNB reward per staked set, scaled by 1e18.
    uint256 public accRewardPerSet;
    /// @notice Timestamp of the last reward update.
    uint256 public lastUpdate;
    /// @notice Sets currently staked.
    uint256 public totalStaked;

    mapping(address => uint256[5]) private _stakedTokens;
    /// @notice True while a wallet has a set staked in this contract.
    mapping(address => bool) public hasStake;
    /// @notice accRewardPerSet at the wallet's last settle, scaled by 1e18.
    mapping(address => uint256) public rewardDebt;
    /// @notice Settled but unclaimed BNB (wei) for a wallet.
    mapping(address => uint256) public claimable;

    event Staked(address indexed user, uint256[5] tokenIds);
    event Unstaked(address indexed user, uint256[5] tokenIds, uint256 rewardPaid);
    event Claimed(address indexed user, uint256 amount);
    event PoolFunded(address indexed funder, uint256 amount);

    error AlreadyStaked(address user);
    error NotStaked(address user);
    error WrongPiece(uint256 tokenId, uint8 expected, uint8 actual);
    error NotTokenOwner(uint256 tokenId, address owner);
    error ZeroFund();
    error TransferFailed();

    constructor(address rpiece_, address owner_) Ownable(owner_) {
        require(rpiece_ != address(0), "rpiece is zero address");
        require(owner_ != address(0), "owner is zero address");
        rpiece = IRiferaCursorPieces(rpiece_);
        lastUpdate = block.timestamp;
    }

    /// @notice Stake one complete set: tokenIds[0] must be Pointer,
    /// tokenIds[1] Ember, tokenIds[2] Verdant, tokenIds[3] Frost,
    /// tokenIds[4] Void — each owned by the caller. The 5 NFTs move into
    /// this contract (caller must approve first). One set per wallet.
    function stake(uint256[5] calldata tokenIds) external nonReentrant {
        if (hasStake[msg.sender]) revert AlreadyStaked(msg.sender);
        _updateRewards();
        for (uint256 i; i < 5; i++) {
            uint256 id = tokenIds[i];
            // pieceOf reverts for unminted tokens (ERC721NonexistentToken).
            uint8 piece = rpiece.pieceOf(id);
            if (piece != uint8(i)) revert WrongPiece(id, uint8(i), piece);
            address tokenOwner = rpiece.ownerOf(id);
            if (tokenOwner != msg.sender) revert NotTokenOwner(id, tokenOwner);
        }
        _stakedTokens[msg.sender] = tokenIds;
        hasStake[msg.sender] = true;
        totalStaked += 1;
        rewardDebt[msg.sender] = accRewardPerSet;
        for (uint256 i; i < 5; i++) {
            rpiece.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }
        emit Staked(msg.sender, tokenIds);
    }

    /// @notice Unstake: returns all 5 NFTs to the staker and pays out all
    /// pending rewards in the same call. After this the wallet can stake
    /// a set again.
    function unstake() external nonReentrant {
        if (!hasStake[msg.sender]) revert NotStaked(msg.sender);
        _updateRewards();
        _settle(msg.sender);
        uint256 reward = claimable[msg.sender];
        claimable[msg.sender] = 0;
        uint256[5] memory tokenIds = _stakedTokens[msg.sender];
        delete _stakedTokens[msg.sender];
        hasStake[msg.sender] = false;
        rewardDebt[msg.sender] = 0;
        totalStaked -= 1;
        for (uint256 i; i < 5; i++) {
            rpiece.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }
        _pay(msg.sender, reward);
        emit Unstaked(msg.sender, tokenIds, reward);
    }

    /// @notice Claim pending rewards without unstaking. Claiming 0 pays 0
    /// (no revert) — a second claim right after the first simply pays 0.
    function claim() external nonReentrant {
        if (!hasStake[msg.sender]) revert NotStaked(msg.sender);
        _updateRewards();
        _settle(msg.sender);
        uint256 amount = claimable[msg.sender];
        claimable[msg.sender] = 0;
        _pay(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    /// @notice Fund the reward pool with BNB. Anyone may fund — the owner
    /// is expected to fund it from mint proceeds. Funds added here start
    /// releasing from the NEXT day (today's release was already computed
    /// from the old pool). There is no owner withdraw of the pool.
    function fundPool() external payable {
        if (msg.value == 0) revert ZeroFund();
        _updateRewards();
        poolBalance += msg.value;
        emit PoolFunded(msg.sender, msg.value);
    }

    /// @notice Total sets currently staked.
    function stakedSets() external view returns (uint256) {
        return totalStaked;
    }

    /// @notice Token ids staked by a wallet ([0,0,0,0,0] when not staked).
    function stakedBy(address user) external view returns (uint256[5] memory) {
        return _stakedTokens[user];
    }

    /// @notice Pending reward (wei) for a wallet: settled claimable plus
    /// rewards accrued since the last settle, simulating the daily 10%
    /// releases up to now. Does not change state.
    function pendingReward(address user) external view returns (uint256) {
        uint256 pending = claimable[user];
        if (!hasStake[user]) return pending;
        uint256 daysElapsed = (block.timestamp - lastUpdate) / 1 days;
        if (daysElapsed > MAX_ACCRUAL_DAYS) daysElapsed = MAX_ACCRUAL_DAYS;
        uint256 simAcc = accRewardPerSet;
        uint256 simPool = poolBalance;
        if (totalStaked > 0) {
            for (uint256 i; i < daysElapsed; i++) {
                uint256 release = (simPool * DAILY_RELEASE_BPS) / BPS_DENOMINATOR;
                if (release == 0) break; // dust: pool too small to release
                simAcc += (release * ACC_PRECISION) / totalStaked;
                simPool -= release;
            }
        }
        return pending + (simAcc - rewardDebt[user]) / ACC_PRECISION;
    }

    /// @notice Settle a staker's accrued rewards into claimable and reset
    /// their debt to the current acc. Caller must have a stake.
    function _settle(address user) internal {
        uint256 pending = (accRewardPerSet - rewardDebt[user]) / ACC_PRECISION;
        if (pending > 0) claimable[user] += pending;
        rewardDebt[user] = accRewardPerSet;
    }

    /// @notice Release 10% of the remaining pool per full day elapsed since
    /// lastUpdate (capped at 365 days), split between staked sets. With
    /// zero stakers nothing is released — the pool stays whole — but
    /// lastUpdate still advances so those days are never paid retroactively.
    function _updateRewards() internal {
        uint256 daysElapsed = (block.timestamp - lastUpdate) / 1 days;
        if (daysElapsed == 0) return;
        if (daysElapsed > MAX_ACCRUAL_DAYS) daysElapsed = MAX_ACCRUAL_DAYS;
        lastUpdate += daysElapsed * 1 days;
        if (totalStaked == 0) return;
        for (uint256 i; i < daysElapsed; i++) {
            uint256 release = (poolBalance * DAILY_RELEASE_BPS) / BPS_DENOMINATOR;
            if (release == 0) break; // dust: pool too small to release
            accRewardPerSet += (release * ACC_PRECISION) / totalStaked;
            poolBalance -= release;
        }
    }

    function _pay(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Required so safeTransferFrom into this contract works.
    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
