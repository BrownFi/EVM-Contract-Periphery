pragma solidity >=0.5.0;

import "./IUniswapV2Pair.sol";

import "./SafeMath.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint k) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        require(k > 0, 'UniswapV2Library: INSUFFICIENT_K');
        uint r = R(amountOut, reserveOut, k);
        uint _avgP = avgP(reserveIn, reserveOut, r);
        uint amountInWithFee = amtIn(amountOut, _avgP);
        return amountInWithFee;
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            // compute pair address
            address pair = pairFor(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, IUniswapV2Pair(pair).K());
        }
    }
    // price impact
    function R(uint amountOut, uint reserveOut, uint k) public pure returns (uint r){
        require(amountOut < reserveOut, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        uint numerator = k.mul(amountOut);
        uint denominator = reserveOut.sub(amountOut).mul(10000);
        r = numerator / denominator;
        return r.add(1);
    }

    // average price
    function avgP(uint reserveIn, uint reserveOut, uint r) internal pure returns (uint p){
        uint numerator = r.add(2).mul(reserveIn);
        uint denominator = reserveOut.mul(2);
        p = numerator / denominator;
        return p.add(1);
    }

    // amountIn 
    function amtIn(uint amountOut, uint _avgP) internal pure returns (uint amountIn){
        amountIn = amountOut.mul(_avgP);
        return amountIn.add(1);
    }

    // post trade price
    function postP(uint reserveIn, uint reserveOut, uint r) internal pure returns (uint p){
        uint numerator = r.mul(3).add(4).mul(reserveOut);
        uint denominator = reserveIn.mul(4);
        p = numerator / denominator;
        return p.add(1);
    }

    // amountInWithFee
    // fee is 0.5% = 50/10000
    function amtInWithFee(uint amountIn) internal pure returns (uint amountInWithFee){
        uint numerator = amountIn.mul(2).mul(10000);
        // 10000 *2 - 50 = 19950
        uint denominator = 19950;
        amountInWithFee = numerator / denominator;
        return amountInWithFee.add(1);
    }

    // amountOutWithFee
    // fee is 0.5% = 50/10000
    function amtOutWithFee(uint amountOut) internal pure returns (uint amountOutWithFee){
        uint numerator = amountOut.mul(10000);
        // 10000 - 50 = 9950
        uint denominator = 9950;
        amountOutWithFee = numerator / denominator;
        return amountOutWithFee.add(1);
    }
}
