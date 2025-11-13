// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BatchSwapper} from "../contracts/BatchSwapper.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract BatchSwapperTest is Test {
    BatchSwapper internal swapper;
    MockERC20 internal tokenA; // fromToken
    MockERC20 internal tokenB; // toToken

    address Lumy = address(0xLUMY);
    address Monx   = address(0xMONX);
    address owner = address(this);

    function setUp() public {
        // Ahora entendí. Los tokens pueden tenes estándar 18 o no. USDC x ej tiene 6.
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 6);

        swapper = new BatchSwapper(address(tokenA), address(tokenB));

        // Mint de A para usuarios
        tokenA.mint(Lumy, 1_000e18);
        tokenA.mint(Monx,   1_000e18);
    }

    function _approve(address user, uint256 amt) internal {
        vm.startPrank(user);
        tokenA.approve(address(swapper), amt);
        vm.stopPrank();
    }
    
    function test_Provide_And_Refund_BeforeSwap() public {
        _approve(Lumy, type(uint256).max);

        vm.startPrank(Lumy);
        swapper.provide(100e18);
        (uint256 fromDeposited, ) = swapper.accounts(Lumy);
        assertEq(fromDeposited, 100e18);
        assertEq(swapper.totalFrom(), 100e18);

        // refund 
        swapper.withdraw(40e18);
        (fromDeposited, ) = swapper.accounts(Lumy);
        assertEq(fromDeposited, 60e18);
        assertEq(swapper.totalFrom(), 60e18);
        vm.stopPrank();
    }

    function test_Swap_And_Withdraw_All_Once() public {
        
        _approve(Lumy, type(uint256).max);
        _approve(Monx,   type(uint256).max);

        vm.prank(Lumy);
        swapper.provide(100e18);
        vm.prank(Monx);
        swapper.provide(50e18);

        
        uint256 expectedTo = 150e6;

        // Owner prefondea B (usando el mock)
        tokenB.mint(address(this), expectedTo);
        tokenB.approve(address(swapper), expectedTo);
        swapper.prefundToToken(expectedTo);

        // swap
        swapper.swap();

        // lumy cobra todo de una 
        vm.prank(Lumy);
        swapper.withdraw(0);
        assertEq(tokenB.balanceOf(Lumy), 100e6);

        // Monx cobra TODO de una (50e6 B)
        vm.prank(Monx);
        swapper.withdraw(0);
        assertEq(tokenB.balanceOf(Monx), 50e6);

        // Reintentos deben fallar
        vm.prank(Lumy);
        vm.expectRevert(bytes("Ya reclamaste todo"));
        swapper.withdraw(0);
    }

    function test_Revert_Swap_Without_Prefund() public {
        _approve(Lumy, type(uint256).max);
        vm.prank(Lumy);
        swapper.provide(10e18);

        // No fondeamos B y swap debe revertir
        vm.expectRevert();
        swapper.swap();
    }

    function test_Cannot_Provide_After_Swap() public {
        _approve(Lumy, type(uint256).max);
        vm.prank(Lumy);
        swapper.provide(10e18);

        tokenB.mint(address(this), 10e6);
        tokenB.approve(address(swapper), 10e6);
        swapper.prefundToToken(10e6);

        // swap
        swapper.swap();

        // Intentar provide post-swap → revert por onlyCollecting
        vm.prank(Monx);
        tokenA.approve(address(swapper), 1e18);
        vm.expectRevert(); // "No collect"
        swapper.provide(1e18);
    }
}
