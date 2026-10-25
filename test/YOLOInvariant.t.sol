// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {YOLO} from "../src/YOLO.sol";

/// @dev The model tracks all possible holders and allowances independently of token storage.
contract YOLOHandler is Test {
    YOLO private immutable token;
    address[4] private actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(YOLO token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 250_000_000 * 10 ** 18;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maximum = allowed < expectedBalance[owner] ? allowed : expectedBalance[owner];
        amount = bound(amount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
    }

    function attemptOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    /// @dev Explicitly reaches revocation and both sides of the infinite-approval sentinel.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        mode %= 4;
        uint256 amount;
        if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else if (mode == 3) amount = expectedBalance[actors[ownerSeed % actors.length]];
        approve(ownerSeed, spenderSeed, amount);
    }

    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) external {
        transfer(fromSeed, toSeed, expectedBalance[actors[fromSeed % actors.length]]);
    }

    /// @dev Check the intermediate movement too: two incorrect no-ops must not pass a round trip.
    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 beforeFrom = expectedBalance[from];
        uint256 beforeTo = expectedBalance[to];
        amount = bound(amount, 0, beforeFrom);
        transfer(fromSeed, toSeed, amount);
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
        transfer(toSeed, fromSeed, amount);
        assertEq(token.balanceOf(from), beforeFrom);
        assertEq(token.balanceOf(to), beforeTo);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approve(ownerSeed, spenderSeed, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
        // The global model must still match every balance and every allowance after rejection.
    }

    function attemptDelegatedOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        approve(ownerSeed, spenderSeed, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // In particular, a failed transfer must not consume the freshly granted finite approval.
    }

    function attemptAllowanceOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowed)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        allowed = bound(allowed, 0, expectedBalance[owner]);
        approve(ownerSeed, spenderSeed, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowed + 1);
    }

    function attemptInvalidRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 maximum = allowed < expectedBalance[owner] ? allowed : expectedBalance[owner];
        amount = bound(amount, 0, maximum);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract YOLOInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    YOLO private token;
    YOLOHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new YOLO();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
        }
        handler = new YOLOHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = YOLOHandler.transfer.selector;
        selectors[1] = YOLOHandler.approve.selector;
        selectors[2] = YOLOHandler.transferFrom.selector;
        selectors[3] = YOLOHandler.attemptOverspend.selector;
        selectors[4] = YOLOHandler.approveBoundary.selector;
        selectors[5] = YOLOHandler.transferEntireBalance.selector;
        selectors[6] = YOLOHandler.roundTrip.selector;
        selectors[7] = YOLOHandler.revokeAndAttemptSpend.selector;
        selectors[8] = YOLOHandler.attemptDelegatedOverspend.selector;
        selectors[9] = YOLOHandler.attemptAllowanceOverspend.selector;
        selectors[10] = YOLOHandler.attemptInvalidRecipient.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allowancesMatchApprovalsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    function invariant_metadataAndZeroAddressStateStayUnchanged() public view {
        assertEq(token.name(), "YOLO");
        assertEq(token.symbol(), "YOLO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    /// @dev Pins a productive lifecycle so it is covered independently of the random scheduler.
    function test_handlerLifecycleIncludesSpendingRevocationAndRollback() public {
        handler.approveBoundary(0, 1, 1);
        handler.transferFrom(0, 1, 2, 1);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max);
        assertEq(token.balanceOf(actors[2]), SUPPLY / 4 + 1);
        handler.revokeAndAttemptSpend(0, 1, 2);
        assertEq(token.allowance(actors[0], actors[1]), 0);

        handler.approveBoundary(0, 1, 2);
        handler.transferFrom(0, 1, 0, 1);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max - 2);
        handler.attemptInvalidRecipient(0, 1, 1);
        handler.attemptDelegatedOverspend(0, 1, 2, false);
        invariant_allowancesMatchApprovalsAndSpending();
        handler.attemptDelegatedOverspend(0, 1, 2, true);
        invariant_allowancesMatchApprovalsAndSpending();
        handler.attemptAllowanceOverspend(0, 1, 2, 1);

        handler.roundTrip(2, 3, 1);
        handler.transferEntireBalance(2, 3);
        assertEq(token.balanceOf(actors[2]), 0);
        handler.attemptOverspend(2, 2);
        handler.transfer(3, 2, 1);
        assertEq(token.balanceOf(actors[2]), 1);
        handler.approveBoundary(2, 3, 3);
        handler.transferFrom(2, 3, 3, 1);
        assertEq(token.balanceOf(actors[2]), 0);
        assertEq(token.allowance(actors[2], actors[3]), 0);

        invariant_supplyAndBalancesAreConserved();
        invariant_allowancesMatchApprovalsAndSpending();
        invariant_metadataAndZeroAddressStateStayUnchanged();
    }
}
