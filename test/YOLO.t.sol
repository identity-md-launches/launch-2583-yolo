// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YOLO} from "../src/YOLO.sol";

contract YOLOTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    YOLO private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(alice);
        token = new YOLO();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "YOLO");
        assertEq(token.symbol(), "YOLO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_constructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(alice);
        YOLO fresh = new YOLO();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_transferEmitsEventAndArrivesWhole() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(alice, bob, 250 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 250 ether));

        assertEq(token.balanceOf(alice), SUPPLY - 250 ether);
        assertEq(token.balanceOf(bob), 250 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanBeTransferred() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(bob, alice, 0);
        vm.prank(bob);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferPreservesBalance() public {
        vm.prank(alice);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWithoutBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferMaximumUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, type(uint256).max)
        );
        vm.prank(alice);
        token.transfer(bob, type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_approvalEmitsEventWithoutMovingTokens() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Approval(alice, spender, 100 ether);
        vm.prank(alice);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(alice, spender), 100 ether);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(spender, 30 ether));
        assertEq(token.allowance(alice, spender), 30 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_approvalToZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(alice);
        token.approve(address(0), 100 ether);
        assertEq(token.allowance(alice, address(0)), 0);
    }

    function test_transferFromSpendsOnlyCallersAllowance() public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 100 ether));
        assertTrue(token.approve(bob, 55 ether));
        vm.stopPrank();

        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(alice, bob, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 40 ether));
        assertEq(token.allowance(alice, spender), 60 ether);
        assertEq(token.allowance(alice, bob), 55 ether);
        assertEq(token.balanceOf(alice), SUPPLY - 40 ether);
        assertEq(token.balanceOf(bob), 40 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 60 ether));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_selfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 10 ether));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_unapprovedSpenderCannotMoveTokens() public {
        vm.prank(alice);
        assertTrue(token.approve(bob, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, spender, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, bob), SUPPLY);
    }

    function test_transferFromBeyondAllowanceRevertsAtomically() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromBeyondBalanceRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, SUPPLY + 1);
        assertEq(token.allowance(alice, spender), SUPPLY + 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdminEntryPointsForDeployerOrStranger() public {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("setMinter(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(alice);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
    }

    function test_deployerCannotSeizeHolderBalanceWithoutApproval() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(bob, alice, 1);
        assertEq(token.balanceOf(bob), 100 ether);
        vm.prank(bob);
        assertTrue(token.transfer(spender, 100 ether));
        assertEq(token.balanceOf(spender), 100 ether);
    }

    function test_plainEtherTransferIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool succeeded,) = address(token).call{value: 1 ether}("");
        assertFalse(succeeded);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    function testFuzz_transferPreservesSupplyAndExactBalances(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != alice);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(alice), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingRevertsWithoutChangingBalances(uint256 funded, uint256 excess) public {
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - funded);
        vm.prank(alice);
        assertTrue(token.transfer(bob, funded));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, funded, funded + excess)
        );
        vm.prank(bob);
        token.transfer(alice, funded + excess);
        assertEq(token.balanceOf(bob), funded);
        assertEq(token.balanceOf(alice), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromPreservesSupplyAndAccountsForAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), approved - amount);
        assertEq(token.balanceOf(alice), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
