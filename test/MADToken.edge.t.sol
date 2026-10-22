// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Deploys the token and performs every launch transfer leg inside one constructor, i.e. one
///      transaction, the way a launch factory does.
contract OneTransactionLaunch {
    MADToken public immutable token;
    uint256 public immutable balanceAfterDeploy;
    uint256 public immutable supplyAfterDeploy;

    constructor(address distributor, address poolManager, address remainder) {
        token = new MADToken{salt: bytes32(uint256(1))}();
        balanceAfterDeploy = token.balanceOf(address(this));
        supplyAfterDeploy = token.totalSupply();
        uint256 supply = supplyAfterDeploy;
        require(token.transfer(distributor, supply / 10), "swarm leg");
        require(token.transfer(poolManager, supply * 8 / 10), "pool leg");
        require(token.transfer(remainder, supply - supply / 10 - supply * 8 / 10), "remainder leg");
    }
}

contract MADTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADToken internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");

    function setUp() public {
        token = new MADToken();
    }

    function test_SupplyIsExactlyTenToThe27() public view {
        assertEq(SUPPLY, 10 ** 27);
        assertEq(token.totalSupply(), 10 ** 27);
        assertEq(IERC20Metadata(address(token)).decimals(), 18);
    }

    function test_OneTransactionLaunchLegsAreExact() public {
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainder = makeAddr("remainder");
        OneTransactionLaunch launch = new OneTransactionLaunch(distributor, poolManager, remainder);
        MADToken launched = launch.token();
        assertEq(launch.balanceAfterDeploy(), SUPPLY);
        assertEq(launch.supplyAfterDeploy(), SUPPLY);
        assertEq(launched.balanceOf(address(launch)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(poolManager), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferExactBalanceSucceedsButOneMoreReverts() public {
        token.transfer(alice, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1000, 1001));
        token.transfer(bob, 1001);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1000));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1000);
    }

    function test_TransferMaxUintReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_TransferFromExactAllowanceThenOneWeiMoreReverts() public {
        token.approve(spender, 5);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), 5);
    }

    function test_AllowanceOneBelowMaxIsFiniteAndDecreases() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 10);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 11);
    }

    function test_InfiniteAllowanceCanMoveEntireSupplyButNoMore() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_TransferFromZeroSourceZeroValueRevertsInvalidApprover() public {
        // A zero-value spend still rewrites the allowance, so the zero owner is rejected as approver.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_TransferFromZeroSourceNonZeroValueRevertsOnAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
    }

    function test_AllowancesAreDirectionalAndPerSpender() public {
        token.approve(spender, 7);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.allowance(address(this), alice), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(alice, bob, 1);
    }

    function test_TokensSentToTokenContractAreUnrecoverable() public {
        // Documented behaviour: nothing can move tokens out of the token's own address.
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), address(this), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    function _isPublicSelector(bytes4 selector) internal pure returns (bool) {
        return selector == IERC20.totalSupply.selector || selector == IERC20.balanceOf.selector
            || selector == IERC20.transfer.selector || selector == IERC20.allowance.selector
            || selector == IERC20.approve.selector || selector == IERC20.transferFrom.selector
            || selector == IERC20Metadata.name.selector || selector == IERC20Metadata.symbol.selector
            || selector == IERC20Metadata.decimals.selector || selector == bytes4(keccak256("INITIAL_SUPPLY()"));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnknownSelectorsRevertAndChangeNothing(
        bytes4 selector,
        address caller,
        bytes32 arg0,
        bytes32 arg1
    ) public {
        if (_isPublicSelector(selector)) selector = bytes4(keccak256(abi.encode(selector)));
        token.transfer(alice, 100 ether);
        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodePacked(selector, arg0, arg1));
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100 ether);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveStoresExactValue(address owner, address who, uint256 amount) public {
        owner = address(uint160(bound(uint160(owner), 1, type(uint160).max)));
        who = address(uint160(bound(uint160(who), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(who, amount));
        assertEq(token.allowance(owner, who), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SplitSpendsNeverExceedAllowance(uint256 approved, uint256 first, uint256 second) public {
        approved = bound(approved, 0, SUPPLY);
        first = bound(first, 0, approved);
        second = bound(second, 0, SUPPLY);
        token.approve(spender, approved);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, first);
        uint256 left = approved - first;
        if (second > left) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, left, second)
            );
            token.transferFrom(address(this), bob, second);
            assertEq(token.balanceOf(bob), 0);
        } else {
            token.transferFrom(address(this), bob, second);
            assertEq(token.balanceOf(bob), second);
        }
        vm.stopPrank();
        assertLe(token.balanceOf(alice) + token.balanceOf(bob), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RoundTripRestoresBalances(uint256 amount, uint256 back) public {
        amount = bound(amount, 0, SUPPLY);
        back = bound(back, 0, amount);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(address(this), back);
        assertEq(token.balanceOf(alice), amount - back);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount + back);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ThirdPartiesUnaffectedByTransfer(address from, address to, uint256 funded, uint256 amount)
        public
    {
        address bystander = makeAddr("edge bystander");
        from = address(uint160(bound(uint160(from), 1, type(uint160).max)));
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        if (from == bystander || from == address(this)) from = alice;
        if (to == bystander || to == address(this)) to = bob;
        token.transfer(bystander, 3 ether);
        token.approve(spender, 11);
        funded = bound(funded, 0, SUPPLY - 3 ether);
        token.transfer(from, funded);
        amount = bound(amount, 0, funded);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(bystander), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3 ether - funded);
        assertEq(token.allowance(address(this), spender), 11);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
