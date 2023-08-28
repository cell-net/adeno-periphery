// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Adeno} from "adenotoken/Adeno.sol";
import {Vesting} from "../src/Vesting.sol";
import {PreSale} from "../src/PreSale.sol";
import {FakeUSDC} from "test/FakeUSDC.sol";
import {console} from "forge-std/console.sol";
import {ERC20Permit} from "openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {Nonces} from "openzeppelin/utils/Nonces.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(address minter, uint256 minterAllowedAmount) external;
    function masterMinter() external view returns (address);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function nonces(address owner) external view returns (uint256);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function owner() external view returns (address);
}

contract PreSaleTest is Test {

    bytes32 private constant _PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    Adeno public adenoToken;
    Vesting public vesting;

    PreSale public preSale;
    PreSale public preSale2;

    address _buyer = vm.addr(0x1);
    address _buyer2 = vm.addr(0x2);
    address _treasury = vm.addr(0x3);

    uint256 private _timeNow;
    uint8 _vestingScheduleMonth;
    uint256 private SECONDS_PER_MONTH;
    uint256 private TOKEN_USDC_PRICE = 40000; // Price is measured in USDC token bits, i.e., if price is 1000000, then 1 Adeno costs 1 USDC. 40000 USDCbits = 0.04 USDC
    uint256 private TOKEN_USD_ETH_PRICE = 4000000; // This is equivalent to $0.04.
    uint256 private TOKEN_AMOUNT = 10_000_000_000_000_000e18;
    // vesting duration = 12 months:
    uint256 private VESTING_DURATION = 12;
    uint256 private VESTING_START_TIME = 1656633599;
    address chainlinkAddress = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    address usdcAddress = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address fakeUsdcAddressSepolia = address(0x721dD8535cBe26FFFc5EE45305ff729d285a937B);
    IUSDC usdc = IUSDC(usdcAddress);
    // IUSDC usdc = IUSDC(fakeUsdcAddressSepolia);
    // FakeUSDC usdc = FakeUSDC(fakeUsdcAddressSepolia);
    // FakeUSDC usdc = new FakeUSDC(100_000_000_000_000e6);
    AggregatorV3Interface private aggregator = AggregatorV3Interface(chainlinkAddress);
    bytes32 domainSeparator = 0x06c37168a7db5138defc7866392bb87a741f9b3d104deb5094588ce041cae335;
    uint256 public maxInt = 2**256 - 1;

    // Mainnet fork test setup
    function setUp() public {
        vm.warp(VESTING_START_TIME);
        adenoToken = new Adeno(2_625_000_000_000_000_000e18);
        adenoToken.mint(address(this), 236_250_000_000_000_000e18);
        vesting = new Vesting(address(adenoToken));
        vesting.updateStartDate(1, VESTING_START_TIME);
        vesting.updateStartDate(3, VESTING_START_TIME);

        preSale = new PreSale(address(vesting), usdcAddress, chainlinkAddress, TOKEN_AMOUNT, TOKEN_USDC_PRICE, TOKEN_USD_ETH_PRICE, VESTING_DURATION, 1, 0, _treasury);

        preSale2 = new PreSale(address(vesting), usdcAddress, chainlinkAddress, TOKEN_AMOUNT, TOKEN_USDC_PRICE, TOKEN_USD_ETH_PRICE, VESTING_DURATION, 1, 0, _treasury);

        address[] memory whiteListAddr = new address[](5);
        whiteListAddr[0] = address(this);
        whiteListAddr[1] = address(preSale);
        whiteListAddr[2] = address(preSale2);
        whiteListAddr[3] = _buyer;
        whiteListAddr[4] = _buyer2;

        vesting.addToWhitelist(whiteListAddr);
        preSale.addToWhitelist(whiteListAddr);
        preSale2.addToWhitelist(whiteListAddr);
        adenoToken.transfer(address(vesting), 100_000_000_000_000_000e18);

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
        usdc.mint(_buyer, 1000e6);
        usdc.mint(_buyer2, 1000e6);
        uint256 balance = usdc.balanceOf(_buyer);
        assertEq(balance, 1000e6);
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), 0);
    }

    function testPurchaseTokensWithUSDC() public {
        uint256 amount = 100;
        hoax(_buyer, TOKEN_AMOUNT);
        usdc.approve(address(preSale), amount*TOKEN_USDC_PRICE);
        assertEq(usdc.allowance(_buyer, address(preSale)), amount*TOKEN_USDC_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithUSDC(amount);
        vesting.updateStartDate(1, VESTING_START_TIME+100000);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
        assertEq(vesting.startDates(1), VESTING_START_TIME+100000);
    }

    function testPermitAndPurchaseTokensWithUSDC() public {
        uint256 amount = 100;
        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        
        vesting.updateStartDate(1, VESTING_START_TIME+100000);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
        assertEq(vesting.startDates(1), VESTING_START_TIME+100000);
    }

    function testReceivedFromMultipleBuyersUSDC() public {
        deal(_buyer, TOKEN_AMOUNT);
        uint256 amount = 2000;


        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer), maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

        deal(_buyer2, TOKEN_AMOUNT);

        uint256 amount2 = 5000;

        uint256 usdcValue2 = amount2 * preSale.tokenPrice();
        bytes32 structHash2 = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer2, address(preSale), usdcValue2, usdc.nonces(_buyer2), maxInt));
        bytes32 messageHash2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash2
            )
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(0x2, messageHash2);

        hoax(_buyer2, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount2, v2, r2, s2);

        uint256 bal = usdc.balanceOf(address(preSale));
        assertEq(bal, 2.8e8);
    }

    function testPurchaseTokensInsufficientUSDCAmount() public {
        deal(_buyer, TOKEN_AMOUNT);

        uint256 amount = 1e6;
        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
    }

    function testPurchaseTokensWithEth() public {
        uint256 amount = 10_000_000;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 weiAmount = (TOKEN_USD_ETH_PRICE * (amount * 10**18)) / uint256(price);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithEth{value: weiAmount}(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 10_000_000e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
    }

    function testPurchaseTokensWithInsufficientEth() public {
        uint256 amount = 10_000_000;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 weiAmount = (TOKEN_USD_ETH_PRICE * (amount * 10**18)) / uint256(price);
        vm.expectRevert("Insufficient Eth for purchase");
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithEth{value: weiAmount-1}(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 0);
        assertEq(releasePeriod, 0);
        assertEq(startTime, 0);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
    }

    function testPurchaseTokensWithExtraEth() public {
        uint256 amount = 10_000_000;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 weiAmount = (TOKEN_USD_ETH_PRICE * (amount * 10**18)) / uint256(price);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithEth{value: weiAmount+1000}(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 10_000_000e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
        assertEq(_buyer.balance, TOKEN_AMOUNT - weiAmount);
    }

    function testPurchaseTokensInvalidAmount() public {
        deal(_buyer, TOKEN_AMOUNT);
        uint256 amount = 2000;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        vm.expectRevert("Number of tokens must be greater than zero");
        preSale.permitAndPurchaseTokensWithUSDC(0, v, r, s);
    }

    function testPurchaseTokenAmountGreaterThanRemaining() public {
        deal(_buyer, TOKEN_AMOUNT);
        uint256 amount = TOKEN_AMOUNT;
        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        vm.expectRevert("Insufficient tokens available for sale");
        preSale.permitAndPurchaseTokensWithUSDC(TOKEN_AMOUNT+1e18, v, r, s);
    }

    function testPurchaseTokensSaleEnded() public {
        deal(_buyer, TOKEN_AMOUNT);
        uint256 amount = 2000;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        preSale.setSaleEnd();
        hoax(_buyer, TOKEN_AMOUNT);
        vm.expectRevert("Sale is not running");
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
    }

    function testRemainingToken() public {
        uint256 amount = 1200;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

        uint256 remainingTokens = preSale.remainingTokens();
        uint256 maxTokensToSell = preSale.maxTokensToSell();
        assertEq(remainingTokens, maxTokensToSell - 1200e18);
    }

    function testTransferRemaining() public {
        deal(_buyer, TOKEN_AMOUNT);
        uint256 amount = 1200;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        uint256 remainingTokens = preSale.remainingTokens();
        uint256 maxTokensToSell = preSale.maxTokensToSell();
        assertEq(remainingTokens, maxTokensToSell - 1200e18);
        preSale.setSaleEnd();
        preSale.transferRemaining();
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _treasury);
        assertEq(totalTokens, remainingTokens);
        assertEq(releasePeriod, 1);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
    }

    function testGetReleasableTokens() public {
        uint256 amount = 1200;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

        // 6 month time warp:
        vm.warp(block.timestamp + (2629746*6));

        uint256 releasableTokens = vesting.getReleasableTokens(address(preSale), _buyer);
        assertEq(releasableTokens, 600e18);
    }

    function testSeeClaimableTokens() public {
        uint256 amount = 12;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        deal(_buyer, amount*10**18);
        vm.startPrank(_buyer);
        vm.warp(_timeNow);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

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

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        vm.warp(_timeNow);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

        uint256 _tokensPerMonth = (purchaseAmount / _vestingScheduleMonth) * 10 ** 18;

        for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(_timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken,) =
                vesting.vestingSchedules(address(preSale), _buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(preSale), _buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth * i;
            if (i == _vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens - releasedToken);
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
            }
        }
    }

    function testFuzzClaimVestedTokens(uint256 purchaseAmount) public {
        vm.assume(purchaseAmount <= 1000);
        vm.assume(purchaseAmount > 1);
        vm.assume(purchaseAmount % 12 == 0);

        uint256 collectMonth = 5;

        uint256 amount = purchaseAmount;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, amount);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        preSale.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        uint256 _tokensPerMonth = (purchaseAmount / _vestingScheduleMonth) * 10 ** 18;

        for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
            uint256 t = i * SECONDS_PER_MONTH;

            vm.warp(_timeNow + t);

            (uint256 totalTokens,,, uint256 releasedToken,) =
                vesting.vestingSchedules(address(preSale), _buyer);

            uint256 releasableTokensMonth = vesting.getReleasableTokens(address(preSale), _buyer);

            uint256 _releasableTokensMonth = _tokensPerMonth * i;
            if (i == _vestingScheduleMonth) {
                assertEq(releasableTokensMonth, totalTokens - releasedToken);
            } else {
                assertEq(releasableTokensMonth, _releasableTokensMonth - releasedToken);
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

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
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

    // function testClaimingWithLockDurations() public {
    //     vesting.updateStartDate(1, VESTING_START_TIME);

    //     PreSale preSale3 = new PreSale(address(vesting), usdcAddress, chainlinkAddress, TOKEN_AMOUNT, TOKEN_USDC_PRICE, TOKEN_USD_ETH_PRICE, VESTING_DURATION, 3, 7, _treasury);

    //     address[] memory whiteListAddr = new address[](4);
    //     whiteListAddr[0] = address(this);
    //     whiteListAddr[1] = address(preSale3);
    //     whiteListAddr[2] = _buyer;
    //     whiteListAddr[3] = _buyer2;

    //     vesting.addToWhitelist(whiteListAddr);
    //     preSale3.addToWhitelist(whiteListAddr);
    //     vesting.setVestingSchedulesActive(address(preSale3), true);

    //     uint256 amount = 100;

    //     uint256 usdcValue = amount * preSale3.tokenPrice();
    //     bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale3), usdcValue, usdc.nonces(_buyer) , maxInt));
    //     bytes32 messageHash = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             domainSeparator,
    //             structHash
    //         )
    //     );

    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

    //     hoax(_buyer, TOKEN_AMOUNT);
    //     preSale3.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
    //     preSale3.setSaleEnd();
    //     deal(_buyer, amount);
    //     vm.startPrank(_buyer);

    //     uint256 claimableTokens;
    //     uint256 nextClaimableTime;

    //     claimableTokens = preSale3.seeClaimableTokens();
    //     nextClaimableTime = vesting.getNextClaimableTime(address(preSale3), _buyer, 3);
    //     assertEq(claimableTokens, 0);
    //     assertEq(nextClaimableTime, (VESTING_START_TIME + (7*SECONDS_PER_MONTH) - _timeNow));

    //     for (uint256 i = 1; i <= _vestingScheduleMonth; i++) {
    //         vm.warp(_timeNow + ((i * SECONDS_PER_MONTH + 100)));
    //         claimableTokens = preSale3.seeClaimableTokens();
    //         nextClaimableTime = vesting.getNextClaimableTime(address(preSale3), _buyer, 3);
    //         if(i <= 6) {
    //             assertEq(claimableTokens, 0);
    //             assertEq(nextClaimableTime, (VESTING_START_TIME + (7*SECONDS_PER_MONTH) - (i*SECONDS_PER_MONTH) - _timeNow - 100));
    //         } else if(i == 7) {
    //             assertEq(claimableTokens, 0);
    //             assertEq(nextClaimableTime, (VESTING_START_TIME + SECONDS_PER_MONTH) - _timeNow - 100);
    //         } else {
    //             assertEq(claimableTokens, ((i-7)*20e18));
    //             assertEq(nextClaimableTime, SECONDS_PER_MONTH - 100);
    //         }
    //     }
    //     preSale3.claimVestedTokens();

    //     uint256 bal = adenoToken.balanceOf(_buyer);
    //     assertEq(bal, 100e18);
    //     vm.stopPrank();
    // }

    function testClaimVestedTokensSaleOngoing() public {
        uint256 amount = 100;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        deal(_buyer, amount);
        vm.startPrank(_buyer);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
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

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
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

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        vm.warp(_timeNow);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);

        bytes32 structHash2 = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale2), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash2
            )
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(0x1, messageHash2);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale2.permitAndPurchaseTokensWithUSDC(amount, v2, r2, s2);
        preSale.setSaleEnd();
        preSale2.setSaleEnd();
        deal(_buyer, amount);
        vm.startPrank(_buyer);

        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens2, 100e18);
        assertEq(releasePeriod2, _vestingScheduleMonth);
        assertEq(startTime2, 1);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);

        uint256 t = uint256(_vestingScheduleMonth) * SECONDS_PER_MONTH;
        vm.warp(_timeNow + t + 100);

        deal(_buyer, 200);
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
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        preSale.setSaleEnd();
        vm.stopPrank();
    }

    function testPurchaseTokensAfterSaleEnd() public {
        preSale.setSaleEnd();
        uint256 amount = 100;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        deal(_buyer, amount);
        vm.startPrank(_buyer);
        vm.expectRevert("Sale is not running");
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        vm.stopPrank();
    }

    function testPreSaleWorkFlowInactive() public {
        uint256 amount = 100;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, amount);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
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

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 100e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
    }

    function testWithdrawUSDC() public {
        uint256 amount = 200;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 200e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
        preSale.setSaleEnd();
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.withdrawUSDC();
        preSale.withdrawUSDC();
        uint256 bal = usdc.balanceOf(address(this));
        assertEq(bal, 200*TOKEN_USDC_PRICE);
    }

    function testWithdrawEth() public {
        uint256 initialAdminBalance = address(this).balance;
        uint256 amount = 10_000_000;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 weiAmount = (TOKEN_USD_ETH_PRICE * (amount * 10**18)) / uint256(price);
        assertEq(address(preSale).balance, 0);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithEth{value: weiAmount}(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 10_000_000e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);
        assertEq(address(preSale).balance, weiAmount);
        assertEq(_buyer.balance, TOKEN_AMOUNT - weiAmount);

        preSale.setSaleEnd();
        bytes4 selector = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
        vm.expectRevert(abi.encodeWithSelector(selector, address(0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf)));
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.withdrawEth();
        assertEq(address(this).balance, initialAdminBalance);
        assertEq(address(preSale).balance, weiAmount);
        preSale.withdrawEth();
        assertEq(address(this).balance, initialAdminBalance + weiAmount);
        assertEq(address(preSale).balance, 0);
    }

    function testRefundPurchaseUSDC() public {
        uint256 amount = 200;

        uint256 usdcValue = amount * preSale.tokenPrice();
        bytes32 structHash = keccak256(abi.encode(0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9, _buyer, address(preSale), usdcValue, usdc.nonces(_buyer) , maxInt));
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1, messageHash);

        uint256 bal = usdc.balanceOf(address(_buyer));
        assertEq(bal, 1000e6);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.permitAndPurchaseTokensWithUSDC(amount, v, r, s);
        uint256 bal2 = usdc.balanceOf(address(_buyer));
        assertEq(bal2, 1000e6 - amount*TOKEN_USDC_PRICE);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens, 200e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        preSale.refundPurchase(_buyer);
        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens2, 0);
        assertEq(releasePeriod2, 0);
        assertEq(startTime2, 0);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);
        uint256 bal3 = usdc.balanceOf(address(_buyer));
        assertEq(bal3, 1000e6);
    }

    function testPurchaseAndRefundEth() public {
        uint256 amount = 10_000_000;
        (, int256 price, , , ) = aggregator.latestRoundData();
        uint256 weiAmount = (TOKEN_USD_ETH_PRICE * (amount * 10**18)) / uint256(price);
        assertEq(address(preSale).balance, 0);
        hoax(_buyer, TOKEN_AMOUNT);
        preSale.purchaseTokensWithEth{value: weiAmount}(amount);
        (uint256 totalTokens, uint256 releasePeriod, uint256 startTime, uint256 releasedToken, uint256 lockDuration) =
            vesting.vestingSchedules(address(preSale), _buyer);
        assertEq(totalTokens, 10_000_000e18);
        assertEq(releasePeriod, _vestingScheduleMonth);
        assertEq(startTime, 1);
        assertEq(releasedToken, 0);
        assertEq(lockDuration, 0);

        assertEq(address(preSale).balance, weiAmount);
        assertEq(_buyer.balance, TOKEN_AMOUNT - weiAmount);
        preSale.refundPurchase(_buyer);
        assertEq(_buyer.balance, TOKEN_AMOUNT);
        assertEq(address(preSale).balance, 0);

        hoax(_buyer, TOKEN_AMOUNT);
        (uint256 totalTokens2, uint256 releasePeriod2, uint256 startTime2, uint256 releasedToken2, uint256 lockDuration2) =
            preSale.seeVestingSchedule();
        assertEq(totalTokens2, 0);
        assertEq(releasePeriod2, 0);
        assertEq(startTime2, 0);
        assertEq(releasedToken2, 0);
        assertEq(lockDuration2, 0);
    }

    receive() external payable {
        // console.log("receive()", msg.sender, msg.value, "");
    }
}
