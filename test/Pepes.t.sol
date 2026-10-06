// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Pepes} from "../src/Pepes.sol";

/// @dev Local deployment probe, never a production component.
contract PepesFactoryProbe {
    function deploy(bytes32 salt) external returns (Pepes) {
        return new Pepes{salt: salt}();
    }

    function move(Pepes token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract PepesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    Pepes internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Pepes();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Pepes");
        assertEq(token.symbol(), "PEPES");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        Pepes fresh = new Pepes();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_Create2MintsToFactoryAndLaunchTransfersArriveWhole() public {
        PepesFactoryProbe factory = new PepesFactoryProbe();
        vm.prank(ALICE);
        Pepes launched = factory.deploy(bytes32(uint256(1)));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = address(0xD157);
        address poolCustodian = address(0x9001);
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY / 2;
        assertTrue(factory.move(launched, distributor, swarmShare));
        assertEq(launched.balanceOf(distributor), swarmShare);
        vm.prank(distributor);
        assertTrue(launched.transfer(BOB, swarmShare));
        assertEq(launched.balanceOf(BOB), swarmShare);
        assertEq(launched.balanceOf(distributor), 0);

        assertTrue(factory.move(launched, poolCustodian, poolShare));
        assertEq(launched.balanceOf(poolCustodian), poolShare);
        vm.prank(poolCustodian);
        assertTrue(launched.transfer(ALICE, 123 ether));
        assertEq(launched.balanceOf(ALICE), 123 ether);
        vm.prank(ALICE);
        assertTrue(launched.transfer(poolCustodian, 123 ether));
        assertEq(launched.balanceOf(poolCustodian), poolShare);

        uint256 remainder = SUPPLY - swarmShare - poolShare;
        assertTrue(factory.move(launched, ALICE, remainder));
        assertEq(launched.balanceOf(ALICE), remainder);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 125 ether);
        assertTrue(token.transfer(ALICE, 125 ether));
        assertEq(token.balanceOf(ALICE), 125 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 125 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(ALICE, 0);
    }

    function test_EmptyAccountCannotTransfer() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ApproveEmitsEventAndCanReplaceOrRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100 ether);
        assertTrue(token.approve(SPENDER, 100 ether));
        assertEq(token.allowance(address(this), SPENDER), 100 ether);
        assertTrue(token.approve(SPENDER, 12 ether));
        assertEq(token.allowance(address(this), SPENDER), 12 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_ApproveFromZeroOwnerReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(SPENDER, 1);
    }

    function test_TransferFromEmitsTransferAndConsumesFiniteAllowance() public {
        token.approve(SPENDER, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 40 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40 ether));
        assertEq(token.allowance(address(this), SPENDER), 60 ether);
        assertEq(token.balanceOf(ALICE), 40 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function test_InfiniteAllowanceIsNotReduced() public {
        token.approve(SPENDER, type(uint256).max);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertTrue(token.transferFrom(address(this), BOB, 2));
        vm.stopPrank();
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 2);
    }

    function test_TransferFromSelfStillConsumesAllowance() public {
        token.approve(SPENDER, 9);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 9));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ApprovalDoesNotAuthorizeOtherSpenders() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DeployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_BalanceFailureRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_InvalidRecipientRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        token.transfer(ALICE, 10 ether);
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[11] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 10 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_RuntimeContainsNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
            }
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromHonorsAllowance(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        assertTrue(token.approve(SPENDER, approved));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));
        assertEq(token.allowance(address(this), SPENDER), approved - spent);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutChangingBalances(uint256 excess) public {
        excess = bound(excess, 1, type(uint256).max - SUPPLY);
        uint256 amount = SUPPLY + excess;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceIsAtomic(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approved);
        token.approve(SPENDER, approved);
        uint256 amount = approved + excess;
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approved, amount)
        );
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
