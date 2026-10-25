// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {YOLO} from "../src/YOLO.sol";

/// @dev Test fixture only. Models the factory's creation and outbound ERC-20 transfers.
contract TokenFactoryFixture {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (YOLO) {
        require(msg.sender == controller, "fixture controller only");
        return new YOLO{salt: salt}();
    }

    function move(YOLO token, address recipient, uint256 amount) external returns (bool) {
        require(msg.sender == controller, "fixture controller only");
        return token.transfer(recipient, amount);
    }
}

contract YOLOLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_create2MintsEverythingToImmediateFactory() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("YOLO factory deployment test");
        bytes32 deploymentHash =
            keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(YOLO).creationCode)));
        address predicted = address(uint160(uint256(deploymentHash)));

        YOLO token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
    }

    function test_launchTransfersClaimsAndTradingTransfersArriveWhole() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        YOLO token = factory.deploy(keccak256("YOLO flow test"));
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool custody fixture");
        address remainder = makeAddr("remainder fixture");
        address claimant = makeAddr("claimant fixture");
        address trader = makeAddr("trader fixture");

        assertTrue(factory.move(token, distributor, SUPPLY / 10));
        assertTrue(factory.move(token, pool, SUPPLY * 6 / 10));
        assertTrue(factory.move(token, remainder, SUPPLY * 3 / 10));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), SUPPLY / 10);
        assertEq(token.balanceOf(pool), SUPPLY * 6 / 10);
        assertEq(token.balanceOf(remainder), SUPPLY * 3 / 10);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, SUPPLY / 10));
        assertEq(token.balanceOf(claimant), SUPPLY / 10);
        assertEq(token.balanceOf(distributor), 0);

        // Exercises token movement in both directions, not AMM pricing or pool initialization.
        vm.prank(pool);
        assertTrue(token.transfer(trader, 1_000 ether));
        assertEq(token.balanceOf(trader), 1_000 ether);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 1_000 ether));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), SUPPLY * 6 / 10);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
