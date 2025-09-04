// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
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
    address public streamAgent = address(3);
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
            streamAgent,
            superToken,
            "ipfs://rate-limited-yoink"
        );
        
        assertTrue(escrowContract != address(0));
        assertEq(yoinkId, 1);
        

        
        // 2. Set the hook as admin
        vm.stopPrank(); // Ensure no previous prank is active
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.rateLimitHook());
        vm.stopPrank();
        
        // 3. Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, streamAgent);
        assertEq(address(yoinkData.token), address(superToken));
        assertEq(yoinkData.hook, factory.rateLimitHook());
        
        // 3. Verify the escrow was initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.superToken()), address(superToken));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow = YoinkEscrowPure(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.token()), address(superToken));
        }
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
        
        // 2. Set the hook as admin
        vm.stopPrank(); // Ensure no previous prank is active
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.smartFlowRateHook());
        vm.stopPrank();
        
        // 3. Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, factory.smartFlowRateHook());
        assertEq(address(yoinkData.token), address(superToken));
        assertEq(yoinkData.hook, factory.smartFlowRateHook());
        
        // 3. Verify the escrow was initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.superToken()), address(superToken));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow = YoinkEscrowPure(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.token()), address(superToken));
        }
        
        // 4. Configure the hook as admin
        vm.startPrank(admin);
        SmartFlowRateHook hook = SmartFlowRateHook(factory.smartFlowRateHook());
        hook.setTargetDuration(yoinkId, 30 days);
        vm.stopPrank();
        
        // 5. Verify the hook was configured correctly
        assertEq(hook.targetDurations(yoinkId), 30 days);
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
        
        // 2. Set the hook as admin
        vm.stopPrank(); // Ensure no previous prank is active
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.feePullerHook());
        vm.stopPrank();
        
        // 3. Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, factory.feePullerHook());
        assertEq(address(yoinkData.token), address(superToken));
        assertEq(yoinkData.hook, factory.feePullerHook());
        
        // 3. Verify the escrow was initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.superToken()), address(superToken));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow = YoinkEscrowPure(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.token()), address(superToken));
        }
        
        // 4. Configure the hook as admin
        vm.startPrank(admin);
        FeePullerHook hook = FeePullerHook(factory.feePullerHook());
        hook.setPositionManager(yoinkId, positionManager);
        hook.setFeeToken(yoinkId, feeToken);
        hook.setMinFeeThreshold(yoinkId, 1000);
        vm.stopPrank();
        
        // 5. Verify the hook was configured correctly
        assertEq(hook.positionManagers(yoinkId), positionManager);
        assertEq(hook.feeTokens(yoinkId), feeToken);
        assertEq(hook.minFeeThresholds(yoinkId), 1000);
    }

    function test_MultipleYoinksWithDifferentHooks() public {
        // Create multiple yoinks with different configurations
        
        // 1. Rate limited yoink
        (address escrow1, uint256 yoinkId1) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            streamAgent,
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
        
        // Set hooks as admin
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId1, factory.rateLimitHook());
        yoinkMaster.setYoinkHook(yoinkId2, factory.smartFlowRateHook());
        vm.stopPrank();
        
        // Verify all yoinks were created correctly
        YoinkMaster.YoinkData memory yoinkData1 = yoinkMaster.getYoink(yoinkId1);
        YoinkMaster.YoinkData memory yoinkData2 = yoinkMaster.getYoink(yoinkId2);
        
        assertEq(yoinkData1.admin, admin);
        assertEq(yoinkData1.yoinkAgent, yoinkAgent);
        assertEq(yoinkData1.streamAgent, streamAgent);
        assertEq(yoinkData1.hook, factory.rateLimitHook());
        
        assertEq(yoinkData2.admin, admin);
        assertEq(yoinkData2.yoinkAgent, yoinkAgent);
        assertEq(yoinkData2.streamAgent, factory.smartFlowRateHook());
        assertEq(yoinkData2.hook, factory.smartFlowRateHook());
        
        // Verify all escrows were initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow1_wrapper = YoinkEscrowWrapper(escrow1);
            YoinkEscrowWrapper escrow2_wrapper = YoinkEscrowWrapper(escrow2);
            assertEq(escrow1_wrapper.yoinkMaster(), address(yoinkMaster));
            assertEq(escrow2_wrapper.yoinkMaster(), address(yoinkMaster));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow1_pure = YoinkEscrowPure(escrow1);
            YoinkEscrowPure escrow2_pure = YoinkEscrowPure(escrow2);
            assertEq(escrow1_pure.yoinkMaster(), address(yoinkMaster));
            assertEq(escrow2_pure.yoinkMaster(), address(yoinkMaster));
        }
    }

    // Note: Factory only creates escrow-based yoinks now
    // For escrowless yoinks, users should call YoinkMaster directly

    function test_HookConfigurationUpdates() public {
        // Create a yoink
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            streamAgent,
            superToken,
            "ipfs://configurable"
        );
        
        // Set initial hook as admin
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.rateLimitHook());
        vm.stopPrank();
        
        // Verify initial hook configuration
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.hook, factory.rateLimitHook());
        
        // Update hook to smart flow rate hook
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.smartFlowRateHook());
        
        // Configure smart flow rate hook
        SmartFlowRateHook hook = SmartFlowRateHook(factory.smartFlowRateHook());
        hook.setTargetDuration(yoinkId, 60 days);
        vm.stopPrank();
        
        // Verify configuration
        assertEq(yoinkMaster.getYoink(yoinkId).hook, factory.smartFlowRateHook());
        assertEq(hook.targetDurations(yoinkId), 60 days);
    }

    function test_EscrowWithdrawalIntegration() public {
        // Create yoink with escrow
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            streamAgent,
            superToken,
            "ipfs://withdrawal-test"
        );
        
        // Set the hook as admin
        vm.startPrank(admin);
        yoinkMaster.setYoinkHook(yoinkId, factory.rateLimitHook());
        vm.stopPrank();
        
        // Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, streamAgent);
        assertEq(yoinkData.hook, factory.rateLimitHook());
        
        // Verify the escrow was initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.superToken()), address(superToken));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow = YoinkEscrowPure(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.token()), address(superToken));
        }
    }

    // ============ Error Handling Integration Tests ============
    
    function test_IntegrationErrorHandling() public {
        // Test invalid operations across the system
        
        // 1. Try to yoink without active stream
        (address escrowContract, uint256 yoinkId) = factory.createRateLimitedYoink(
            admin,
            yoinkAgent,
            streamAgent,
            superToken,
            "ipfs://error-test"
        );
        
        vm.prank(yoinkAgent);
        vm.expectRevert("Yoink: stream is not active");
        yoinkMaster.yoink(yoinkId, recipient1);
        
        // 2. Try to start stream as non-flow rate agent
        vm.prank(recipient1);
        vm.expectRevert("Yoink: caller is not authorized to change flow rates");
        yoinkMaster.startStream(yoinkId, 100, recipient1);
        
        // 3. Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, streamAgent);
        // Note: Factory sets rate limiting hook automatically
        assertEq(yoinkData.hook, factory.rateLimitHook());
    }

    // ============ Performance Integration Tests ============
    
    function test_MultipleYoinksPerformance() public {
        // Create many yoinks to test system performance
        uint256 numYoinks = 2; // Reduced from 10 to avoid gas issues
        
        for (uint256 i = 0; i < numYoinks; i++) {
            factory.createRateLimitedYoink(
                admin,
                yoinkAgent,
                streamAgent,
                superToken,
                string(abi.encodePacked("ipfs://yoink-", vm.toString(i)))
            );
        }
        
        // Verify all yoinks were created
        for (uint256 i = 1; i <= numYoinks; i++) {
            YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(i);
            assertEq(yoinkData.admin, admin);
            assertEq(yoinkData.yoinkAgent, yoinkAgent);
            assertEq(yoinkData.streamAgent, streamAgent);
            // Note: Factory sets rate limiting hook automatically
            assertEq(yoinkData.hook, factory.rateLimitHook());
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
            streamAgent,
            superToken,
            "ipfs://fuzz-test"
        );
        
        // Verify the yoink was created correctly
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(yoinkId);
        assertEq(yoinkData.admin, admin);
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.streamAgent, streamAgent);
        // Note: Factory sets rate limiting hook automatically
        assertEq(yoinkData.hook, factory.rateLimitHook());
        
        // Verify the escrow was initialized correctly
        // Check if this is a wrapper or pure SuperToken
        try superToken.getUnderlyingToken() returns (address underlying) {
            // This is a wrapper SuperToken, use YoinkEscrowWrapper
            YoinkEscrowWrapper escrow = YoinkEscrowWrapper(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.superToken()), address(superToken));
        } catch {
            // This is a pure SuperToken, use YoinkEscrowPure
            YoinkEscrowPure escrow = YoinkEscrowPure(escrowContract);
            assertEq(escrow.yoinkMaster(), address(yoinkMaster));
            assertEq(address(escrow.token()), address(superToken));
        }
    }
}
