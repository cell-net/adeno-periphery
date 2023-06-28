// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Vesting.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";

contract PreSale is Ownable {
    using SafeMath for uint256;

    Vesting public vestingContract;
    IERC20 public token;
    bool public isSaleEnd;

    uint256 public tokenPrice;
    uint256 public maxTokensToSell;
    uint256 public remainingTokens;
    uint256 public duration;

    mapping(address => uint256) public vestedAmount;

    event TokensPurchased(address buyer, uint256 amount);
    event TokensClaimed(address beneficiary, uint256 amount);
    event ValueAmount(uint256 value, uint256 tokenAmount);

    constructor(address _vestingContract, address _token, uint256 _maxTokensToSell, uint256 _tokenPrice, uint256 _vestingDuration) {
        vestingContract = Vesting(_vestingContract);
        token = IERC20(_token);
        tokenPrice = _tokenPrice;
        duration = _vestingDuration;

        maxTokensToSell = _maxTokensToSell;
        remainingTokens = _maxTokensToSell;
    }

    modifier onlySaleEnd() {
        require(isSaleEnd, "Sale has not ended");
        _;
    }

    modifier onlySaleNotEnd() {
        require(!isSaleEnd, "Sale has ended");
        _;
    }

    function purchaseTokens(uint256 _numberOfTokens)
        external payable
        onlySaleNotEnd
    {
        require(msg.value == _numberOfTokens * tokenPrice, "The value sent doesn't match the number of tokens being purchased");
        require(_numberOfTokens > 0, "Number of tokens must be greater than zero");
        require(remainingTokens >= _numberOfTokens, "Insufficient tokens available for sale");
        require(duration > 0, "Duration must be greater than zero");

        vestedAmount[msg.sender] = vestedAmount[msg.sender].add(_numberOfTokens);

        vestingContract.createVestingSchedule(
            msg.sender,
            _numberOfTokens,
            duration, // Number of months for the release period
            0 // Start time of the vesting schedule
        );

        remainingTokens = remainingTokens.sub(_numberOfTokens);

        emit TokensPurchased(msg.sender, _numberOfTokens);
    }

    function seeClaimableTokens() public view returns (uint256 releasableTokens) {
        releasableTokens = vestingContract.getReleasableTokens(address(this), msg.sender);
    }

    function claimVestedTokens() external onlySaleEnd {
        uint256 userVestedAmount = vestedAmount[msg.sender];
        require(userVestedAmount > 0, "No tokens available to claim");
        uint256 releasableTokens = vestingContract.getReleasableTokens(address(this), msg.sender);
        require(releasableTokens > 0, "No tokens available for release");

        vestingContract.releaseTokens(address(this), msg.sender);

        emit TokensClaimed(msg.sender, releasableTokens);
    }

    function setSaleEnd() external onlyOwner {
        isSaleEnd = !isSaleEnd;
    }
}
