// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";

contract Staking360days {
    using SafeMath for uint256;

    IERC20 public token;
    uint256 public constant DEFAULT_RATE = 155 * 1e16; // 155% per year as base rate (in 1e18 format)
    uint256 public constant SCALING_FACTOR = 1e18;
    uint256 public constant LOCKUP_PERIOD = 360 days; // 1 year lockup period

    address payable public feeAddress; // Address where fees are sent
    uint256 public constant CLAIM_FEE = 5 * 1e6; // Fee for claiming rewards (5 TRX in sun)

    // Struct to store user's staking data
    struct StakerData {
        uint256 totalStaked;
        uint256 lastStakedTimestamp;
        uint256 reward;
        uint256[] lockupTimestamps; // Array to store multiple lockup periods
        uint256[] amountsStaked; // Array to store the amounts of tokens staked at different times
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
        
        // Add the new lockup period for the current stake
        staker.lockupTimestamps.push(block.timestamp.add(LOCKUP_PERIOD)); // Lockup period for this stake
        staker.amountsStaked.push(amount); // Store the amount of tokens staked at this timestamp
    }

    function unstake(uint256 amount) public payable {
        StakerData storage staker = stakers[msg.sender];
        uint256 totalAmountStaked = staker.totalStaked;
        require(totalAmountStaked >= amount, "Not enough staked tokens");

        uint256 unstakedAmount = 0;
        uint256 unstakedCount = 0;

        // Iterate through all staked amounts to unstake tokens based on lockup periods
        for (uint256 i = 0; i < staker.lockupTimestamps.length; i++) {
            if (block.timestamp >= staker.lockupTimestamps[i] && unstakedAmount < amount) {
                uint256 availableForUnstake = staker.amountsStaked[i];
                if (unstakedAmount + availableForUnstake > amount) {
                    uint256 remainingAmount = amount - unstakedAmount;
                    unstakedAmount = amount;
                    staker.amountsStaked[i] = availableForUnstake - remainingAmount; // Adjust staked amount
                    break;
                } else {
                    unstakedAmount += availableForUnstake;
                    staker.amountsStaked[i] = 0; // Mark this portion as unstaked
                    unstakedCount++;
                }
            }
        }

        // Ensure we unstaked the correct amount
        require(unstakedAmount == amount, "Amount mismatch during unstaking");

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

    // Helper function to get the unstaking periods for a user
    function getUnstakingPeriods(address user) public view returns (uint256[] memory) {
        StakerData storage staker = stakers[user];
        return staker.lockupTimestamps; // Returns the list of lockup timestamps for the user
    }

    // Helper function to get the amounts staked
    function getAmountsStaked(address user) public view returns (uint256[] memory) {
        StakerData storage staker = stakers[user];
        return staker.amountsStaked; // Returns the list of amounts staked by the user
    }
}
