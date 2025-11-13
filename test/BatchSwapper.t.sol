// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BatchSwapper} from "../contracts/BatchSwapper.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract BatchSwapperTest is Test {
    BatchSwapper internal swapper;
    MockERC20 internal tokenA; // fromToken
    MockERC20 internal tokenB; // toToken

    address alice = address(0xA11CE);
    address bob   = address(0xB0B);
    address owner = address(this);

    function setUp() public {
        // A: 18 dec (como DAI), B: 6 dec (como USDC), para testear conversión 1:1 con decimales distintos
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 6);

        swapper = new BatchSwapper(address(tokenA), address(tokenB));

        // Mint de A para usuarios
        tokenA.mint(alice, 1_000e18);
        tokenA.mint(bob,   1_000e18);
    }

    function _approve(address user, uint256 amt) internal {
        vm.startPrank(user);
        tokenA.approve(address(swapper), amt);
        vm.stopPrank();
    }

    function test_Provide_And_Refund_BeforeSwap() public {
        _approve(alice, type(uint256).max);

        vm.startPrank(alice);
        swapper.provide(100e18);
        (uint256 fromDeposited, ) = swapper.accounts(alice);
        assertEq(fromDeposited, 100e18);
        assertEq(swapper.totalFrom(), 100e18);

        // refund 40
        swapper.withdraw(40e18);
        (fromDeposited, ) = swapper.accounts(alice);
        assertEq(fromDeposited, 60e18);
        assertEq(swapper.totalFrom(), 60e18);
        vm.stopPrank();
    }

    function test_Swap_And_Withdraw_All_Once() public {
        // Alice 100 A, Bob 50 A
        _approve(alice, type(uint256).max);
        _approve(bob,   type(uint256).max);

        vm.prank(alice);
        swapper.provide(100e18);
        vm.prank(bob);
        swapper.provide(50e18);

        // totalFrom = 150e18 A → expectedTo en B (6 dec) = 150e6
        uint256 expectedTo = 150e6;

        // Owner prefondea B (usando el mock)
        tokenB.mint(address(this), expectedTo);
        tokenB.approve(address(swapper), expectedTo);
        swapper.prefundToToken(expectedTo);

        // swap
        swapper.swap();

        // Alice cobra TODO de una (100e6 B)
        vm.prank(alice);
        swapper.withdraw(0);
        assertEq(tokenB.balanceOf(alice), 100e6);

        // Bob cobra TODO de una (50e6 B)
        vm.prank(bob);
        swapper.withdraw(0);
        assertEq(tokenB.balanceOf(bob), 50e6);

        // Reintentos deben fallar
        vm.prank(alice);
        vm.expectRevert(bytes("Ya reclamaste todo"));
        swapper.withdraw(0);
    }

    function test_Revert_Swap_Without_Prefund() public {
        _approve(alice, type(uint256).max);
        vm.prank(alice);
        swapper.provide(10e18);

        // No fondeamos B → swap debe revertir
        vm.expectRevert(); // mensaje genérico; si querés, hacé match exacto
        swapper.swap();
    }

    function test_Cannot_Provide_After_Swap() public {
        _approve(alice, type(uint256).max);
        vm.prank(alice);
        swapper.provide(10e18);

        // Prefund correcto
        tokenB.mint(address(this), 10e6);
        tokenB.approve(address(swapper), 10e6);
        swapper.prefundToToken(10e6);

        // swap
        swapper.swap();

        // Intentar provide post-swap → revert por onlyCollecting
        vm.prank(bob);
        tokenA.approve(address(swapper), 1e18);
        vm.expectRevert(); // "No collect"
        swapper.provide(1e18);
    }
}
