// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Adeno} from "adenotoken/Adeno.sol";
import {Vesting} from "../src/Vesting.sol";
import {PreSale} from "../src/PreSale.sol";
import {console} from "forge-std/console.sol";
import "openzeppelin/utils/math/SafeMath.sol";

contract PreSaleNewTest is Test {
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
    uint256 private TOKEN_PRICE = 1; // Price is measured in Eth, or can be seen as a wei to "tokenbit" ratio. i.e. a TOKEN_PRICE of 0.5 means that 0.5 wei can purchase 1 tokenbit, thus 1 wei can purchase 2 toknbits, and 1 eth can purchase 2 tokens, which can also be represented as 1 token being equal to 0.5 eth.
    uint256 private TOKEN_AMOUNT = 1000e18;
    // vesting duration = 12 months:
    uint256 private VESTING_DURATION = 12;
    uint256 private VESTING_START_TIME = 1656633599;

    function setUp() public {
        vm.warp(VESTING_START_TIME);
        adenoToken = new Adeno(2625000000e18);
        adenoToken.mint(address(this), 236250000e18);
        vesting = new Vesting(address(adenoToken));

        preSale = new PreSale(address(vesting), address(adenoToken), TOKEN_AMOUNT, TOKEN_PRICE, VESTING_DURATION);
        // sell 1000 tokens for 1 eth each

        preSale2 = new PreSale(address(vesting), address(adenoToken), TOKEN_AMOUNT, TOKEN_PRICE, VESTING_DURATION);

        address[] memory whiteListAddr = new address[](3);
        whiteListAddr[0] = address(this);
        whiteListAddr[1] = address(preSale);
        whiteListAddr[2] = address(preSale2);

        vesting.addToWhitelist(whiteListAddr);
        adenoToken.transfer(address(vesting), 1000e18);

        _vestingScheduleMonth = 12;
        _timeNow = VESTING_START_TIME;
        SECONDS_PER_MONTH = vesting.SECONDS_PER_MONTH();
        vesting.setVestingSchedulesActive(address(preSale), true);
        vesting.setVestingSchedulesActive(address(preSale2), true);
    }

    function testPurchaseTokens() public {
        uint256 amount = 10e18;

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens{value: amount}(amount);

        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 10e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);
    }

    function testPurchaseTokensInsufficientEth() public {
        uint256 amount = 10e18;

        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("The value sent doesn't match the number of tokens being purchased");
        preSale.purchaseTokens{value: amount-2}(amount);
    }

    function testPurchaseTokensInvalidAmount() public {
        hoax(_buyer);
        vm.expectRevert("Number of tokens must be greater than zero");
        preSale.purchaseTokens(0);
    }

    function testPurchaseTokenAmountGreaterThanRemaining() public {
        hoax(_buyer, TOKEN_AMOUNT+1e18);
        vm.expectRevert("Insufficient tokens available for sale");
        preSale.purchaseTokens{value: TOKEN_AMOUNT+1e18}(TOKEN_AMOUNT+1e18);
    }

    function testPurchaseTokensSaleEnded() public {
        uint256 amount = 10e18;
        preSale.setSaleEnd();
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Sale has ended");
        preSale.purchaseTokens{value: amount}(amount);
    }

    function testRemainingToken() public {
        uint256 amount = 10e18;

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens{value: amount}(amount);

        uint256 remainingTokens = preSale.remainingTokens();
        uint256 maxTokensToSell = preSale.maxTokensToSell();

        assertEq(remainingTokens, maxTokensToSell - 10e18);
    }

    function testGetReleasableTokens() public {
        uint256 amount = 12e18;

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokens{value: amount}(amount);

        // 6 month time warp:
        vm.warp(block.timestamp + (2629746*6));

        uint256 releasableTokens = vesting.getReleasableTokens(address(preSale), _buyer);
        assertEq(releasableTokens, 6e18);
    }

    function testSeeClaimableTokens() public {
        uint256 amount = 12e18;

        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.warp(_timeNow);
        preSale.purchaseTokens{value: amount}(amount);

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
        vm.assume(purchaseAmount <= 1000e18);
        vm.assume(purchaseAmount > 0.1 ether);

        uint256 amount = purchaseAmount;
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.warp(_timeNow);
        preSale.purchaseTokens{value: amount}(amount);

        uint256 _tokensPerMonth = purchaseAmount.div(_vestingScheduleMonth);

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

    function testFuzzClaimVestedTokens(uint256 purchaseAmount, uint8 collectMonth) public {
        vm.assume(purchaseAmount <= 1000e18);
        vm.assume(purchaseAmount > 0.1 ether);

        vm.assume(collectMonth <= _vestingScheduleMonth);
        vm.assume(collectMonth > 0);

        uint256 amount = purchaseAmount;
        vm.warp(_timeNow);
        hoax(_buyer, amount);
        preSale.purchaseTokens{value: amount}(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        uint256 _tokensPerMonth = purchaseAmount.div(_vestingScheduleMonth);

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
        uint256 amount = 12e18;

        vm.warp(_timeNow);
        hoax(_buyer, amount);
        preSale.purchaseTokens{value: amount}(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        uint256 t = uint256(_vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(_timeNow + t);

        preSale.claimVestedTokens();

        uint256 bal = adenoToken.balanceOf(_buyer);
        assertEq(bal, 12e18);
        vm.stopPrank();
    }

    function testClaimVestedTokensSaleOngoing() public {
        uint256 amount = 12e18;

        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.warp(_timeNow);
        preSale.purchaseTokens{value: amount}(amount);
        vm.expectRevert("Sale has not ended");
        preSale.claimVestedTokens();
    }

    function testClaimVestedTokensZeroContribution() public {
        preSale.setSaleEnd();
        vm.startPrank(_buyer);
        vm.expectRevert("No tokens available to claim");
        preSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testClaimVestedTokensZeroReleasableToken() public {
        uint256 amount = 12e18;

        vm.warp(_timeNow);
        hoax(_buyer, amount);
        preSale.purchaseTokens{value: amount}(amount);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.warp(_timeNow + SECONDS_PER_MONTH * 36);
        preSale.claimVestedTokens();
        vm.expectRevert("No tokens available for release");
        preSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testMultipleSaleWithSameVestingContract() public {
        uint256 amount = 12e18;

        vm.warp(_timeNow);
        hoax(_buyer, amount*2);
        preSale.purchaseTokens{value: amount}(amount);
        hoax(_buyer, amount*2);
        preSale2.purchaseTokens{value: amount}(amount);
        preSale.setSaleEnd();
        preSale2.setSaleEnd();

        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 12e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, VESTING_START_TIME);
        assertEq(releasedToken, 0);

        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens2, 12e18);
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
        assertEq(bal, 12e18 + 12e18);

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
        uint256 amount = 10e18;
        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.expectRevert("Sale has ended");
        preSale.purchaseTokens{value: amount}(amount);
        vm.stopPrank();
    }

    function testPrivateSaleWorkFlowInactive() public {
        uint256 amount = 10e18;
        hoax(_buyer, amount);
        preSale.purchaseTokens{value: amount}(amount);
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

    receive() external payable {
        // console.log("receive()", msg.sender, msg.value, "");
    }
}
