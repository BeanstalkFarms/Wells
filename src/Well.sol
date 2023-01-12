/**
 * SPDX-License-Identifier: MIT
 **/

pragma solidity ^0.8.17;

import "oz/security/ReentrancyGuard.sol";
import "oz/token/ERC20/extensions/draft-ERC20Permit.sol";

import "src/interfaces/IWell.sol";
import "src/interfaces/IPump.sol";
import "src/interfaces/IWellFunction.sol";

import "src/utils/ImmutableTokens.sol";
import "src/utils/ImmutablePump.sol";
import "src/utils/ImmutableWellFunction.sol";

/**
 * @author Publius
 * @title Well
 * @dev A Well is a constant function AMM allowing the provisioning of liquidity
 * into a single pooled on-chain liquidity position.

 * Each Well has tokens, a pricing function, and a Pump.
 * - Tokens defines the set of tokens that can be exchanged in the pool.
 * - The pricing function defines an invariant relationship between the balances
 *   of the tokens in the pool and the number of LP tokens. See {IWellFunction}.
 * - Pumps are on-chain oracles that are updated every time the pool is
 *   interacted with. See {IPump}.
 * 
 * Including a Pump is optional. Only 1 Pump can be attached to a Well, but a
 * Pump can call other Pumps, allowing multiple Pumps to be used.
 * 
 * A Well's tokens, pricing function, and Pump are stored as immutable variables
 * to prevent unnessary SLOAD calls.
 * 
 * Users can swap tokens in and add/remove liquidity to a Well.
 *
 * Implementation of ERC-20, ERC-2612 and {IWell} interface.
 **/

