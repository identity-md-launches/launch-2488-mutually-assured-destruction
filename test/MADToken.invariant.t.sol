// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev All balances remain within a closed set of actors so conservation can be checked.
contract MADTokenHandler is Test {
    MADToken public immutable token;
    address[4] public actors;

    constructor() {
        token = new MADToken();
        actors = [address(this), makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three")];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(from);
        uint256 beforeTo = token.balanceOf(to);
        amount = bound(amount, 0, beforeFrom);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _assertBalances(from, to, beforeFrom, beforeTo, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = token.balanceOf(owner);
        uint256 beforeTo = token.balanceOf(to);
        uint256 allowed = token.allowance(owner, spender);
        amount = bound(amount, 0, beforeFrom < allowed ? beforeFrom : allowed);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        _assertBalances(owner, to, beforeFrom, beforeTo, amount);
    }

    function _assertBalances(address from, address to, uint256 beforeFrom, uint256 beforeTo, uint256 amount)
        internal
        view
    {
        if (from == to) {
            assertEq(token.balanceOf(from), beforeFrom);
        } else {
            assertEq(token.balanceOf(from), beforeFrom - amount);
            assertEq(token.balanceOf(to), beforeTo + amount);
        }
    }
}

contract MADTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    MADTokenHandler internal handler;
    MADToken internal token;

    function setUp() public {
        handler = new MADTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MADTokenHandler.transfer.selector;
        selectors[1] = MADTokenHandler.approve.selector;
        selectors[2] = MADTokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_EntireSupplyIsConservedAcrossCallSequences() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
