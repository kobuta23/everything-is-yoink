// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {YoinkMaster} from "../src/YoinkMaster.sol";
import {YoinkFactory} from "../src/YoinkFactory.sol";
import {YoinkEscrowWrapper} from "../src/YoinkEscrowWrapper.sol";
import {YoinkEscrowPure} from "../src/YoinkEscrowPure.sol";
import {RateLimitHook} from "../src/hooks/RateLimitHook.sol";
import {SmartFlowRateHook} from "../src/hooks/SmartFlowRateHook.sol";
import {FeePullerHook} from "../src/hooks/FeePullerHook.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YoinkIntegrationTest is Test {
    YoinkMaster public yoinkMaster;
    YoinkFactory public factory;
    YoinkEscrowWrapper public escrowTemplateWrapper;
    YoinkEscrowPure public escrowTemplatePure;
    
    // Base mainnet addresses
    address public constant BASE_STREME = 0x3B3Cd21242BA44e9865B066e5EF5d1cC1030CC58; // STREME on Base
    address public constant BASE_USDCX = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx on Base
    address public constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    
    address public admin = address(1);
    address public yoinkAgent = address(2);
    address public flowRateAgent = address(3);
    address public treasury = address(4);
    address public recipient1 = address(5);
    address public recipient2 = address(6);
    address public recipient3 = address(7);
    address public positionManager = address(8);
    address public feeToken = address(9);
    
    ISuperToken public superToken;
    ISuperToken public wrapperSuperToken;
    IERC20 public underlyingToken;

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://base-mainnet.arpc.x.superfluid.dev");
        
        // Deploy escrow templates
        escrowTemplateWrapper = new YoinkEscrowWrapper();
        escrowTemplatePure = new YoinkEscrowPure();
        
        // Deploy YoinkMaster
        yoinkMaster = new YoinkMaster();
        
        // Deploy YoinkFactory
        factory = new YoinkFactory(
            address(yoinkMaster),
            address(escrowTemplateWrapper),
            address(escrowTemplatePure)
        );
        
        // Use STREME as our test SuperToken (pure superToken)
        superToken = ISuperToken(BASE_STREME);
        
        // Use USDCx as our wrapper superToken
        wrapperSuperToken = ISuperToken(BASE_USDCX);
        
        // Use USDC as underlying token
        underlyingToken = IERC20(BASE_USDC);
    }

    // ============ Full System Integration Tests ============
    
    function test_FullSystemDeployment() public {
        // Verify all contracts are deployed and configured
        assertEq(address(factory.yoinkMaster()), address(yoinkMaster));
        assertEq(factory.escrowTemplateWrapper(), address(escrowTemplateWrapper));
        assertEq(factory.escrowTemplatePure(), address(escrowTemplatePure));
        
        // Verify preset hooks are deployed
        assertTrue(factory.rateLimitHook() != address(0));
        assertTrue(factory.smartFlowRateHook() != address(0));
        assertTrue(factory.feePullerHook() != address(0));
    }

    function test_CompleteRateLimitedYoinkWorkflow() public {
        // 1. Create a rate limited yoink through factory
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://rate-limited-yoink"
        );
        
        assertTrue(escrowContract != address(0));
        assertEq(yoinkId, 1);
        
        // 2. Initialize the escrow contract
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        
        // 3. Fund the escrow
        uint256 fundingAmount = 10000;
        deal(address(superToken), address(escrow), fundingAmount);
        assertEq(escrow.getSuperTokenBalance(), fundingAmount);
        
        // 4. Start a stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(yoinkId, 100, recipient1);
        
        // 5. Verify stream is active and NFT is minted
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertTrue(yoinkData.isActive);
        assertEq(yoinkMaster.ownerOf(yoinkId), recipient1);
        
        // 6. Try to yoink immediately - should fail due to rate limit
        vm.prank(yoinkAgent);
        vm.expectRevert("Rate limited: 1 hour required");
        yoinkMaster.yoink(yoinkId, recipient2);
        
        // 7. Wait for rate limit to expire
        vm.warp(block.timestamp + 1 hours);
        
        // 8. Yoink to new recipient - should succeed
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(yoinkId, recipient2);
        
        // 9. Verify NFT ownership changed
        assertEq(yoinkMaster.ownerOf(yoinkId), recipient2);
        assertEq(yoinkMaster.balanceOf(recipient2), 1);
        assertEq(yoinkMaster.balanceOf(recipient1), 0);
        
        // 10. Stop the stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(yoinkId, 0, recipient2);
        
        // 11. Verify stream is inactive and NFT is burned
        yoinkData = yoinkMaster.getYoink(yoinkId);
        assertFalse(yoinkData.isActive);
        vm.expectRevert("ERC721: invalid token ID");
        yoinkMaster.ownerOf(yoinkId);
    }

    function test_CompleteSmartFlowRateYoinkWorkflow() public {
        // 1. Create a smart flow rate yoink
        (address escrowContract, uint256 yoinkId) = factory.createSmartFlowRateYoink(
            admin,
            yoinkAgent,
            superToken,
            "ipfs://smart-flow-yoink",
            30 days // Target duration
        );
        
        // 2. Initialize escrow and fund it
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        uint256 fundingAmount = 1000000; // 1M tokens
        deal(address(superToken), address(escrow), fundingAmount);
        
        // 3. Start a stream
        vm.prank(factory.smartFlowRateHook());
        yoinkMaster.setFlowRate(yoinkId, 100, recipient1);
        
        // 4. Verify hook is flow rate agent
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.flowRateAgent, factory.smartFlowRateHook());
        
        // 5. Check optimal flow rate calculation
        SmartFlowRateHook hook = SmartFlowRateHook(factory.smartFlowRateHook());
        int96 optimalRate = hook.getOptimalFlowRate(yoinkId);
        assertTrue(optimalRate > 0);
        
        // 6. Yoink to new recipient
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(yoinkId, recipient2);
        
        // 7. Verify hook can modulate flow rate
        vm.prank(factory.smartFlowRateHook());
        yoinkMaster.setFlowRate(yoinkId, optimalRate, recipient2);
    }

    function test_CompleteFeePullerYoinkWorkflow() public {
        // 1. Create a fee puller yoink
        (address escrowContract, uint256 yoinkId) = factory.createFeePullerYoink(
            admin,
            yoinkAgent,
            superToken,
            "ipfs://fee-puller-yoink",
            positionManager,
            feeToken,
            1000 // Min fee threshold
        );
        
        // 2. Initialize escrow
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        
        // 3. Start a stream
        vm.prank(factory.feePullerHook());
        yoinkMaster.setFlowRate(yoinkId, 100, recipient1);
        
        // 4. Mock fees in position manager
        uint256 feeAmount = 2000; // Above threshold
        deal(feeToken, positionManager, feeAmount);
        
        // 5. Yoink to trigger fee pulling
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(yoinkId, recipient2);
        
        // 6. Verify fees were pulled to escrow
        assertEq(IERC20(feeToken).balanceOf(address(escrow)), feeAmount);
    }

    function test_MultipleYoinksWithDifferentHooks() public {
        // Create multiple yoinks with different configurations
        
        // 1. Rate limited yoink
        (address escrow1, uint256 yoinkId1) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://yoink1"
        );
        
        // 2. Smart flow rate yoink
        (address escrow2, uint256 yoinkId2) = factory.createSmartFlowRateYoink(
            admin,
            yoinkAgent,
            superToken,
            "ipfs://yoink2",
            30 days
        );
        
        // 3. Fee puller yoink
        (address escrow3, uint256 yoinkId3) = factory.createFeePullerYoink(
            admin,
            yoinkAgent,
            superToken,
            "ipfs://yoink3",
            positionManager,
            feeToken,
            1000
        );
        
        // Initialize all escrows
        YoinkEscrowWrapper(escrow1).initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        YoinkEscrowWrapper(escrow2).initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        YoinkEscrowWrapper(escrow3).initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        
        // Fund escrows
        deal(address(superToken), escrow1, 10000);
        deal(address(superToken), escrow2, 10000);
        deal(address(superToken), escrow3, 10000);
        
        // Start streams
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(yoinkId1, 100, recipient1);
        
        vm.prank(factory.smartFlowRateHook());
        yoinkMaster.setFlowRate(yoinkId2, 100, recipient2);
        
        vm.prank(factory.feePullerHook());
        yoinkMaster.setFlowRate(yoinkId3, 100, recipient3);
        
        // Verify all streams are active
        assertTrue(yoinkMaster.getYoink(yoinkId1).isActive);
        assertTrue(yoinkMaster.getYoink(yoinkId2).isActive);
        assertTrue(yoinkMaster.getYoink(yoinkId3).isActive);
        
        // Verify NFTs are minted
        assertEq(yoinkMaster.ownerOf(yoinkId1), recipient1);
        assertEq(yoinkMaster.ownerOf(yoinkId2), recipient2);
        assertEq(yoinkMaster.ownerOf(yoinkId3), recipient3);
    }

    // Note: Factory only creates escrow-based yoinks now
    // For escrowless yoinks, users should call YoinkMaster directly

    function test_HookConfigurationUpdates() public {
        // Create a yoink
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://configurable"
        );
        
        // Update hook to smart flow rate hook
        vm.prank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.smartFlowRateHook());
        
        // Configure smart flow rate hook
        SmartFlowRateHook hook = SmartFlowRateHook(factory.smartFlowRateHook());
        hook.setTargetDuration(yoinkId, 60 days);
        
        // Verify configuration
        assertEq(yoinkMaster.getYoink(yoinkId).hook, factory.smartFlowRateHook());
        assertEq(hook.targetDurations(yoinkId), 60 days);
    }

    function test_EscrowWithdrawalIntegration() public {
        // Create yoink with escrow
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://withdrawal-test"
        );
        
        // Initialize and fund escrow
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        uint256 fundingAmount = 10000;
        deal(address(superToken), address(escrow), fundingAmount);
        
        // Start stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(yoinkId, 100, recipient1);
        
        // Withdraw from escrow
        vm.prank(address(yoinkMaster));
        escrow.withdrawAll(address(superToken));
        
        // Verify withdrawal
        assertEq(escrow.getSuperTokenBalance(), 0);
        assertEq(superToken.balanceOf(address(yoinkMaster)), fundingAmount);
    }

    // ============ Error Handling Integration Tests ============
    
    function test_IntegrationErrorHandling() public {
        // Test invalid operations across the system
        
        // 1. Try to yoink without active stream
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://error-test"
        );
        
        vm.prank(yoinkAgent);
        vm.expectRevert("Stream not active");
        yoinkMaster.yoink(yoinkId, recipient1);
        
        // 2. Try to set flow rate as non-flow rate agent
        vm.prank(recipient1);
        vm.expectRevert("Not flow rate agent");
        yoinkMaster.setFlowRate(yoinkId, 100, recipient1);
        
        // 3. Try to withdraw from escrow as non-owner
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        deal(address(superToken), address(escrow), 1000);
        
        vm.prank(recipient1);
        vm.expectRevert("YoinkDepositWrapper: caller is not the owner");
        escrow.withdrawAll(address(superToken));
    }

    // ============ Performance Integration Tests ============
    
    function test_MultipleYoinksPerformance() public {
        // Create many yoinks to test system performance
        uint256 numYoinks = 10;
        
        for (uint256 i = 0; i < numYoinks; i++) {
            factory.createRateLimitedYoink(
                admin,
                yoinkAgent,
                flowRateAgent,
                superToken,
                string(abi.encodePacked("ipfs://yoink-", vm.toString(i)))
            );
        }
        
        // Verify all yoinks were created
        for (uint256 i = 1; i <= numYoinks; i++) {
            YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(i);
            assertEq(yoinkData.admin, admin);
            assertEq(yoinkData.yoinkAgent, yoinkAgent);
            assertEq(yoinkData.flowRateAgent, flowRateAgent);
        }
    }

    // ============ Fuzz Integration Tests ============
    
    function testFuzz_IntegrationWorkflow(uint256 fundingAmount, uint256 flowRate) public {
        vm.assume(fundingAmount > 0 && fundingAmount <= type(uint128).max);
        vm.assume(flowRate > 0 && flowRate <= type(uint96).max);
        
        // Create yoink
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://fuzz-test"
        );
        
        // Initialize and fund escrow
        YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
        escrow.initialize(address(yoinkMaster), address(yoinkMaster), superToken, address(0x123)); // Mock underlying token
        deal(address(superToken), address(escrow), fundingAmount);
        
        // Start stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(yoinkId, int96(uint96(flowRate)), recipient1);
        
        // Wait and yoink
        vm.warp(block.timestamp + 1 hours);
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(yoinkId, recipient2);
        
        // Verify yoink succeeded
        assertEq(yoinkMaster.ownerOf(yoinkId), recipient2);
    }
}
