// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Adeno} from "adenotoken/Adeno.sol";
import {Vesting} from "../src/Vesting.sol";
import {PrivateSale} from "../src/PrivateSale.sol";
import {console} from "forge-std/console.sol";

contract PrivateSaleTest is Test {

    Adeno public adenoToken;
    Vesting public vesting;

    PrivateSale public privateSale;
    PrivateSale public privateSale2;

    address buyer = vm.addr(0x1);
    address buyer2 = vm.addr(0x2);

    uint256 private timeNow;
    uint8 vestingScheduleMonth;
    uint256 private SECONDS_PER_MONTH;
    uint256 private TOKEN_PRICE = 1e18;
    uint256 private TOKEN_AMOUNT = 1000e18;
    uint256 private VESTING_START_TIME = 1656633599;

    function setUp() public {
        timeNow = VESTING_START_TIME;
        // vm.warp(timeNow);

        adenoToken = new Adeno(2625000000e18);
        adenoToken.mint(address(this), 236250000e18);
        vesting = new Vesting(address(adenoToken));
        vesting.updateStartDate(1, VESTING_START_TIME);
        privateSale = new PrivateSale(address(vesting), TOKEN_AMOUNT);
        // sell 1000 tokens for 1 eth each

        privateSale2 = new PrivateSale(address(vesting), TOKEN_AMOUNT);
        // half month

        address[] memory whiteListAddr = new address[](3);
        whiteListAddr[0] = address(this);
        whiteListAddr[1] = address(privateSale);
        whiteListAddr[2] = address(privateSale2);

        vesting.addToWhitelist(whiteListAddr);
        adenoToken.transfer(address(vesting), 1000e18);

        vestingScheduleMonth = 36;
        SECONDS_PER_MONTH = vesting.SECONDS_PER_MONTH();
        vesting.setVestingSchedulesActive(address(privateSale), true);
        vesting.setVestingSchedulesActive(address(privateSale2), true);
    }

    function testPurchaseTokensFor() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(privateSale), buyer);
        assertEq(totalTokens, 10e18);
        assertEq(releasePeriod, vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            vesting.vestingSchedules(address(privateSale), buyer2);
        assertEq(totalTokens2, 20e18);
        assertEq(releasePeriod2, vestingScheduleMonth);
        assertEq(startTime2, 1);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);
    }

    function testPurchaseTokensForNotOwner() public {
        vm.startPrank(buyer);
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        vm.stopPrank();
    }

    function testPurchaseTokensInvalidArrayLength() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10e18;
        amounts[1] = 20e18;
        amounts[2] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        vm.expectRevert("Recipients and amounts do not match");
        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
    }

    function testPurchaseTokensInvalidAmounts() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        vm.expectRevert("Amount must be greater than zero");
        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
    }

    function testPurchaseTokensAmountsGreaterThanRemaining() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = TOKEN_AMOUNT;
        amounts[1] = 1e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        vm.expectRevert("Insufficient tokens available for sale");
        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
    }

    function testPurchaseTokensForSaleEnded() public {
        privateSale.setSaleEnd();
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        vm.expectRevert("Sale has ended");
        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
    }

    function testRemainingToken() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        uint256 remainingTokens = privateSale.remainingTokens();
        uint256 maxTokensToSell = privateSale.maxTokensToSell();

        assertEq(remainingTokens, maxTokensToSell - 30e18);
    }

    function testGetReleasableTokens() public {
        // hoax(buyer, 100e18);
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        // 1 May 2023 == 10 month
        vm.warp(1682963257);

        uint256 releasableTokensMonth = vesting.getReleasableTokens(address(privateSale), buyer);
        assertEq(releasableTokensMonth, 10e18);
    }

    function testSeeClaimableTokens() public {
        deal(buyer, 100e18);
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;
        vm.warp(timeNow);
        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        vm.startPrank(buyer);

        uint256 releasableTokensMonth0 = privateSale.seeClaimableTokens();
        assertEq(releasableTokensMonth0, 0);

        for (uint256 i = 1; i <= vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(timeNow + t);

            uint256 releasableTokensMonth = privateSale.seeClaimableTokens();
            assertEq(releasableTokensMonth, i * 10 ** 18);
        }
        vm.stopPrank();
    }

    // function testFiveYearGetReleasableTokens() public {

    //     address[] memory recipients = new address[](1);
    //     recipients[0] = address(buyer);

    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = 36;

    //     uint8[] memory durations = new uint8[](1);
    //     durations[0] = 36;

    //     uint256[] memory startTimes = new uint256[](1);
    //     startTimes[0] = 1;

    //     uint256[] memory lockDurations = new uint256[](1);
    //     lockDurations[0] = 24;

    //     privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

    //     uint256 _tokensPerMonth = amounts[0] / (durations[0] - lockDurations[0]);

    //     for (uint256 i = 1; i <= durations[0]; i++) {
    //         uint256 t = i * SECONDS_PER_MONTH;

    //         vm.warp(timeNow + t);

    //         (uint256 totalTokens,,, uint256 releasedToken, uint256 lockDuration) =
    //             vesting.vestingSchedules(address(privateSale), buyer);

    //         uint256 releasableTokensMonth = vesting.getReleasableTokens(address(privateSale), buyer);

    //         if (i == 60) {
    //             assertEq(releasableTokensMonth, totalTokens - releasedToken);
    //         } else if(i > lockDuration) {
    //             uint256 _releasableTokensMonth = _tokensPerMonth * (i - lockDuration);
    //             assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
    //         } else {
    //             assertEq(releasableTokensMonth, 0);
    //         }
    //     }
    // }

    function testFuzzGetReleasableTokens(uint256 purchaseAmount) public {
        vm.assume(purchaseAmount <= 1000e18);
        vm.assume(purchaseAmount > 0.1 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = purchaseAmount;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        uint256 _tokensPerMonth = purchaseAmount / vestingScheduleMonth;

        for (uint256 i = 1; i <= vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken,) =
                vesting.vestingSchedules(address(privateSale), buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(privateSale), buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth * i;
            if (i == vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens - releasedToken);
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
            }
        }
    }

    function testFuzzClaimVestedToken(uint256 purchaseAmount, uint8 collectMonth) public {
        vm.assume(purchaseAmount <= 1000e18);
        vm.assume(purchaseAmount > 0.1 ether);

        vm.assume(collectMonth <= vestingScheduleMonth);
        vm.assume(collectMonth > 0);

        deal(buyer, 1000e18);

        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = purchaseAmount;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        privateSale.setSaleEnd();
        vm.startPrank(buyer);

        uint256 _tokensPerMonth = purchaseAmount / vestingScheduleMonth;

        for (uint256 i = 1; i <= vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken,) =
                vesting.vestingSchedules(address(privateSale), buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(privateSale), buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth * i;
            if (i == vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens - releasedToken);
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
            }

            if (i == collectMonth) {
                privateSale.claimVestedTokens();
            }
        }
        vm.stopPrank();
    }

    function testFuzzClaimVestedToken2(uint256 purchaseAmount, uint8 collectMonth, uint256 collectMonth2) public {
        vm.assume(purchaseAmount <= 1000e18);
        vm.assume(purchaseAmount > 0.1 ether);

        vm.assume(collectMonth <= vestingScheduleMonth);
        vm.assume(collectMonth > 0);

        collectMonth2 = bound(collectMonth2, collectMonth, vestingScheduleMonth);

        deal(buyer, 1000e18);

        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = purchaseAmount;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        privateSale.setSaleEnd();
        vm.startPrank(buyer);

        uint256 _tokensPerMonth = purchaseAmount / vestingScheduleMonth;

        for (uint256 i = 1; i <= vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken,) =
                vesting.vestingSchedules(address(privateSale), buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(privateSale), buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth * i;
            if (i == vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens - releasedToken);
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
            }

            if (i == collectMonth || i == collectMonth2) {
                privateSale.claimVestedTokens();
            }
        }
        vm.stopPrank();
    }

    function testClaimVestedTokens() public {
        deal(buyer, 100e18);
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;
        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        privateSale.setSaleEnd();

        uint256 t = uint256(vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(timeNow + t);

        vm.startPrank(buyer);
        privateSale.claimVestedTokens();

        uint256 bal = adenoToken.balanceOf(buyer);
        assertEq(bal, 36e18);
        vm.stopPrank();
    }

    function testClaimVestedTokensForOthers() public {
        deal(buyer, 100e18);
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        
        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        uint256 t = uint256(vestingScheduleMonth) * SECONDS_PER_MONTH;

        vm.warp(timeNow + t);
        vesting.releaseTokens(address(privateSale), buyer);

        uint256 bal = adenoToken.balanceOf(buyer);
        assertEq(bal, 36e18);
    }

    function testClaimVestedTokensSaleOngoing() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        hoax(buyer,100e18);
        vm.expectRevert("Sale has not ended");
        privateSale.claimVestedTokens();
    }

    function testClaimVestedTokensZeroContribution() public {
        privateSale.setSaleEnd();
        vm.startPrank(buyer);
        vm.expectRevert("No tokens available to claim");
        privateSale.claimVestedTokens();
        vm.stopPrank();
    }

    function testClaimVestedTokensZeroReleasableToken() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        vm.warp(timeNow + SECONDS_PER_MONTH * 36);

        privateSale.setSaleEnd();
        deal(buyer, 100e18);
        vm.startPrank(buyer);
        privateSale.claimVestedTokens();
        vm.expectRevert("No tokens available for release");
        privateSale.claimVestedTokens();

        vm.stopPrank();
    }

    function testMultipleSaleWithSameVestingContract() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(buyer);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 36e18;

        uint8[] memory durations = new uint8[](1);
        durations[0] = 36;

        uint256[] memory startTimes = new uint256[](1);
        startTimes[0] = 1;

        uint256[] memory lockDurations = new uint256[](1);
        lockDurations[0] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(privateSale), buyer);
        assertEq(totalTokens, 36e18);
        assertEq(releasePeriod, vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        privateSale2.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            vesting.vestingSchedules(address(privateSale2), buyer);
        assertEq(totalTokens2, 36e18);
        assertEq(releasePeriod2, vestingScheduleMonth);
        assertEq(startTime2, 1);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);

        uint256 t = uint256(vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(timeNow + t + 100);

        privateSale.setSaleEnd();
        privateSale2.setSaleEnd();
        vm.startPrank(buyer);
        privateSale.claimVestedTokens();
        privateSale2.claimVestedTokens();

        uint256 bal = adenoToken.balanceOf(buyer);
        assertEq(bal, 36e18 + 36e18);

        vm.stopPrank();
    }

    function testSetSaleEnd() public {
        assertEq(privateSale.isSaleEnd(), false);
        privateSale.setSaleEnd();
        assertEq(privateSale.isSaleEnd(), true);
    }

    function testSetSaleEndNotOwner() public {
        vm.startPrank(buyer);
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        privateSale.setSaleEnd();
        vm.stopPrank();
    }

    function testPurchaseTokensForOnlySaleNotEnd() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10e18;
        amounts[1] = 20e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);
    }

    function testPrivateSaleWorkFlowInactive() public {
        vesting.setVestingSchedulesActive(address(privateSale), false);

        address[] memory recipients = new address[](2);
        recipients[0] = address(buyer);
        recipients[1] = address(buyer2);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 36e18;
        amounts[1] = 100e18;

        uint8[] memory durations = new uint8[](2);
        durations[0] = 36;
        durations[1] = 36;

        uint256[] memory startTimes = new uint256[](2);
        startTimes[0] = 1;
        startTimes[1] = 1;

        uint256[] memory lockDurations = new uint256[](2);
        lockDurations[0] = 0;
        lockDurations[1] = 0;

        privateSale.purchaseTokensFor(recipients, amounts, durations, startTimes, lockDurations);

        privateSale.setSaleEnd();
        vm.startPrank(buyer);
        vm.expectRevert("Vesting schedule not active");
        privateSale.claimVestedTokens();
        vm.stopPrank();
    }

    receive() external payable {
        // console.log("receive()", msg.sender, msg.value, "");
    }
}
