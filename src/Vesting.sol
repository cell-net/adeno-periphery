// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";
import "openzeppelin/security/Pausable.sol";
import "openzeppelin/utils/math/SafeMath.sol";

contract Vesting is Ownable, Pausable {
    using SafeMath for uint256;

    uint256 public constant SECONDS_PER_MONTH = 2629746;

    struct VestingSchedule {
        uint256 totalTokens; // amount of tokens for a recipient
        uint256 releasePeriod; // Number of months for the release period
        uint256 startTime; // Start time of the vesting schedule
        uint256 releasedTokens; // Number of tokens released so far
    }

    // privatesale addr => (user addr => schedule)
    mapping(address => mapping(address => VestingSchedule)) public vestingSchedules;

    // privatesale addr => bool
    mapping(address => bool) public vestingSchedulesActive;
    mapping(address => bool) public whitelist;

    IERC20 public token;

    event TokensReleased(address beneficiary, uint256 amount);
    event VestingScheduleCreated(address beneficiary, uint256 totalTokens, uint256 startTime);

    constructor(address _token) {
        token = IERC20(_token);
    }

    function createVestingSchedule(address beneficiary, uint256 totalTokens, uint256 releasePeriod, uint256 startTime)
        external
        onlyWhitelisted
        whenNotPaused
    {
        require(totalTokens > 0, "Total tokens must be greater than zero");
        require(releasePeriod > 0, "Release period must be greater than zero");
        require(
            vestingSchedules[msg.sender][beneficiary].totalTokens == 0,
            "Vesting schedule already exists for the beneficiary"
        );

        VestingSchedule storage schedule = vestingSchedules[msg.sender][beneficiary];
        schedule.totalTokens = totalTokens;
        schedule.releasePeriod = releasePeriod;
        schedule.startTime = startTime == 0 ? block.timestamp : startTime;

        emit VestingScheduleCreated(beneficiary, totalTokens, startTime);
    }

    function releaseTokens(address contractAddress, address beneficiary) external whenNotPaused {
        require(vestingSchedulesActive[contractAddress] == true, "Vesting schedule not active.");
        VestingSchedule storage schedule = vestingSchedules[contractAddress][beneficiary];
        uint256 releasableTokens = getReleasableTokens(contractAddress, beneficiary);
        require(releasableTokens > 0, "No tokens available for release");
        schedule.releasedTokens = schedule.releasedTokens.add(releasableTokens);
        token.transfer(beneficiary, releasableTokens);
        emit TokensReleased(beneficiary, releasableTokens);
    }

    function getReleasableTokens(address contractAddress, address beneficiary) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[contractAddress][beneficiary];
        require(schedule.totalTokens > 0, "No vesting schedule found for the beneficiary");
        uint256 elapsedTime = block.timestamp.sub(schedule.startTime);
        uint256 totalReleasePeriods = schedule.releasePeriod;
        uint256 totalTokens = schedule.totalTokens;
        uint256 tokensPerPeriod = totalTokens.div(totalReleasePeriods);
        uint256 passedMonths = elapsedTime.div(SECONDS_PER_MONTH) > totalReleasePeriods
            ? totalReleasePeriods
            : elapsedTime.div(SECONDS_PER_MONTH);
        uint256 tokensToRelease = passedMonths.mul(tokensPerPeriod);

        // give remaining tokens if last month
        uint256 tokensToClaim;
        if(passedMonths == 0) {
            tokensToClaim = 0;
        } else {
            tokensToClaim = passedMonths == totalReleasePeriods
                ? totalTokens.sub(schedule.releasedTokens)
                : tokensToRelease.sub(schedule.releasedTokens);
        }
        return tokensToClaim;
    }

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Sender is not whitelisted");
        _;
    }

    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            whitelist[addr] = true;
        }
    }

    function removeFromWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            address addr = addresses[i];
            whitelist[addr] = false;
        }
    }

    function setVestingSchedulesActive(address contractAddress, bool active) external onlyOwner {
        vestingSchedulesActive[contractAddress] = active;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}