// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IWETH {
    function deposit() external payable;

    function approve(address guy, uint256 wad) external returns (bool);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(
        QuoteExactInputSingleParams memory params
    )
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract Models is ReentrancyGuard, Ownable {
    uint256 public constant PRICE_SCALE = 1e8;
    uint256 public constant MIN_PAYMENT_BPS = 90;
    uint256 public constant BPS_DENOM = 100;

    uint256[] public boosterPrices;

    mapping(address => uint256) public level;

    address public recipient;

    IQuoterV2 public quoter;
    ISwapRouter02 public swapRouter;
    address public weth;
    address public usd;
    uint24 public poolFee;
    uint8 public usdDecimals;

    event Upgraded(
        address indexed user,
        uint256 fromLevel,
        uint256 toLevel,
        uint256 usdPrice1e8,
        uint256 ethRequired,
        uint256 ethPaid
    );
    event RecipientUpdated(address indexed newRecipient);
    event PriceConfigUpdated(
        address quoter,
        address swapRouter,
        address weth,
        address usd,
        uint24 poolFee,
        uint8 usdDecimals
    );

    constructor(
        uint256[] memory _boosterPrices,
        address _recipient,
        address _quoter,
        address _swapRouter,
        address _weth,
        address _usd,
        uint24 _poolFee,
        uint8 _usdDecimals
    ) Ownable(msg.sender) {
        require(_boosterPrices.length > 0, "empty booster list");
        require(_recipient != address(0), "zero recipient");
        require(
            _quoter != address(0) &&
                _swapRouter != address(0) &&
                _weth != address(0) &&
                _usd != address(0),
            "zero addr"
        );

        boosterPrices = _boosterPrices;
        recipient = _recipient;
        quoter = IQuoterV2(_quoter);
        swapRouter = ISwapRouter02(_swapRouter);
        weth = _weth;
        usd = _usd;
        poolFee = _poolFee;
        usdDecimals = _usdDecimals;
    }

    function boosterCount() external view returns (uint256) {
        return boosterPrices.length;
    }

    function boosterPricesAll() external view returns (uint256[] memory) {
        return boosterPrices;
    }

    function getEthPriceUsd1e8() public returns (uint256) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2
            .QuoteExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usd,
                amountIn: 1 ether,
                fee: poolFee,
                sqrtPriceLimitX96: 0
            });

        (uint256 amountOut, , , ) = quoter.quoteExactInputSingle(params);
        require(amountOut > 0, "bad quote");

        if (usdDecimals == 8) {
            return amountOut;
        } else if (usdDecimals < 8) {
            return amountOut * (10 ** (8 - usdDecimals));
        } else {
            return amountOut / (10 ** (usdDecimals - 8));
        }
    }

    function usdtoEth(uint256 usdAmount1e8) public returns (uint256) {
        uint256 ethPriceUsd1e8 = getEthPriceUsd1e8();
        return (usdAmount1e8 * 1e18) / ethPriceUsd1e8;
    }

    function _validatePayment(
        uint256 usdPrice1e8
    ) internal returns (uint256 requiredEth) {
        requiredEth = usdtoEth(usdPrice1e8);
        uint256 minAcceptable = (requiredEth * MIN_PAYMENT_BPS) / BPS_DENOM;
        require(msg.value >= minAcceptable, "insufficient payment");
    }

    function _swapAndForward(
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2
            .QuoteExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usd,
                amountIn: amountIn,
                fee: poolFee,
                sqrtPriceLimitX96: 0
            });

        (uint256 quotedAmountOut, , , ) = quoter.quoteExactInputSingle(params);
        require(quotedAmountOut > 0, "bad swap quote");

        IWETH(weth).deposit{value: amountIn}();
        IWETH(weth).approve(address(swapRouter), amountIn);

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: usd,
                fee: poolFee,
                recipient: recipient,
                amountIn: amountIn,
                amountOutMinimum: (quotedAmountOut * MIN_PAYMENT_BPS) /
                    BPS_DENOM,
                sqrtPriceLimitX96: 0
            })
        );
        require(amountOut > 0, "swap failed");
    }

    function upgrade() external payable nonReentrant {
        uint256 current = level[msg.sender];
        require(current < boosterPrices.length, "already at max level");

        uint256 usdPrice = boosterPrices[current];
        uint256 requiredEth = _validatePayment(usdPrice);

        uint256 next = current + 1;
        level[msg.sender] = next;

        _swapAndForward(msg.value);

        emit Upgraded(
            msg.sender,
            current,
            next,
            usdPrice,
            requiredEth,
            msg.value
        );
    }

    function setRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "zero recipient");
        recipient = _recipient;
        emit RecipientUpdated(_recipient);
    }

    function setPriceConfig(
        address _quoter,
        address _swapRouter,
        address _weth,
        address _usd,
        uint24 _poolFee,
        uint8 _usdDecimals
    ) external onlyOwner {
        require(
            _quoter != address(0) &&
                _swapRouter != address(0) &&
                _weth != address(0) &&
                _usd != address(0),
            "zero addr"
        );
        quoter = IQuoterV2(_quoter);
        swapRouter = ISwapRouter02(_swapRouter);
        weth = _weth;
        usd = _usd;
        poolFee = _poolFee;
        usdDecimals = _usdDecimals;
        emit PriceConfigUpdated(
            _quoter,
            _swapRouter,
            _weth,
            _usd,
            _poolFee,
            _usdDecimals
        );
    }
}
