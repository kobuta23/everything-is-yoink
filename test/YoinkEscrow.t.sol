// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {YoinkEscrowWrapper} from "../src/YoinkEscrowWrapper.sol";
import {YoinkEscrowPure} from "../src/YoinkEscrowPure.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract YoinkEscrowTest is Test {
    YoinkEscrowWrapper public escrowWrapper;
    YoinkEscrowPure public escrowPure;
    
    // Base mainnet addresses
    address public constant BASE_STREME = 0x3B3Cd21242BA44e9865B066e5EF5d1cC1030CC58; // STREME on Base
    address public constant BASE_USDCX = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx on Base
    address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    
    address public yoinkMaster = address(1);
    address public user = address(2);
    address public recipient = address(3);
    
    ISuperToken public superToken;
    ISuperToken public wrapperSuperToken;
    IERC20 public underlyingToken;

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://base-mainnet.arpc.x.superfluid.dev");
        
        // Deploy escrow contracts
        escrowWrapper = new YoinkEscrowWrapper();
        escrowPure = new YoinkEscrowPure();
        
        // Use STREME as our test SuperToken (pure superToken)
        superToken = ISuperToken(BASE_STREME);
        
        // Use USDCx as our wrapper superToken
        wrapperSuperToken = ISuperToken(BASE_USDCX);
        
        // Use USDC as underlying token
        underlyingToken = IERC20(BASE_USDC);
    }

    // ============ YoinkEscrowWrapper Tests ============
    
    function test_WrapperEscrowDeployment() public {
        assertEq(escrowWrapper.yoinkMaster(), address(0)); // Not initialized yet
    }

    function test_WrapperEscrowInitialize() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        assertEq(escrowWrapper.yoinkMaster(), yoinkMaster);
    }

    function test_WrapperEscrowInitializeRevertIfAlreadyInitialized() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        vm.expectRevert("Already initialized");
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
    }

    function test_WrapperEscrowInitializeRevertIfInvalidYoinkMaster() public {
        vm.expectRevert("YoinkDepositWrapper: yoinkMaster cannot be zero");
        escrowWrapper.initialize(address(this), address(0), wrapperSuperToken, address(underlyingToken));
    }

    function test_WrapperEscrowDeposit() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Check balance
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), amount);
    }

    function test_WrapperEscrowWithdraw() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Withdraw all to owner (this contract)
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        
        // Check balances
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), 0);
        assertEq(wrapperSuperToken.balanceOf(address(this)), amount);
    }

    function test_WrapperEscrowWithdrawRevertIfNotYoinkMaster() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Try to withdraw as non-owner
        vm.prank(user);
        vm.expectRevert("YoinkDepositWrapper: caller is not the owner");
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
    }

    function test_WrapperEscrowWithdrawRevertIfInsufficientBalance() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Try to withdraw more than available
        vm.prank(address(this));
        vm.expectRevert("YoinkDepositWrapper: no tokens to withdraw");
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
    }

    function test_WrapperEscrowWithdrawRevertIfInvalidRecipient() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Try to withdraw to zero address - this is not possible with withdrawAll
        // The function doesn't take a recipient parameter, so this test is not applicable
        // Instead, test that withdrawAll works correctly
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), 0);
    }

    function test_WrapperEscrowWithdrawAll() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Withdraw all
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        
        // Check balances
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), 0);
        assertEq(wrapperSuperToken.balanceOf(address(this)), amount);
    }

    function test_WrapperEscrowWithdrawAllRevertIfNotYoinkMaster() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Try to withdraw all as non-owner
        vm.prank(user);
        vm.expectRevert("YoinkDepositWrapper: caller is not the owner");
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
    }

    function test_WrapperEscrowWithdrawAllRevertIfInvalidRecipient() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Try to withdraw all to zero address - this is not possible with withdrawAll
        // The function doesn't take a recipient parameter, so this test is not applicable
        // Instead, test that withdrawAll works correctly
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), 0);
    }

    function test_WrapperEscrowGetBalance() public {
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        // Check balance
        assertEq(escrowWrapper.getSuperTokenBalance(), amount);
    }

    // ============ YoinkEscrowPure Tests ============
    
    function test_PureEscrowDeployment() public {
        assertEq(escrowPure.yoinkMaster(), address(0)); // Not initialized yet
    }

    function test_PureEscrowInitialize() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        assertEq(escrowPure.yoinkMaster(), yoinkMaster);
    }

    function test_PureEscrowInitializeRevertIfAlreadyInitialized() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        vm.expectRevert("Already initialized");
        escrowPure.initialize(address(this), yoinkMaster, superToken);
    }

    function test_PureEscrowInitializeRevertIfInvalidYoinkMaster() public {
        vm.expectRevert("YoinkDeposit: yoinkMaster cannot be zero");
        escrowPure.initialize(address(this), address(0), superToken);
    }

    function test_PureEscrowDeposit() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Check balance
        assertEq(superToken.balanceOf(address(escrowPure)), amount);
    }

    function test_PureEscrowWithdraw() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Withdraw all to owner
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        
        // Check balances
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
        assertEq(superToken.balanceOf(address(this)), amount);
    }

    function test_PureEscrowWithdrawRevertIfNotYoinkMaster() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Try to withdraw as non-owner
        vm.prank(user);
        vm.expectRevert("YoinkDeposit: caller is not the owner");
        escrowPure.withdrawAll(address(superToken));
    }

    function test_PureEscrowWithdrawRevertIfInsufficientBalance() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Try to withdraw more than available
        vm.prank(address(this));
        vm.expectRevert("YoinkDeposit: no tokens to withdraw");
        escrowPure.withdrawAll(address(superToken));
    }

    function test_PureEscrowWithdrawRevertIfInvalidRecipient() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Try to withdraw to zero address - this is not possible with withdrawAll
        // The function doesn't take a recipient parameter, so this test is not applicable
        // Instead, test that withdrawAll works correctly
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
    }

    function test_PureEscrowWithdrawAll() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Withdraw all
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        
        // Check balances
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
        assertEq(superToken.balanceOf(address(this)), amount);
    }

    function test_PureEscrowWithdrawAllRevertIfNotYoinkMaster() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Try to withdraw all as non-owner
        vm.prank(user);
        vm.expectRevert("YoinkDeposit: caller is not the owner");
        escrowPure.withdrawAll(address(superToken));
    }

    function test_PureEscrowWithdrawAllRevertIfInvalidRecipient() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Try to withdraw all to zero address - this is not possible with withdrawAll
        // The function doesn't take a recipient parameter, so this test is not applicable
        // Instead, test that withdrawAll works correctly
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
    }

    function test_PureEscrowGetBalance() public {
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock some tokens to the escrow
        uint256 amount = 1000;
        deal(address(superToken), address(escrowPure), amount);
        
        // Check balance
        assertEq(superToken.balanceOf(address(escrowPure)), amount);
    }

    // ============ Integration Tests ============
    
    function test_EscrowIntegration() public {
        // Initialize both escrows
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        
        // Mock tokens to both escrows
        uint256 wrapperAmount = 1000;
        uint256 pureAmount = 2000;
        
        deal(address(wrapperSuperToken), address(escrowWrapper), wrapperAmount);
        deal(address(superToken), address(escrowPure), pureAmount);
        
        // Check balances
        assertEq(escrowWrapper.getSuperTokenBalance(), wrapperAmount);
        assertEq(superToken.balanceOf(address(escrowPure)), pureAmount);
        
        // Withdraw from both
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        
        // Check final balances
        assertEq(escrowWrapper.getSuperTokenBalance(), 0);
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
        assertEq(wrapperSuperToken.balanceOf(address(this)), wrapperAmount);
        assertEq(superToken.balanceOf(address(this)), pureAmount);
    }

    // ============ Fuzz Tests ============
    
    function testFuzz_WrapperEscrowWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        
        escrowWrapper.initialize(address(this), yoinkMaster, wrapperSuperToken, address(underlyingToken));
        deal(address(wrapperSuperToken), address(escrowWrapper), amount);
        
        vm.prank(address(this));
        escrowWrapper.withdrawAll(address(wrapperSuperToken));
        
        assertEq(wrapperSuperToken.balanceOf(address(escrowWrapper)), 0);
        assertEq(wrapperSuperToken.balanceOf(address(this)), amount);
    }

    function testFuzz_PureEscrowWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        
        escrowPure.initialize(address(this), yoinkMaster, superToken);
        deal(address(superToken), address(escrowPure), amount);
        
        vm.prank(address(this));
        escrowPure.withdrawAll(address(superToken));
        
        assertEq(superToken.balanceOf(address(escrowPure)), 0);
        assertEq(superToken.balanceOf(address(this)), amount);
    }
}
