// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Vesting.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";

contract PreSale is Ownable {
    using SafeMath for uint256;

    Vesting public vestingContract;
    IERC20 public erc20Token;
    bool public isSaleEnd;
    uint256 public tokenPrice;
    uint256 public maxTokensToSell;
    uint256 public remainingTokens;
    uint256 public duration;
    uint256 public vestingStartDate;

    mapping(address => uint256) public vestedAmount;
    mapping(address => bool) public whitelist;

    event TokensPurchased(address buyer, uint256 amount);
    event TokensClaimed(address beneficiary, uint256 amount);

    constructor(address _vestingContract, address _erc20TokenContract, uint256 _maxTokensToSell, uint256 _tokenPrice, uint256 _vestingDuration, uint256 _vestingStartDate) {
        vestingContract = Vesting(_vestingContract);
        tokenPrice = _tokenPrice; // This is the price of Adeno in 'token bits'
        duration = _vestingDuration;
        vestingStartDate = _vestingStartDate;
        erc20Token = IERC20(_erc20TokenContract);

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

    modifier onlyWhitelisted() {
        require(whitelist[msg.sender], "Sender is not whitelisted");
        _;
    }

    function purchaseTokens(uint256 _numberOfTokens)
        external payable
        onlySaleNotEnd
        onlyWhitelisted
    {
        require(_numberOfTokens > 0, "Number of tokens must be greater than zero");
        require(remainingTokens >= _numberOfTokens, "Insufficient tokens available for sale");
        require(duration > 0, "Duration must be greater than zero");

        uint256 allowance = erc20Token.allowance(msg.sender, address(this));
        require(allowance >= _numberOfTokens.mul(tokenPrice), "Check the token allowance");
        bool success = erc20Token.transferFrom(msg.sender, address(this), _numberOfTokens.mul(tokenPrice));
        require(success, "Transaction was not successful");

        vestedAmount[msg.sender] = vestedAmount[msg.sender].add(_numberOfTokens);

        vestingContract.createVestingSchedule(
            msg.sender,
            _numberOfTokens.mul(10**18),
            duration, // Number of months for the release period
            vestingStartDate // Start time of the vesting schedule
        );

        remainingTokens = remainingTokens.sub(_numberOfTokens.mul(10**18));

        emit TokensPurchased(msg.sender, _numberOfTokens.mul(10**18));
    }

    function seeVestingSchedule() external view returns (uint256, uint256, uint256, uint256) {
        return vestingContract.vestingSchedules(address(this), msg.sender);
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

    function refundPurchase(address _buyer) external onlySaleNotEnd onlyOwner {
        (uint256 totalTokens,,, uint256 releasedTokens) = vestingContract.vestingSchedules(address(this), _buyer);
        require(totalTokens != 0);
        require(releasedTokens == 0);
        vestingContract.removeVestingSchedule(address(this), _buyer);
        require(erc20Token.transfer(_buyer, (totalTokens.div(10**18)).mul(tokenPrice)));
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

    function setSaleEnd() external onlyOwner {
        isSaleEnd = !isSaleEnd;
    }

    function withdrawFunds() external onlySaleEnd onlyOwner {
        require(erc20Token.transfer(msg.sender, erc20Token.balanceOf(address(this))));
    }
}
