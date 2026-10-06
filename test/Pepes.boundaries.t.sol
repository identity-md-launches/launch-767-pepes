// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepes} from "src/Pepes.sol";

/// @dev Complements the deployment and ERC-20 tests with arithmetic boundaries and allowance lifecycles.
/// forge-config: default.fuzz.runs = 1000
contract PepesBoundaryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Pepes internal token;

    function setUp() public {
        token = new Pepes();
    }

    function test_MaximumTransfersRevertWithoutOverflowOrStateChanges() public {
        uint256 amount = type(uint256).max;
        bytes memory balanceError =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(balanceError);
        token.transfer(ALICE, amount);

        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        vm.expectRevert(balanceError);
        token.transferFrom(address(this), ALICE, amount);

        assertEq(token.allowance(address(this), SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsConsumed() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), approved - 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceCanBeRevokedAfterUse() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);

        assertTrue(token.approve(SPENDER, 0));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        // A new finite approval must replace the revoked unlimited approval.
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_ConsumedAllowanceCannotBeReplayed() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_OwnerTransferFromRequiresAndConsumesSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(ALICE), 1);
    }

    function test_SelfTransfersCannotBypassBalanceCheck() public {
        uint256 amount = SUPPLY + 1;
        bytes memory balanceError =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount);
        vm.expectRevert(balanceError);
        token.transfer(address(this), amount);

        token.approve(SPENDER, amount);
        vm.prank(SPENDER);
        vm.expectRevert(balanceError);
        token.transferFrom(address(this), address(this), amount);
        assertEq(token.allowance(address(this), SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferFromCannotBypassAllowanceCheck() public {
        token.approve(SPENDER, 1);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1, 2));
        token.transferFrom(address(this), address(this), 2);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroValueCallsStillRejectZeroAddresses() public {
        token.approve(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalsAreIsolatedByOwnerAndSpender() public {
        token.transfer(ALICE, 10);
        token.transfer(BOB, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 7);
        vm.prank(BOB);
        token.approve(SPENDER, 9);
        vm.prank(ALICE);
        token.approve(BOB, 3);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        assertEq(token.allowance(ALICE, SPENDER), 5);
        assertEq(token.allowance(BOB, SPENDER), 9);
        assertEq(token.allowance(ALICE, BOB), 3);

        vm.prank(ALICE);
        token.approve(SPENDER, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(BOB, ALICE, 9));
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 3));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
        assertEq(token.balanceOf(ALICE), 14);
        assertEq(token.balanceOf(BOB), 6);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20);
    }

    function testFuzz_TransferRoundTripRestoresBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectTransfersLeaveApprovalsUntouched(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(SPENDER, approved));
        assertTrue(token.transfer(SPENDER, amount));
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(SPENDER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailurePreservesApprovalForRetry(uint256 balance, uint256 excess, bool infinite) public {
        balance = bound(balance, 1, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        uint256 attempted = balance + excess;
        uint256 approved = infinite ? type(uint256).max : attempted;
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, approved);

        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, attempted)
        );
        token.transferFrom(ALICE, BOB, attempted);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), approved);

        // The same spender can use the original approval after correcting only the amount.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, balance));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), balance);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), approved == type(uint256).max ? approved : approved - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitSpendingExhaustsOnlyTheApprovedAmount(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY - 1);
        first = bound(first, 0, approved);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertEq(token.allowance(address(this), SPENDER), approved - first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, approved - first));

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), first);
        assertEq(token.balanceOf(BOB), approved - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - approved);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