contract Well is
    ERC20Permit,
    IWell,
    ImmutableTokens,
    ImmutableWellFunction,
    ImmutablePump,
    ReentrancyGuard
{
    /// @dev see {IWell.initialize}
    constructor(
        IERC20[] memory _tokens,
        Call memory _function,
        Call memory _pump,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        ImmutableTokens(_tokens)
        ImmutableWellFunction(_function)
        ImmutablePump(_pump)
        ReentrancyGuard()
    {
        if (_pump.target != address(0)) 
            IPump(_pump.target).attach(_pump.data, _tokens.length);
    }

    /// @dev see {IWell.tokens}
    function tokens()
        public
        view
        override(IWell, ImmutableTokens)
        returns (IERC20[] memory ts)
    {
        ts = ImmutableTokens.tokens();
    }

    /// @dev see {IWell.wellFunction}
    function wellFunction()
        public
        view
        override(IWell, ImmutableWellFunction)
        returns (Call memory)
    {
        return ImmutableWellFunction.wellFunction();
    }

    /// @dev see {IWell.pump}
    function pump()
        public
        view
        override(IWell, ImmutablePump)
        returns (Call memory)
    {
        return ImmutablePump.pump();
    }

    /// @dev see {IWell.well}
    function well() external view returns (
        IERC20[] memory _tokens,
        Call memory _wellFunction,
        Call memory _pump
    ) {
        _tokens = tokens();
        _wellFunction = wellFunction();
        _pump = pump();
    }

    /**
     * Swap
     **/

    /// @dev see {IWell.swapFrom}
    function swapFrom(
        IERC20 fromToken,
        IERC20 toToken,
        uint amountIn,
        uint minAmountOut,
        address recipient
    ) external nonReentrant returns (uint amountOut) {
        amountOut = uint(
            updatePumpsAndgetSwap(
                fromToken,
                toToken,
                int(amountIn),
                int(minAmountOut)
            )
        );
        _executeSwap(fromToken, toToken, amountIn, amountOut, recipient);
    }

    /// @dev see {IWell.swapTo}
    function swapTo(
        IERC20 fromToken,
        IERC20 toToken,
        uint maxAmountIn,
        uint amountOut,
        address recipient
    ) external nonReentrant returns (uint amountIn) {
        amountIn = uint(
            -updatePumpsAndgetSwap(
                toToken,
                fromToken,
                -int(amountOut),
                -int(maxAmountIn)
            )
        );
        _executeSwap(
            fromToken,
            toToken,
            amountIn,
            amountOut,
            recipient
        );
    }

    /// @dev see {IWell.getSwapIn}
    function getSwapIn(
        IERC20 fromToken,
        IERC20 toToken,
        uint amountOut
    ) external view returns (uint amountIn) {
        amountIn = uint(
            -getSwap(
                toToken,
                fromToken,
                -int(amountOut)
            )
        );
    }

    /// @dev see {IWell.getSwapOut}
    function getSwapOut(
        IERC20 fromToken,
        IERC20 toToken,
        uint amountIn
    ) external view returns (uint amountOut) {
        amountOut = uint(
            getSwap(
                fromToken,
                toToken,
                int(amountIn)
            )
        );
    }

    /// @dev low level swap function. Fetches balances, indexes of tokens and returns swap output.
    /// given a change in balance of iToken, returns change in balance of jToken.
    function getSwap(
        IERC20 iToken,
        IERC20 jToken,
        int amountIn
    ) public view returns (int amountOut) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = getBalances(_tokens);
        (uint i, uint j) = getIJ(_tokens, iToken, jToken);
        amountOut = calculateSwap(balances, i, j, amountIn);
    }

    /// @dev same as {getSwap}, but also updates pumps
    function updatePumpsAndgetSwap(
        IERC20 iToken,
        IERC20 jToken,
        int amountIn,
        int minAmountOut
    ) internal returns (int amountOut) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = pumpBalances(_tokens);
        (uint i, uint j) = getIJ(_tokens, iToken, jToken);
        amountOut = calculateSwap(balances, i, j, amountIn);
        require(amountOut >= minAmountOut, "Well: slippage");
    }

    /// @dev contains core swap logic.
    /// A swap to a specified amount is the same as a swap from a negative specified amount.
    /// Thus, swapFrom and swapTo can use the same swap logic using signed math.
    function calculateSwap(
        uint[] memory balances,
        uint i,
        uint j,
        int amountIn
    ) public view returns (int amountOut) {
        Call memory _wellFunction = wellFunction();
        balances[i] = amountIn > 0 
            ? balances[i] + uint(amountIn) 
            : balances[i] - uint(-amountIn);
        amountOut = int(balances[j]) - int(
            getBalance(
                _wellFunction,
                balances,
                j,
                totalSupply()
            )
        );
    }

    /// @dev executes token transfers and emits Swap event.
    function _executeSwap(
        IERC20 fromToken,
        IERC20 toToken,
        uint amountIn,
        uint amountOut,
        address recipient
    ) internal {
        fromToken.transferFrom(msg.sender, address(this), amountIn);
        toToken.transfer(recipient, amountOut);
        emit Swap(fromToken, toToken, amountIn, amountOut);
    }

    /**
     * Add Liquidity
     **/

    /// @dev see {IWell.addLiquidity}
    function addLiquidity(
        uint[] memory tokenAmountsIn,
        uint minAmountOut,
        address recipient
    ) external nonReentrant returns (uint amountOut) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = pumpBalances(_tokens);
        for (uint i; i < _tokens.length; ++i) {
            _tokens[i].transferFrom(
                msg.sender,
                address(this),
                tokenAmountsIn[i]
            );
            balances[i] = balances[i] + tokenAmountsIn[i];
        }
        amountOut = getLpTokenSupply(wellFunction(), balances) - totalSupply();
        require(amountOut >= minAmountOut, "Well: slippage");
        _mint(recipient, amountOut);
        emit AddLiquidity(tokenAmountsIn, amountOut);
    }

    /// @dev see {IWell.getAddLiquidityOut}
    function getAddLiquidityOut(uint[] memory tokenAmountsIn)
        external
        view
        returns (uint amountOut)
    {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = getBalances(_tokens);
        for (uint i; i < _tokens.length; ++i)
            balances[i] = balances[i] + tokenAmountsIn[i];
        amountOut = getLpTokenSupply(wellFunction(), balances) - totalSupply();
    }

    /**
     * Remove Liquidity
     **/

    /// @dev see {IWell.removeLiquidity}
    function removeLiquidity(
        uint lpAmountIn,
        uint[] calldata minTokenAmountsOut,
        address recipient
    ) external nonReentrant returns (uint[] memory tokenAmountsOut) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = pumpBalances(_tokens);
        uint lpTokenSupply = totalSupply();
        tokenAmountsOut = new uint[](_tokens.length);
        _burn(msg.sender, lpAmountIn);
        for (uint i; i < _tokens.length; ++i) {
            tokenAmountsOut[i] = (lpAmountIn * balances[i]) / lpTokenSupply;
            require(
                tokenAmountsOut[i] >= minTokenAmountsOut[i],
                "Well: slippage"
            );
            _tokens[i].transfer(recipient, tokenAmountsOut[i]);
        }
        emit RemoveLiquidity(lpAmountIn, tokenAmountsOut);
    }

    /// @dev see {IWell.getRemoveLiquidityOut}
    function getRemoveLiquidityOut(uint lpAmountIn)
        external
        view
        returns (uint[] memory tokenAmountsOut)
    {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = getBalances(_tokens);
        uint lpTokenSupply = totalSupply();
        tokenAmountsOut = new uint[](_tokens.length);
        for (uint i; i < _tokens.length; ++i) {
            tokenAmountsOut[i] = (lpAmountIn * balances[i]) / lpTokenSupply;
        }
    }

    /**
     * Remove Liquidity One Token
     **/

    /// @dev see {IWell.removeLiquidityOneToken}
    function removeLiquidityOneToken(
        IERC20 token,
        uint lpAmountIn,
        uint minTokenAmountOut,
        address recipient
    ) external nonReentrant returns (uint tokenAmountOut) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = pumpBalances(_tokens);
        tokenAmountOut = _getRemoveLiquidityOneTokenOut(
            _tokens,
            token,
            balances,
            lpAmountIn
        );
        require(tokenAmountOut >= minTokenAmountOut, "Well: slippage");

        _burn(msg.sender, lpAmountIn);
        token.transfer(recipient, tokenAmountOut);
        emit RemoveLiquidityOneToken(lpAmountIn, token, tokenAmountOut);

        // todo: decide on event signature.
        // uint[] memory tokenAmounts = new uint[](w.tokens.length);
        // tokenAmounts[i] = tokenAmountOut;
        // emit RemoveLiquidity(lpAmountIn, tokenAmounts);
    }

    /// @dev see {IWell.getRemoveLiquidityOneTokenOut}
    function getRemoveLiquidityOneTokenOut(IERC20 token, uint lpAmountIn)
        external
        view
        returns (uint tokenAmountOut)
    {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = getBalances(_tokens);
        tokenAmountOut = _getRemoveLiquidityOneTokenOut(
            _tokens,
            token,
            balances,
            lpAmountIn
        );
    }

    function _getRemoveLiquidityOneTokenOut(
        IERC20[] memory _tokens,
        IERC20 token,
        uint[] memory balances,
        uint lpAmountIn
    ) private view returns (uint tokenAmountOut) {
        uint j = getJ(_tokens, token);
        uint newLpTokenSupply = totalSupply() - lpAmountIn;
        uint newBalanceJ = getBalance(
            wellFunction(),
            balances,
            j,
            newLpTokenSupply
        );
        tokenAmountOut = balances[j] - newBalanceJ;
    }

    /**
     * Remove Liquidity Imbalanced
     **/

    /// @dev see {IWell.removeLiquidityImbalanced}
    function removeLiquidityImbalanced(
        uint maxLpAmountIn,
        uint[] calldata tokenAmountsOut,
        address recipient
    ) external nonReentrant returns (uint lpAmountIn) {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = pumpBalances(_tokens);
        lpAmountIn = _getRemoveLiquidityImbalanced(
            _tokens,
            balances,
            tokenAmountsOut
        );
        require(lpAmountIn <= maxLpAmountIn, "Well: slippage");
        _burn(msg.sender, lpAmountIn);
        for (uint i; i < _tokens.length; ++i)
            _tokens[i].transfer(recipient, tokenAmountsOut[i]);
        emit RemoveLiquidity(lpAmountIn, tokenAmountsOut);
    }

    /// @dev see {IWell.getRemoveLiquidityImbalanced}
    function getRemoveLiquidityImbalanced(uint[] calldata tokenAmountsOut)
        external
        view
        returns (uint lpAmountIn)
    {
        IERC20[] memory _tokens = tokens();
        uint[] memory balances = getBalances(_tokens);
        lpAmountIn = _getRemoveLiquidityImbalanced(
            _tokens,
            balances,
            tokenAmountsOut
        );
    }

    function _getRemoveLiquidityImbalanced(
        IERC20[] memory _tokens,
        uint[] memory balances,
        uint[] calldata tokenAmountsOut
    ) private view returns (uint) {
        for (uint i; i < _tokens.length; ++i)
            balances[i] = balances[i] - tokenAmountsOut[i];
        return totalSupply() - getLpTokenSupply(wellFunction(), balances);
    }

    /// @dev Fetches the current balances of the Well and updates the Pump.
    function pumpBalances(IERC20[] memory _tokens)
        internal
        returns (uint[] memory balances)
    {
        balances = getBalances(_tokens);
        updatePump(balances);
    }

    /// @dev Updates the Pump with the previous balances.
    function updatePump(uint[] memory balances)
        internal
    {
        if (pumpAddress() != address(0))
            IPump(pumpAddress()).update(pumpBytes(), balances);
    }

    /// @dev Returns the Well's balances of `_tokens` by calling {balanceOf} on 
    /// each token.
    function getBalances(IERC20[] memory _tokens)
        internal
        view
        returns (uint[] memory balances)
    {
        balances = new uint[](_tokens.length);
        for (uint i; i < _tokens.length; ++i)
            balances[i] = _tokens[i].balanceOf(address(this));
    }

    /// @dev Gets the LP token supply given a list of `balances`.
    /// Wraps {IWellFunction.getLpTokenSupply}.
    function getLpTokenSupply(Call memory _wellFunction, uint[] memory balances)
        internal
        view
        returns (uint lpTokenSupply)
    {
        lpTokenSupply = IWellFunction(_wellFunction.target).getLpTokenSupply(
            _wellFunction.data,
            balances
        );
    }

    /// @dev Gets the jth balance given a list of `balances` and `lpTokenSupply`.
    /// Wraps {IWellFunction.getBalance}.
    function getBalance(
        Call memory wf,
        uint[] memory balances,
        uint j,
        uint lpTokenSupply
    ) internal view returns (uint balance) {
        balance = IWellFunction(wf.target).getBalance(
            wf.data,
            balances,
            j,
            lpTokenSupply
        );
    }

    /// @dev Returns the indices of `iToken` and `jToken` in `_tokens`.
    function getIJ(
        IERC20[] memory _tokens,
        IERC20 iToken,
        IERC20 jToken
    ) internal pure returns (uint i, uint j) {
        for (uint k; k < _tokens.length; ++k) {
            if (iToken == _tokens[i]) i = k;
            else if (jToken == _tokens[i]) j = k;
        }
    }

    /// @dev Returns the index of `jToken` in `_tokens`.
    function getJ(IERC20[] memory _tokens, IERC20 jToken)
        internal
        pure
        returns (uint j)
    {
        for (j; jToken != _tokens[j]; ++j) {}
    }
}