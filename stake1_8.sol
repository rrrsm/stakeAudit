// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";

contract StakingNoLockup {
    using SafeMath for uint256;

    IERC20 public token;
    uint256 public constant DEFAULT_RATE = 8 * 1e16; // 8% per year as base rate (in 1e18 format)
    uint256 public constant SCALING_FACTOR = 1e18;

    address payable public feeAddress; // Address where fees are sent
    uint256 public constant CLAIM_FEE = 50 * 1e6; // Fee for claiming rewards (50 TRX in sun)
    uint256 public constant UNSTAKE_FEE = 100 * 1e6; // Fee for unstaking tokens (100 TRX in sun)

    // Struct to store user's staking data
    struct StakerData {
        uint256 totalStaked;
        uint256 lastStakedTimestamp;
        uint256 reward;
    }

    mapping(address => StakerData) public stakers;

    constructor(
        IERC20 _token,
        address payable _feeAddress
    ) {
        token = _token;
        feeAddress = _feeAddress;
    }

    function calculateReward(address user) public view returns (uint256) {
        StakerData storage staker = stakers[user];
        uint256 stakingDuration = block.timestamp.sub(staker.lastStakedTimestamp);
        uint256 currentRate = DEFAULT_RATE;
        uint256 rawReward = staker.totalStaked.mul(currentRate).mul(stakingDuration).div(SCALING_FACTOR).div(365 days);
        return rawReward;
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        token.transferFrom(msg.sender, address(this), amount);

        // Update staker's data
        StakerData storage staker = stakers[msg.sender];
        staker.reward = staker.reward.add(calculateReward(msg.sender));
        staker.totalStaked = staker.totalStaked.add(amount);
        staker.lastStakedTimestamp = block.timestamp;
    }

    function unstake(uint256 amount) public payable {
        require(msg.value >= UNSTAKE_FEE, "Insufficient fee for unstaking");
        StakerData storage staker = stakers[msg.sender];
        require(staker.totalStaked >= amount, "Not enough staked tokens");

        // Send the fee to the feeAddress
        feeAddress.transfer(msg.value);

        // Update staker's data
        staker.reward = staker.reward.add(calculateReward(msg.sender));
        staker.totalStaked = staker.totalStaked.sub(amount);
        staker.lastStakedTimestamp = block.timestamp;

        token.transfer(msg.sender, amount);
    }

    function claimReward() public payable {
        require(msg.value >= CLAIM_FEE, "Insufficient fee for claiming rewards");
        StakerData storage staker = stakers[msg.sender];
        uint256 reward = staker.reward.add(calculateReward(msg.sender));
        require(reward > 0, "No reward to claim");

        // Send the fee to the feeAddress
        feeAddress.transfer(msg.value);

        staker.reward = 0;
        staker.lastStakedTimestamp = block.timestamp;

        token.transfer(msg.sender, reward);
    }
}