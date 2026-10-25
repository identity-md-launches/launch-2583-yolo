// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YOLO} from "src/YOLO.sol";

/// @dev Receiving ERC-20 balances must not require a recipient callback.
contract RejectingYOLORecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

/// @dev Complements the issuance and launch tests with allowance lifecycles and algebraic properties.
/// forge-config: default.fuzz.runs = 1024
contract YOLOPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    YOLO private token;
    address private holder;
    address private recipient;
    address private spender;
    address private otherSpender;

    function setUp() public {
        holder = makeAddr("property holder");
        recipient = makeAddr("property recipient");
        spender = makeAddr("property spender");
        otherSpender = makeAddr("property other spender");
        vm.prank(holder);
        token = new YOLO();
    }

    function test_approveZeroSpenderRejectsEvenZeroAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroTransferFromToZeroIsStillInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_zeroTransferFromEmptyHolderEmitsTransfer() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(recipient, holder, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, holder, 0));
        assertEq(token.allowance(recipient, spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_selfTransferCannotBypassInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(recipient);
        token.transfer(recipient, 1);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(holder);
        token.transfer(holder, SUPPLY + 1);
        _assertBalances(SUPPLY, 0);
    }

    function test_ownerUsingTransferFromNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        _assertBalances(SUPPLY, 0);

        _approve(holder, holder, 1);
        _spend(holder, holder, recipient, 1);
        assertEq(token.allowance(holder, holder), 0);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(holder, spender, type(uint256).max - 1);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_infiniteApprovalCanBeRevokedAfterSpending() public {
        _approve(holder, spender, type(uint256).max);
        _spend(spender, holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Approval(holder, spender, 0);
        _approve(holder, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY - 1, 1);
    }

    function test_returningTokensDoesNotRestoreExhaustedAllowance() public {
        _approve(holder, spender, SUPPLY);
        _spend(spender, holder, recipient, SUPPLY);
        _assertBalances(0, SUPPLY);
        _send(recipient, holder, SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_approvalBeforeFundingSurvivesFailedSpendAndWorksAfterFunding() public {
        _approve(recipient, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, holder, 1);
        assertEq(token.allowance(recipient, spender), 1);
        _assertBalances(SUPPLY, 0);

        _send(holder, recipient, 1);
        _spend(spender, recipient, holder, 1);
        assertEq(token.allowance(recipient, spender), 0);
        _assertBalances(SUPPLY, 0);
    }

    function test_contractRecipientDoesNotNeedACallback() public {
        RejectingYOLORecipient receiver = new RejectingYOLORecipient();
        _send(holder, address(receiver), 1);
        _approve(holder, spender, 1);
        _spend(spender, holder, address(receiver), 1);
        assertEq(token.balanceOf(address(receiver)), 2);
        assertEq(token.balanceOf(holder), SUPPLY - 2);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBalancesAndLeavesApprovalsAlone(
        uint256 initialRecipientBalance,
        uint256 amount,
        uint256 approved
    ) public {
        initialRecipientBalance = bound(initialRecipientBalance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - initialRecipientBalance);
        _send(holder, recipient, initialRecipientBalance);
        _approve(holder, spender, approved);
        _approve(recipient, spender, approved);

        _send(holder, recipient, amount);
        _assertBalances(SUPPLY - initialRecipientBalance - amount, initialRecipientBalance + amount);
        _send(recipient, holder, amount);
        _assertBalances(SUPPLY - initialRecipientBalance, initialRecipientBalance);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.allowance(recipient, spender), approved);
    }

    function testFuzz_splitDelegatedTransfersEqualOneTransfer(uint256 approved, uint256 total, uint256 first) public {
        total = bound(total, 0, approved < SUPPLY ? approved : SUPPLY);
        first = bound(first, 0, total);
        _approve(holder, spender, approved);
        uint256 snapshot = vm.snapshotState();

        _spend(spender, holder, recipient, total);
        uint256 remaining = token.allowance(holder, spender);
        _assertBalances(SUPPLY - total, total);
        assertEq(remaining, approved == type(uint256).max ? approved : approved - total);

        assertTrue(vm.revertToStateAndDelete(snapshot));
        _spend(spender, holder, recipient, first);
        _spend(spender, holder, recipient, total - first);
        _assertBalances(SUPPLY - total, total);
        assertEq(token.allowance(holder, spender), remaining);
    }

    function testFuzz_delegatedSelfTransferSpendsAllowanceWithoutMovingBalances(
        uint256 approved,
        uint256 amount,
        bool infinite
    ) public {
        approved = infinite ? type(uint256).max : bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        _approve(holder, spender, approved);
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Transfer(holder, holder, amount);
        _spend(spender, holder, holder, amount);
        assertEq(token.allowance(holder, spender), infinite ? approved : approved - amount);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_repeatedBalanceFailuresPreserveFiniteOrInfiniteApproval(
        uint256 funded,
        uint256 excess,
        bool infinite
    ) public {
        funded = bound(funded, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - funded);
        uint256 requested = funded + excess;
        uint256 approved = infinite ? type(uint256).max : requested;
        _send(holder, recipient, funded);
        _approve(recipient, spender, approved);

        for (uint256 i; i < 2; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, funded, requested)
            );
            vm.prank(spender);
            token.transferFrom(recipient, holder, requested);
            assertEq(token.allowance(recipient, spender), approved);
            _assertBalances(SUPPLY - funded, funded);
        }
    }

    function testFuzz_insufficientAllowanceCannotUseAnotherSpendersApproval(uint256 approved, uint256 requested)
        public
    {
        approved = bound(approved, 0, SUPPLY - 1);
        requested = bound(requested, approved + 1, SUPPLY);
        _approve(holder, spender, approved);
        _approve(holder, otherSpender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, requested)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, requested);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.allowance(holder, otherSpender), type(uint256).max);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_replacementApprovalAfterPartialSpendIsExact(uint256 initial, uint256 spent, uint256 replacement)
        public
    {
        initial = bound(initial, 1, SUPPLY);
        spent = bound(spent, 1, initial);
        _approve(holder, spender, initial);
        _spend(spender, holder, recipient, spent);
        vm.expectEmit(true, true, true, true, address(token));
        emit IERC20.Approval(holder, spender, replacement);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        _assertBalances(SUPPLY - spent, spent);

        uint256 next = replacement < SUPPLY - spent ? replacement : SUPPLY - spent;
        _spend(spender, holder, recipient, next);
        assertEq(token.allowance(holder, spender), replacement == type(uint256).max ? replacement : replacement - next);
        _assertBalances(SUPPLY - spent - next, spent + next);
    }

    function testFuzz_zeroReceiverFailurePreservesAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        _approve(holder, spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), approved);
        _assertBalances(SUPPLY, 0);
    }

    function testFuzz_spenderCannotReuseApprovalForAnotherOwner(uint256 funded, uint256 requested) public {
        funded = bound(funded, 1, SUPPLY);
        requested = bound(requested, 1, funded);
        _send(holder, recipient, funded);
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, requested));
        vm.prank(spender);
        token.transferFrom(recipient, holder, requested);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(recipient, spender), 0);
        _assertBalances(SUPPLY - funded, funded);
    }

    function _approve(address owner, address delegate, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(delegate, amount));
    }

    function _send(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function _spend(address delegate, address from, address to, uint256 amount) private {
        vm.prank(delegate);
        assertTrue(token.transferFrom(from, to, amount));
    }

    function _assertBalances(uint256 holderBalance, uint256 recipientBalance) private view {
        assertEq(token.balanceOf(holder), holderBalance);
        assertEq(token.balanceOf(recipient), recipientBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
