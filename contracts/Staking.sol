// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Staking is Ownable {

    using SafeERC20 for IERC20;
    
    uint256 constant stakingPeriod = 30 * 8 days;
    uint256 constant stakeablePeriod = 30 * 2 days;
    uint256 constant rewardPeriod = 5 seconds;
    uint256 constant maximumRewardRate = 2500;        // 25%
    uint256 constant rewardRateDeprecator = 25000;    // 250%
    uint256 constant thresholdTVL = 1000000 * 1e18; // 10M Tokens
    uint256 constant penaltyRate = 6000;

    uint256 _initPeriod;
    IERC20 _stakingToken;

    struct Stake {
        uint256 amount;
        uint256 accumulatedRewards;
        uint256 stakedAt;
        uint256 endDate;
        uint256 lastUpdated;
    }

    mapping(address => Stake) private _stakes;

    modifier updateReward(address user) {
        Stake storage userStake = _stakes[user];
        userStake.accumulatedRewards += calculateRewards(user);
        userStake.lastUpdated = block.timestamp;
        _;
    }

    event LogStake(
        address user,
        uint256 amount,
        uint256 previousRewards,
        uint256 stakedAt
    );

    event LogUnstake(
        address user,
        uint256 amount,
        uint256 reward,
        uint256 timestamp
    );

    constructor(IERC20 stakingToken_) Ownable(msg.sender) {
        _initPeriod = block.timestamp;
        _stakingToken = stakingToken_;
    }

    function stake(uint256 amount) external updateReward(msg.sender) {
        require(block.timestamp - _initPeriod < stakeablePeriod, "ERR: NOT STAKEABLE");
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 previousRewards = _stake(msg.sender, amount);
        _stakingToken.safeTransfer(msg.sender, previousRewards);
        _stake(msg.sender, amount);
        emit LogStake(
            msg.sender,
            amount,
            previousRewards,
            block.timestamp
        );
    }

    function unstake() external updateReward(msg.sender) {
        (uint256 amount, uint256 reward) = _unstake(msg.sender);
        _stakingToken.safeTransfer(msg.sender, amount + reward);
        emit LogUnstake(
            msg.sender,
            amount,
            reward,
            block.timestamp
        );
    }

    function delegateStake(address user, uint256 amount) external updateReward(msg.sender) onlyOwner {
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 previousRewards = _stake(user, amount);
        _stakingToken.safeTransfer(msg.sender, previousRewards);   
    }

    function withdrawAdmin(address user) external updateReward(user) onlyOwner {
        require((_stakes[user].endDate + stakeablePeriod) < block.timestamp, "ERR: STAKE NOT MATURED YET");
        (uint256 amount, uint256 reward) = _unstake(user);
        _stakingToken.safeTransfer(msg.sender, amount + reward);
    }

    function TVL() public view returns(uint256) {
        return _stakingToken.balanceOf(address(this));
    }

    function calculateRewards(address user) public view returns(uint256) {
        Stake memory userStake = _stakes[user];
        uint256 elapsedTime = block.timestamp - userStake.lastUpdated;
        uint256 tvlFactor = TVL() / thresholdTVL;
        uint256 apr = tvlFactor >= 10 ? rewardRateDeprecator : maximumRewardRate - (tvlFactor * rewardRateDeprecator);
        uint256 reward = (userStake.amount * apr * rewardPeriod) / 365 / 1e4;
        if(elapsedTime > rewardPeriod) {
            reward = reward * elapsedTime / rewardPeriod;
        }
        return reward;
    }

    function _stake(address user, uint256 amount) internal returns(uint256) {
        Stake storage userStake = _stakes[user];
        userStake.amount += amount;
        userStake.stakedAt = block.timestamp;
        userStake.endDate = block.timestamp + stakingPeriod;
        uint256 accumulatedRewards = userStake.accumulatedRewards;
        userStake.accumulatedRewards = 0;
        return accumulatedRewards;
    }

    function _unstake(address user) internal returns(uint256, uint256) {
        Stake storage userStake = _stakes[user];
        if(block.timestamp < userStake.endDate) {
            userStake.amount -= userStake.amount * penaltyRate / 1e4;
        }
        uint256 withdrawableStake = userStake.amount;
        uint256 withdrawableReward = userStake.accumulatedRewards;

        userStake.amount = 0;
        userStake.accumulatedRewards = 0;
        return (withdrawableStake, withdrawableReward);
    }
}