// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uniswap interface and library imports
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "hardhat/console.sol";

contract FlashLoan {
    // Factory and Routing addresses for PancakeSwap
    address private constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // Token addresses
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant CROX = 0x2c094F5A7D1146BB93850f629501eB749f6Ed491;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

    // Deadline
    uint private deadline = block.timestamp + 1 days;

    uint private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function checkResult(
        uint _amountToRepay,
        uint _acquiredCoin
    ) private pure returns (bool) {
        return _acquiredCoin > _amountToRepay;
    }

    function getBalanceOfToken(address _token) private view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }

    function placeTrade(
        address _fromToken,
        address _toToken,
        uint _amountIn
    ) private returns (uint) {
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _fromToken,
            _toToken
        );

        require(pair != address(0), "This pool does not exist");

        // Calculate amount out
        address[] memory path = new address[](2); // length 2 array
        path[0] = _fromToken;
        path[1] = _toToken;

        uint amountRequired = IUniswapV2Router01(PANCAKE_ROUTER).getAmountsOut(
            _amountIn,
            path
        )[1];

        uint amountReceived = IUniswapV2Router01(PANCAKE_ROUTER)
            .swapExactTokensForTokens(
                _amountIn,
                amountRequired,
                path,
                address(this),
                deadline
            )[1];

        require(amountReceived > 0, "Transaction Abort: Error swapping tokens");

        return amountReceived;
    }

    function initiateArbitrage(address _BUSD_Borrow, uint _amount) external {
        IERC20(BUSD).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(CROX).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(CAKE).safeApprove(address(PANCAKE_ROUTER), MAX_INT);

        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _BUSD_Borrow,
            WBNB
        );

        require(pair != address(0), "This pool does not exist");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint amount0Out = _BUSD_Borrow == token0 ? _amount : 0; // WBNB
        uint amount1Out = _BUSD_Borrow == token1 ? _amount : 0; // BUSD

        bytes memory data = abi.encode(_BUSD_Borrow, _amount, msg.sender);

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function pancakeCall(
        address _sender,
        uint _amount0,
        uint _amount1,
        bytes calldata _data
    ) external {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();

        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            token0,
            token1
        );

        require(msg.sender == pair, "Pair does not match");
        require(_sender == address(this), "Sender does not match");

        (address busdBorrow, uint amount, address myAddress) = abi.decode(
            _data,
            (address, uint, address)
        );

        // Calculate the amount to repay at the end
        uint fee = ((amount * 3) / 997) + 1;
        uint amountToRepay = amount + fee;

        // Assign loan amount
        uint loanAmount = _amount0 > 0 ? _amount0 : _amount1;

        // Place trades
        uint tradeCoin1 = placeTrade(BUSD, CROX, loanAmount);
        uint tradeCoin2 = placeTrade(CROX, CAKE, tradeCoin1);
        uint tradeCoin3 = placeTrade(CAKE, BUSD, tradeCoin2);

        // Check if profit is made
        bool profit = checkResult(amountToRepay, tradeCoin3);

        require(profit, "Arbitrage not profitable");

        // Pay myself
        IERC20(BUSD).transfer(myAddress, tradeCoin3 - amountToRepay);

        // Pay loan back
        IERC20(busdBorrow).transfer(pair, amountToRepay);
    }
}
