// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Adeno} from "adenotoken/Adeno.sol";
import {Vesting} from "../src/Vesting.sol";
import {console} from "forge-std/console.sol";

contract VestingTest is Test {

    Adeno public adenoToken;

    Vesting public vesting;

    address buyer = vm.addr(0x1);
    address buyer2 = vm.addr(0x2);
    address presale1 = vm.addr(0x3);
    address presale2 = vm.addr(0x4);

    uint256 private timeNow;
    uint256 private SECONDS_PER_MONTH;

    function setUp() public {
        adenoToken = new Adeno(2625000000e18);
        adenoToken.mint(address(this), 236250000e18);
        vesting = new Vesting(address(adenoToken));
        timeNow = block.timestamp;

        adenoToken.transfer(address(vesting), 100000e18);

        address[] memory whiteListAddr = new address[](1);
        whiteListAddr[0] = address(this);

        vesting.addToWhitelist(whiteListAddr);
        vesting.updateStartDate(1, block.timestamp);

        SECONDS_PER_MONTH = vesting.SECONDS_PER_MONTH();
    }

    function testCreateVestingSchedule() public {
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);

        vesting.createVestingSchedule(buyer, 100e18, 36, 1, 0);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(this), buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, 36);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
    }

    function testCreateAndAddToVestingSchedule() public {
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);

        vesting.createVestingSchedule(buyer, 110e18, 36, 1, 0);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(this), buyer);
        assertEq(totalTokens, 110e18);
        assertEq(releasePeriod, 36);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        vesting.createVestingSchedule(buyer, 2e18, 36, 1, 0);
        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            vesting.vestingSchedules(address(this), buyer);
        assertEq(totalTokens2, 112e18);
        assertEq(releasePeriod2, 36);
        assertEq(startTime2, 1);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);

        vm.warp(timeNow + SECONDS_PER_MONTH * 2);

        // set schedule inactive
        vesting.setVestingSchedulesActive(address(this), false);
        vm.expectRevert("Vesting schedule not active");
        vesting.releaseTokens(address(this), buyer);
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);
        vesting.releaseTokens(address(this), buyer);
        uint256 buyerBal = adenoToken.balanceOf(buyer);
        assertEq(buyerBal, 6222222222222222222);
        vm.expectRevert("Vesting schedule already in use, for the beneficiary");
        vesting.createVestingSchedule(buyer, 1e18, 36, 1, 0);
    }

    function testCreateVestingScheduleNotWhitelisted() public {
        vm.startPrank(buyer);
        vm.expectRevert("Sender is not whitelisted");
        vesting.createVestingSchedule(buyer, 100e18, 36, 1, 0);
        vm.stopPrank();
    }

    function testCreateVestingScheduleZeroTotalToken() public {
        vm.expectRevert("Total tokens must be greater than zero");
        vesting.createVestingSchedule(buyer, 0, 36, 1, 0);
    }

    function testCreateVestingScheduleZeroReleasePeriod() public {
        vm.expectRevert("Release period must be greater than zero");
        vesting.createVestingSchedule(buyer, 100e18, 0, 1, 0);
    }

    function testCreateVestingScheduleWhenPaused() public {
        vesting.pause();
        bytes4 selector = bytes4(keccak256("EnforcedPause()"));
        vm.expectRevert(selector);
        vesting.createVestingSchedule(buyer, 100e18, 36, 1, 0);
    }

    function testGetReleasableTokens() public {
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);

        uint256 totalTokens = 100e18;
        uint256 totalMonths = 36;
        uint256 _tokensPerMonth = totalTokens / totalMonths;
        vesting.createVestingSchedule(buyer, totalTokens, totalMonths, 1, 0);

        uint256 releasableTokensMonth0 = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth0, 0);

        vm.warp(timeNow + SECONDS_PER_MONTH);

        uint256 releasableTokensMonth1 = vesting.getReleasableTokens(address(this), buyer);
        uint256 _releasableTokensMonth1 = _tokensPerMonth;
        assertEq(releasableTokensMonth1, _releasableTokensMonth1);

        vm.warp(timeNow + SECONDS_PER_MONTH * 2);

        uint256 releasableTokensMonth2 = vesting.getReleasableTokens(address(this), buyer);

        uint256 _releasableTokensMonth2 = _tokensPerMonth * 2;
        assertEq(releasableTokensMonth2, _releasableTokensMonth2);
    }

    function testGetNextClaimableTime() public {
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);

        uint256 totalTokens = 100e18;
        uint256 totalMonths = 36;
        uint256 _tokensPerMonth = totalTokens / totalMonths;
        vesting.createVestingSchedule(buyer, totalTokens, totalMonths, 1, 0);

        uint256 releasableTokensMonth0 = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth0, 0);

        vm.warp(timeNow + 1750);
        uint256 nextTime = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime, SECONDS_PER_MONTH - 1750);

        vm.warp(timeNow + SECONDS_PER_MONTH - 1750);
        uint256 nextTime2 = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime2, 1750);

        vm.warp(timeNow + (SECONDS_PER_MONTH * 3) - 1750);
        uint256 nextTime3 = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime3, 1750);

        vm.warp(timeNow + SECONDS_PER_MONTH);

        uint256 releasableTokensMonth1 = vesting.getReleasableTokens(address(this), buyer);
        uint256 _releasableTokensMonth1 = _tokensPerMonth;
        assertEq(releasableTokensMonth1, _releasableTokensMonth1);

        uint256 nextTime4 = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime4, 2628000);

        vm.warp(timeNow + (SECONDS_PER_MONTH * 40));

        uint256 releasableTokensMonth2 = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth2, totalTokens);

        uint256 nextTime5 = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime5, 0);
        vesting.releaseTokens(address(this), buyer);
        uint256 nextTime6 = vesting.getNextClaimableTime(address(this), buyer, 1);
        assertEq(nextTime6, 0);
        assertEq(adenoToken.balanceOf(buyer), totalTokens);
    }

    function testSetVestingSchedulesActive() public {
        bool scheduleActive = vesting.vestingSchedulesActive(address(this));
        assertEq(scheduleActive, false);
        vesting.setVestingSchedulesActive(address(this), true);

        scheduleActive = vesting.vestingSchedulesActive(address(this));
        assertEq(scheduleActive, true);
    }

    function testReleaseTokensScheduleInactive() public {
        uint256 totalTokens = 100e18;
        uint256 totalMonths = 36;
        vesting.createVestingSchedule(buyer, totalTokens, totalMonths, 1, 0);
        vm.warp(timeNow + SECONDS_PER_MONTH);
        vm.expectRevert("Vesting schedule not active");
        vesting.releaseTokens(address(this), buyer);
    }

    function testReleaseTokensFirstMonth() public {
        // set schedule active
        vesting.setVestingSchedulesActive(address(this), true);
        uint256 totalTokens = 100e18;
        uint256 totalMonths = 36;
        uint256 _tokensPerMonth = totalTokens / totalMonths;
        vesting.createVestingSchedule(buyer, totalTokens, totalMonths, 1, 0);

        vm.warp(timeNow + SECONDS_PER_MONTH);

        vm.startPrank(buyer);

        vesting.getReleasableTokens(address(this), buyer);
        address[] memory waddr = new address[](1);
        waddr[0] = buyer;

        uint256 releasableTokensMonth1Before = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth1Before, _tokensPerMonth);

        vm.expectRevert("Sender is not whitelisted");
        vesting.releaseTokens(address(this), buyer);
        vm.stopPrank();

        hoax(address(this));
        vesting.addToWhitelist(waddr);

        vm.startPrank(buyer);
        vesting.releaseTokens(address(this), buyer);
        uint256 buyerBal = adenoToken.balanceOf(buyer);
        assertEq(buyerBal, _tokensPerMonth);

        uint256 releasableTokensMonth1After = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth1After, 0);

        vm.warp(timeNow + SECONDS_PER_MONTH * 2);
        uint256 releasableTokensMonth2After = vesting.getReleasableTokens(address(this), buyer);
        assertEq(releasableTokensMonth2After, _tokensPerMonth);

        vm.stopPrank();
    }

    function testUpdatePlan() public {
        vesting.updateStartDate(1, timeNow + 100);
        uint256 startDate = vesting.startDates(1);
        assertEq(startDate, timeNow + 100);
    }

    function testAddToWhitelist() public {
        address[] memory whiteListAddr = new address[](2);
        whiteListAddr[0] = presale1;
        whiteListAddr[1] = presale2;

        vesting.addToWhitelist(whiteListAddr);

        assertEq(vesting.whitelist(presale1), true);
        assertEq(vesting.whitelist(presale2), true);
    }

    function testAddToWhitelistNotOwner() public {
        vm.startPrank(buyer);
        address[] memory whiteListAddr = new address[](2);
        whiteListAddr[0] = presale1;
        whiteListAddr[1] = presale2;
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        vesting.addToWhitelist(whiteListAddr);
        vm.stopPrank();
    }

    function testRemoveFromWhitelist() public {
        address[] memory whiteListAddr = new address[](2);
        whiteListAddr[0] = presale1;
        whiteListAddr[1] = presale2;

        vesting.addToWhitelist(whiteListAddr);

        assertEq(vesting.whitelist(presale1), true);
        assertEq(vesting.whitelist(presale2), true);

        vesting.removeFromWhitelist(whiteListAddr);

        assertEq(vesting.whitelist(presale1), false);
        assertEq(vesting.whitelist(presale2), false);
    }

    function testRemoveFromWhitelistNotOwner() public {
        vm.startPrank(buyer);
        address[] memory whiteListAddr = new address[](2);
        whiteListAddr[0] = presale1;
        whiteListAddr[1] = presale2;

        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        vesting.removeFromWhitelist(whiteListAddr);
        vm.stopPrank();
    }

    function testPause() public {
        vesting.pause();
    }

    function testUnpause() public {
        vesting.pause();
        vesting.unpause();
    }

    function testTransferOwnership() public {
        address user = vm.addr(0x6);
        vesting.transferOwnership(user);
        assertEq(vesting.owner(), user);
    }

}
