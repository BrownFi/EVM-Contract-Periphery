pragma solidity >=0.5.0;

import "../interfaces/IBrownFiPair.sol";

import "./SafeMath.sol";


library BrownFiLibrary {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'BrownFiLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'BrownFiLibrary: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'689fb83dc5445f9bdeec02d0e7736f1a246b8d8a933fe4e72bc8faa91b04bbe4' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IBrownFiPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'BrownFiLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'BrownFiLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint k) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'BrownFiLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'BrownFiLibrary: INSUFFICIENT_LIQUIDITY');
        require(k > 0, 'BrownFiLibrary: INSUFFICIENT_K');
        if (k == 2000) {
            return amountOutWithKEqualsTo2000(reserveIn, reserveOut, amountIn);
        }
        else {
            uint delta = delta(reserveOut, reserveIn, amountIn, k);
            uint sqrtDelta = sqrtDelta(delta);
            return amountOutWithKSmallerThan2000(reserveIn, reserveOut, amountIn, k, sqrtDelta);
        }
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint k) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'BrownFiLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'BrownFiLibrary: INSUFFICIENT_LIQUIDITY');
        require(k > 0, 'BrownFiLibrary: INSUFFICIENT_K');

        uint numerator = reserveIn.mul(amountOut);
        numerator = numerator.mul(reserveOut.mul(2000).sub(amountOut.mul(2000)).add(amountOut.mul(k)));
        // 1000 = 100% fee 
        // k = 2000
        uint denominator = reserveOut.mul(reserveOut.sub(amountOut)).mul(1995); // 1995 = 2000 - 5. 0.5% fee
        return (numerator / denominator);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'BrownFiLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            address pair = pairFor(factory, path[i - 1], path[i]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, IBrownFiPair(pair).k());
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'BrownFiLibrary: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            // compute pair address
            address pair = pairFor(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut, IBrownFiPair(pair).k());
        }
    }

    // post trade price
    // function postP(uint reserveIn, uint reserveOut, uint amountOut, uint k) public pure returns (uint p){
    //     uint numerator = reserveOut.mul(4000).mul(reserveOut.sub(amountOut));
    //     // denominator = reserveIn*(4000*(reserveOut - amountOut) + 3*k +3*amountOut)
    //     // = reserveIn*4000*reserveOut - reserveIn*4000*amountOut + 3*reserveIn*k + 3*reserveIn*amountOut
    //     uint denominator = reserveIn.mul(4000).mul(reserveOut).add(reserveIn.mul(4000).mul(amountOut)).add(reserveIn.mul(3).mul(k)).add(reserveIn.mul(3).mul(amountOut));
    //     p = numerator / denominator;
    //     return p;
    // }

    function delta(uint reserveOut, uint reserveIn, uint amountIn, uint k) public pure returns (uint _delta){
        uint temp = reserveIn.mul(reserveIn).mul(1000);
        temp = temp.add(amountIn.mul(amountIn).mul(1000));
        temp = temp.add(reserveIn.mul(2).mul(amountIn).mul(k));
        temp = temp.sub(reserveIn.mul(2000).mul(amountIn));
        uint numerator = reserveOut.mul(temp);
        uint denominator = reserveIn.mul(reserveIn).mul(1000);
        _delta = numerator / denominator;  
        // if we multiply numerator by reserveOut before dividing by denominator, it will have higher precision but easier to overflow                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      
        return _delta.mul(reserveOut); 
    }

    function sqrtDelta(uint _delta) public pure returns (uint){
        return _delta.sqrt();
    }

    // fee will be charged in pair contract, it will be 0.25%
    // because of that, the front end will show 0.25% more than the actual amount
    function amountOutWithKEqualsTo2000 (uint reserveIn, uint reserveOut, uint amountIn) public pure returns (uint amountOut){
        uint numerator = reserveOut.mul(amountIn);
        uint denominator = reserveIn.add(amountIn); 
        amountOut = numerator / denominator;
    }

    function amountOutWithKSmallerThan2000 (uint reserveIn, uint reserveOut, uint amountIn, uint k, uint _sqrtDelta) public pure returns (uint amountOut){
        uint temp = reserveIn.mul(reserveOut).mul(1000);
        temp = temp.add(amountIn.mul(reserveOut).mul(1000));
        temp = temp.sub(reserveIn.mul(1000).mul(_sqrtDelta));
        uint numerator = temp;
        uint denominator = reserveIn.mul(2000).sub(k.mul(reserveIn));
        amountOut = numerator / denominator;
    }
}
