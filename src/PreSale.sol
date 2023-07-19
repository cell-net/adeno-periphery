// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Vesting.sol";
import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/access/Ownable.sol";
import "openzeppelin/security/ReentrancyGuard.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "openzeppelin/security/Pausable.sol";

contract PreSale is Ownable, Pausable, ReentrancyGuard {

    Vesting public vestingContract;
    IERC20 public erc20Token;
    AggregatorV3Interface public aggregator;
    bool public isSaleEnd;
    uint256 public tokenPrice;
    uint256 public maxTokensToSell;
    uint256 public remainingTokens;
    uint256 public duration;
    uint256 public vestingStartDate;
    uint256 public usdPrice;
    mapping(address => uint256) public usdcAmount;
    mapping(address => uint256) public ethAmount;

    mapping(address => uint256) public vestedAmount;
    mapping(address => bool) public whitelist;

    event TokensPurchased(address buyer, uint256 amount);
    event TokensClaimed(address beneficiary, uint256 amount);

    constructor(address _vestingContract, address _erc20TokenContract, address _aggregatorContract, uint256 _maxTokensToSell, uint256 _tokenPrice, uint256 _usdPrice, uint256 _vestingDuration, uint256 _vestingStartDate) {
        vestingContract = Vesting(_vestingContract);
        tokenPrice = _tokenPrice; // This is the price of Adeno in 'token bits'
        duration = _vestingDuration;
        vestingStartDate = _vestingStartDate;
        erc20Token = IERC20(_erc20TokenContract);
        aggregator = AggregatorV3Interface(_aggregatorContract);
        maxTokensToSell = _maxTokensToSell;
        remainingTokens = _maxTokensToSell;
        usdPrice = _usdPrice;
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
        external
        onlySaleNotEnd
        onlyWhitelisted
    {
        uint256 _tokensToBuy = _numberOfTokens * 10**18;
        require(_numberOfTokens > 0, "Number of tokens must be greater than zero");
        require(remainingTokens >= _tokensToBuy, "Insufficient tokens available for sale");
        require(duration > 0, "Duration must be greater than zero");

        uint256 usdcValue = _numberOfTokens * tokenPrice;
        uint256 allowance = erc20Token.allowance(msg.sender, address(this));
        require(allowance >= usdcValue, "Check the token allowance");
        bool success = erc20Token.transferFrom(msg.sender, address(this), usdcValue);
        require(success, "Transaction was not successful");
        usdcAmount[msg.sender] = usdcAmount[msg.sender] + usdcValue;

        vestedAmount[msg.sender] = vestedAmount[msg.sender] + _numberOfTokens;

        vestingContract.createVestingSchedule(
            msg.sender,
            _tokensToBuy,
            duration, // Number of months for the release period
            vestingStartDate // Start time of the vesting schedule
        );

        remainingTokens = remainingTokens - _tokensToBuy;

        emit TokensPurchased(msg.sender, _tokensToBuy);
    }

    function purchaseTokensWithEth(uint256 _numberOfTokens)
        external payable
        onlySaleNotEnd
        onlyWhitelisted
        nonReentrant
    {
        uint256 _tokensToBuy = _numberOfTokens * 10**18;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 ethValue = (usdPrice * _tokensToBuy) / uint256(price);
        require(msg.value >= ethValue, "Insufficient Eth for purchase");
        require(_numberOfTokens > 0, "Number of tokens must be greater than zero");
        require(remainingTokens >= _tokensToBuy, "Insufficient tokens available for sale");
        require(duration > 0, "Duration must be greater than zero");
        uint256 excess = msg.value - ethValue;
        ethAmount[msg.sender] = ethAmount[msg.sender] + msg.value;

        vestedAmount[msg.sender] = vestedAmount[msg.sender] + _tokensToBuy;

        vestingContract.createVestingSchedule(
            msg.sender,
            _tokensToBuy,
            duration, // Number of months for the release period
            vestingStartDate // Start time of the vesting schedule
        );

        remainingTokens = remainingTokens - _tokensToBuy;
        if (excess > 0) {
            require(address(this).balance >= excess, "Not enough Eth to make the transfer");
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "ETH transfer failed");
        }
        emit TokensPurchased(msg.sender, _tokensToBuy);
    }

    function changeAggregatorInterface(address _address) external onlyOwner {
        aggregator = AggregatorV3Interface(_address);
    }

    function seeVestingSchedule() external view returns (uint256, uint256, uint256, uint256) {
        return vestingContract.vestingSchedules(address(this), msg.sender);
    }

    function seeClaimableTokens() external view returns (uint256 releasableTokens) {
        releasableTokens = vestingContract.getReleasableTokens(address(this), msg.sender);
    }

    function claimVestedTokens() external onlySaleEnd {
        require(vestedAmount[msg.sender] > 0, "No tokens available to claim");
        uint256 releasableTokens = vestingContract.getReleasableTokens(address(this), msg.sender);
        require(releasableTokens > 0, "No tokens available for release");
        vestingContract.releaseTokens(address(this), msg.sender);
        emit TokensClaimed(msg.sender, releasableTokens);
    }

    function refundPurchase(address _buyer) external onlySaleNotEnd nonReentrant onlyOwner {
        (uint256 totalTokens,,, uint256 releasedTokens) = vestingContract.vestingSchedules(address(this), _buyer);
        require(totalTokens != 0, "Nothing to refund");
        require(releasedTokens == 0, "Tokens have already been claimed");
        vestingContract.removeVestingSchedule(address(this), _buyer);
        if(ethAmount[_buyer] > 0) {
            require(address(this).balance >= ethAmount[_buyer], "Not enough Eth to make the transfer");
            uint256 ethToRefund = ethAmount[_buyer];
            ethAmount[_buyer] = 0;
            (bool success, ) = payable(_buyer).call{value: ethToRefund}("");
            require(success, "ETH transfer failed");
        }
        if(usdcAmount[_buyer] > 0) {
            require(erc20Token.balanceOf(address(this)) >= usdcAmount[_buyer], "Not enough USDC to make the transfer");
            uint256 usdcToRefund = usdcAmount[_buyer];
            usdcAmount[_buyer] = 0;
            require(erc20Token.transfer(_buyer, usdcToRefund), "USDC transfer failed");
        }
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

    function withdrawUSDC() external onlySaleEnd nonReentrant onlyOwner {
        require(erc20Token.balanceOf(address(this)) > 0, "No USDC to withdraw");
        require(erc20Token.transfer(msg.sender, erc20Token.balanceOf(address(this))));
    }

    function withdrawEth() external onlySaleEnd nonReentrant onlyOwner {
        require(address(this).balance > 0, "No Eth to withdraw");
        (bool sent,) = payable(msg.sender).call{value: address(this).balance}("");
        require(sent);
    }
}
