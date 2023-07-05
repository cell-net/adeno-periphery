// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Adeno} from "adenotoken/Adeno.sol";
import {Vesting} from "../src/Vesting.sol";
import {PreSale} from "../src/PreSale.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin/utils/math/SafeMath.sol";

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract PreSaleTest is Test {
    using SafeMath for uint256;

    Adeno public adenoToken;
    Vesting public vesting;

    PreSale public preSale;
    PreSale public preSale2;

    address _buyer = vm.addr(0x1);
    address _buyer2 = vm.addr(0x2);

    uint256 private _timeNow;
    uint8 _vestingScheduleMonth;
    uint256 private SECONDS_PER_MONTH;
    uint256 private TOKEN_PRICE = 40000; // Price is measured in USDC token bits, i.e., if price is 1000000, then 1 Adeno costs 1 USDC. 40000 USDCbits = 0.04 USDC
    uint256 private TOKEN_AMOUNT = 10000e18;
    // vesting duration = 12 months:
    uint256 private VESTING_DURATION = 12;
    uint256 private VESTING_START_TIME = 1656633599;
    address usdcAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUSDC usdc = IUSDC(usdcAddress);

    function setUp() public {
        vm.warp(VESTING_START_TIME);
        adenoToken = new Adeno(2625000000e18);
        adenoToken.mint(address(this), 236250000e18);
        vesting = new Vesting(address(adenoToken));

        preSale = new PreSale(address(vesting), usdcAddress, TOKEN_AMOUNT, TOKEN_PRICE, VESTING_DURATION, VESTING_START_TIME);
        // sell 1000 tokens for 1 eth each

        preSale2 = new PreSale(address(vesting), usdcAddress, TOKEN_AMOUNT, TOKEN_PRICE, VESTING_DURATION, VESTING_START_TIME);

        address[] memory whiteListAddr = new address[](5);
        whiteListAddr[0] = address(this);
        whiteListAddr[1] = address(preSale);
        whiteListAddr[2] = address(preSale2);
        whiteListAddr[3] = _buyer;
        whiteListAddr[4] = _buyer2;

        vesting.addToWhitelist(whiteListAddr);
        preSale.addToWhitelist(whiteListAddr);
        preSale2.addToWhitelist(whiteListAddr);
        adenoToken.transfer(address(vesting), 1000e18);

        _vestingScheduleMonth = 12;
        _timeNow = VESTING_START_TIME;
        SECONDS_PER_MONTH = vesting.SECONDS_PER_MONTH();
        vesting.setVestingSchedulesActive(address(preSale), true);
        vesting.setVestingSchedulesActive(address(preSale2), true);
        // spoof .configureMinter() call with the master minter account
        vm.prank(usdc.masterMinter());
        // allow this test contract to mint USDC
        usdc.configureMinter(address(this), type(uint256).max);
        // mint $1000 USDC to the test contract (or an external user)
        usdc.mint(address(this), 1000e6);
        usdc.mint(_buyer, 1000e6);
        usdc.mint(_buyer2, 1000e6);
        uint256 balance = usdc.balanceOf(address(this));
        assertEq(balance, 1000e6);
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), 0);
    }

    function testPurchaseTokens() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);
    }

    // function testPurchaseTokensInsufficientEth() public {
    //     uint256 amount = 10e18;

    //     hoax(_buyer, TOKEN_AMOUNT);
    //     vm.expectRevert("The value sent doesn't match the number of tokens being purchased");
    //     preSale.purchaseTokens{value: amount-2}(amount);
    // }

    function testPurchaseTokensInsufficientUSDCAmount() public {
        uint256 amount = 25001;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        preSale.purchaseTokens(amount);
    }

    function testPurchaseTokensInsufficientUSDCAllowance() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), 39e5);
        assertEq(usdc.allowance(_buyer, address(preSale)), 39e5);
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Check the token allowance");
        preSale.purchaseTokens(amount);
    }

    function testPurchaseTokensInvalidAmount() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Number of tokens must be greater than zero");
        preSale.purchaseTokens(0);
    }

    function testPurchaseTokenAmountGreaterThanRemaining() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Insufficient tokens available for sale");
        preSale.purchaseTokens(TOKEN_AMOUNT+1e18);
    }

    function testPurchaseTokensSaleEnded() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        preSale.setSaleEnd();
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Sale has ended");
        preSale.purchaseTokens(amount);
    }

    function testRemainingToken() public {
        uint256 amount = 1200;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);

        uint256 remainingTokens = preSale.remainingTokens();
        uint256 maxTokensToSell = preSale.maxTokensToSell();
        assertEq(remainingTokens, maxTokensToSell - 1200e18);
    }

    function testGetReleasableTokens() public {
        uint256 amount = 1200;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);

        // 6 month time warp:
        vm.warp(block.timestamp + (2629746*6));

        uint256 releasableTokens = vesting.getReleasableTokens(address(preSale), _buyer);
        assertEq(releasableTokens, 600e18);
    }

    function testSeeClaimableTokens() public {
        uint256 amount = 12;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        deal(_buyer, amount*10**18);
        vm.startPrank(_buyer);
        vm.warp(_timeNow);
        preSale.purchaseTokens(amount);

        uint256 releasableTokensMonth0 = preSale.seeClaimableTokens();
        assertEq(releasableTokensMonth0, 0);

        for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(_timeNow + t);

            uint256 releasableTokensMonth = preSale.seeClaimableTokens();
            assertEq(releasableTokensMonth, i * 10 ** 18);
        }
        vm.stopPrank();
    }

    function testFuzzGetReleasableTokens(uint256 purchaseAmount) public {
        vm.assume(purchaseAmount <= 1000);
        vm.assume(purchaseAmount > 1);
        vm.assume(purchaseAmount % 12 == 0);

        uint256 amount = purchaseAmount;
        deal(_buyer, TOKEN_AMOUNT);
        vm.startPrank(_buyer);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        vm.warp(_timeNow);
        preSale.purchaseTokens(amount);

        uint256 _tokensPerMonth = (purchaseAmount.div(_vestingScheduleMonth)) * 10 ** 18;

        for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(_timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken) =
                vesting.vestingSchedules(address(preSale), _buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(preSale), _buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth.mul(i);
            if (i == _vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens.sub(releasedToken));
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth.sub(releasedToken));
            }
        }
    }

    function testFuzzClaimVestedTokens(uint256 purchaseAmount) public {
        vm.assume(purchaseAmount <= 1000);
        vm.assume(purchaseAmount > 1);
        vm.assume(purchaseAmount % 12 == 0);

        uint256 collectMonth = 5;

        uint256 amount = purchaseAmount;
        hoax(_buyer, amount);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, amount);
        preSale.purchaseTokens(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        uint256 _tokensPerMonth = (purchaseAmount.div(_vestingScheduleMonth)) * 10 ** 18;

        for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(_timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken) =
                vesting.vestingSchedules(address(preSale), _buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(preSale), _buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth.mul(i);
            if (i == _vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens.sub(releasedToken));
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth.sub(releasedToken));
            }

            if (i == collectMonth) {
                preSale.claimVestedTokens();
                assertEq(adenoToken.balanceOf(_buyer), releasableTokensMonth);
            }
        }
        vm.stopPrank();
    }

    function testClaimVestedTokens() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        uint256 t = uint256(_vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(_timeNow + t);

        preSale.claimVestedTokens();

        uint256 bal = adenoToken.balanceOf(_buyer);
        assertEq(bal, 100e18);
        vm.stopPrank();
    }

    function testClaimVestedTokensSaleOngoing() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        preSale.purchaseTokens(amount);
        vm.warp(_timeNow);
        vm.expectRevert("Sale has not ended");
        preSale.claimVestedTokens();
    }

    function testClaimVestedTokensZeroVested() public {
        preSale.setSaleEnd();
        vm.startPrank(_buyer);
        vm.expectRevert("No tokens available to claim");
        preSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testClaimVestedTokensZeroReleasableToken() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        vm.warp(_timeNow + SECONDS_PER_MONTH * 36);
        preSale.claimVestedTokens();
        // Try to claim a second time:
        vm.expectRevert("No tokens available for release");
        preSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testMultipleSaleWithSameVestingContract() public {
        uint256 amount = 100;

        vm.warp(_timeNow);
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale2), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale2)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale2.purchaseTokens(amount);
        preSale.setSaleEnd();
        preSale2.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);

        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens2, 100e18);
        assertEq(releasePeriod2, _vestingScheduleMonth);
        assertEq(startTime2, VESTING_START_TIME);
        assertEq(releasedToken2, 0);

        uint256 t = uint256(_vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(_timeNow + t + 100);

        deal(_buyer, amount*2);
        vm.startPrank(_buyer);
        preSale.claimVestedTokens();
        preSale2.claimVestedTokens();

        uint256 bal = adenoToken.balanceOf(_buyer);
        assertEq(bal, 200e18);

        vm.stopPrank();
    }

    function testSetSaleEnd() public {
        assertEq(preSale.isSaleEnd(), false);
        preSale.setSaleEnd();
        assertEq(preSale.isSaleEnd(), true);
    }

    function testNonOwnerSetSaleEnd() public {
        vm.startPrank(_buyer);
        vm.expectRevert("Ownable: caller is not the owner");
        preSale.setSaleEnd();
        vm.stopPrank();
    }

    function testPurchaseTokensAfterSaleEnd() public {
        preSale.setSaleEnd();
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.expectRevert("Sale has ended");
        preSale.purchaseTokens(amount);
        vm.stopPrank();
    }

    function testPreSaleWorkFlowInactive() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, amount);
        preSale.purchaseTokens(amount);
        preSale.setSaleEnd();
        vesting.setVestingSchedulesActive(address(preSale), false);
        uint256 t = uint256(_vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(_timeNow + t + 100);
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.expectRevert("Vesting schedule not active");
        preSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testPreSaleSeeVestingSchedule() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);
    }

    function testWithdrawFunds() public {
        uint256 amount = 200;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 200e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);
        preSale.setSaleEnd();
        vm.expectRevert("Ownable: caller is not the owner");
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.withdrawFunds();
        preSale.withdrawFunds();
        uint256 bal = usdc.balanceOf(address(this));
        assertEq(bal, 1000e6 + (amount*TOKEN_PRICE));
    }

    function testRefundPurchase() public {
        uint256 amount = 200;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_PRICE);
        uint256 bal = usdc.balanceOf(address(_buyer));
        assertEq(bal, 1000e6);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens(amount);
        uint256 bal2 = usdc.balanceOf(address(_buyer));
        assertEq(bal2, 1000e6 - amount*TOKEN_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 200e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);
        preSale.refundPurchase(_buyer);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens2, 0);
        assertEq(releasePeriod2, 0);
        assertEq(startTime2, 0);
        assertEq(releasedToken2, 0);
        uint256 bal3 = usdc.balanceOf(address(_buyer));
        assertEq(bal3, 1000e6);
    }

    receive() external payable {
        // console.log("receive()", msg.sender, msg.value, "");
    }
}
