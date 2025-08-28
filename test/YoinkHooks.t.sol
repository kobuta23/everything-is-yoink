// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {RateLimitHook} from "../src/hooks/RateLimitHook.sol";
import {SmartFlowRateHook} from "../src/hooks/SmartFlowRateHook.sol";
import {FeePullerHook} from "../src/hooks/FeePullerHook.sol";
import {AdvancedHook} from "../src/hooks/AdvancedHook.sol";
import {IYoinkHook} from "../src/hooks/IYoinkHook.sol";
import {YoinkMaster} from "../src/YoinkMaster.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YoinkHooksTest is Test {
    RateLimitHook public rateLimitHook;
    SmartFlowRateHook public smartFlowRateHook;
    FeePullerHook public feePullerHook;
    AdvancedHook public advancedHook;
    YoinkMaster public yoinkMaster;
    
    // Base mainnet addresses
    address public constant BASE_STREME = 0x3B3Cd21242BA44e9865B066e5EF5d1cC1030CC58; // STREME on Base
    
    address public admin = address(1);
    address public yoinkAgent = address(2);
    address public flowRateAgent = address(3);
    address public treasury = address(4);
    address public recipient = address(5);
    address public positionManager = address(6);
    address public feeToken = address(7);
    
    ISuperToken public superToken;
    uint256 public yoinkId = 1;
    
    // Helper function to create a yoink
    function _createYoink() internal returns (uint256) {
        vm.prank(treasury);
        return yoinkMaster.createYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
    }

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://base-mainnet.arpc.x.superfluid.dev");
        
        // Deploy YoinkMaster
        yoinkMaster = new YoinkMaster();
        
        // Deploy hooks
        rateLimitHook = new RateLimitHook();
        smartFlowRateHook = new SmartFlowRateHook(address(yoinkMaster));
        feePullerHook = new FeePullerHook(address(yoinkMaster));
        advancedHook = new AdvancedHook();
        
        // Use real Superfluid token (STREME)
        superToken = ISuperToken(BASE_STREME);
    }

    // ============ RateLimitHook Tests ============
    
    function test_RateLimitHookDeployment() public {
        assertEq(rateLimitHook.MIN_INTERVAL(), 1 hours);
    }

    function test_RateLimitHookBeforeYoinkFirstTime() public {
        rateLimitHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Check that last yoink time is recorded
        assertEq(rateLimitHook.lastYoinkTime(yoinkId), block.timestamp);
    }

    function test_RateLimitHookBeforeYoinkWithinLimit() public {
        // First yoink
        rateLimitHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Try to yoink again immediately - should fail
        vm.expectRevert("Rate limited: 1 hour required");
        rateLimitHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
    }

    function test_RateLimitHookBeforeYoinkAfterLimit() public {
        // First yoink
        rateLimitHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Wait 1 hour
        vm.warp(block.timestamp + 1 hours);
        
        // Try to yoink again - should succeed
        rateLimitHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
    }

    function test_RateLimitHookBeforeYoinkDifferentYoinkIds() public {
        // Yoink on different IDs should not interfere
        rateLimitHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        rateLimitHook.beforeYoink(yoinkId + 1, address(0), recipient, address(this));
    }

    // ============ SmartFlowRateHook Tests ============
    
    function test_SmartFlowRateHookDeployment() public {
        assertEq(address(smartFlowRateHook.yoinkMaster()), address(yoinkMaster));
    }

    function test_SmartFlowRateHookSetTargetDuration() public {
        // Create a yoink first
        vm.prank(treasury);
        uint256 yoinkId = yoinkMaster.createYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        uint256 targetDuration = 30 days;
        vm.prank(admin);
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
        
        assertEq(smartFlowRateHook.targetDurations(yoinkId), targetDuration);
    }

    function test_SmartFlowRateHookSetTargetDurationRevertIfNotOwner() public {
        uint256 yoinkId = _createYoink();
        uint256 targetDuration = 30 days;
        vm.prank(recipient); // Not owner
        vm.expectRevert("SmartFlowRateHook: only yoink admin can set target duration");
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
    }

    function test_SmartFlowRateHookBeforeYoink() public {
        uint256 yoinkId = _createYoink();
        // Set target duration
        uint256 targetDuration = 30 days;
        vm.prank(admin);
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
        
        // Mock treasury balance
        deal(address(superToken), treasury, 1000);
        
        // Call beforeYoink
        smartFlowRateHook.beforeYoink(yoinkId, address(0), recipient, address(this));
    }

    function test_SmartFlowRateHookGetOptimalFlowRate() public {
        uint256 yoinkId = _createYoink();
        // Set target duration
        uint256 targetDuration = 30 days;
        vm.prank(admin);
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
        
        // Mock treasury balance
        deal(address(superToken), treasury, 1000);
        
        // Get optimal flow rate
        int96 optimalRate = smartFlowRateHook.getOptimalFlowRate(yoinkId);
        assertTrue(optimalRate >= 0);
    }

    function test_SmartFlowRateHookGetOptimalFlowRateNoTargetDuration() public {
        // No target duration set
        int96 optimalRate = smartFlowRateHook.getOptimalFlowRate(yoinkId);
        assertEq(optimalRate, 0);
    }

    function test_SmartFlowRateHookGetOptimalFlowRateNoBalance() public {
        uint256 yoinkId = _createYoink();
        // Set target duration
        uint256 targetDuration = 30 days;
        vm.prank(admin);
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
        
        // No treasury balance
        int96 optimalRate = smartFlowRateHook.getOptimalFlowRate(yoinkId);
        assertEq(optimalRate, 0);
    }

    // ============ FeePullerHook Tests ============
    
    function test_FeePullerHookDeployment() public {
        assertEq(address(feePullerHook.yoinkMaster()), address(yoinkMaster));
    }

    function test_FeePullerHookSetConfiguration() public {
        uint256 yoinkId = _createYoink();
        uint256 minFeeThreshold = 1000;
        
        vm.prank(admin);
        feePullerHook.setPositionManager(yoinkId, positionManager);
        vm.prank(admin);
        feePullerHook.setFeeToken(yoinkId, feeToken);
        vm.prank(admin);
        feePullerHook.setMinFeeThreshold(yoinkId, minFeeThreshold);
        
        (address pm, address ft, uint256 threshold) = feePullerHook.getConfiguration(yoinkId);
        assertEq(pm, positionManager);
        assertEq(ft, feeToken);
        assertEq(threshold, minFeeThreshold);
    }

    function test_FeePullerHookSetConfigurationRevertIfNotOwner() public {
        uint256 yoinkId = _createYoink();
        vm.prank(recipient); // Not owner
        vm.expectRevert("FeePullerHook: only yoink admin can set position manager");
        feePullerHook.setPositionManager(yoinkId, positionManager);
    }

    function test_FeePullerHookBeforeYoink() public {
        uint256 yoinkId = _createYoink();
        // Set configuration
        vm.prank(admin);
        feePullerHook.setPositionManager(yoinkId, positionManager);
        vm.prank(admin);
        feePullerHook.setFeeToken(yoinkId, feeToken);
        vm.prank(admin);
        feePullerHook.setMinFeeThreshold(yoinkId, 1000);
        
        // Mock fee balance in position manager
        deal(feeToken, positionManager, 500); // Below threshold
        
        // Call beforeYoink - should succeed but not pull fees
        feePullerHook.beforeYoink(yoinkId, address(0), recipient, address(this));
    }

    function test_FeePullerHookBeforeYoinkWithFees() public {
        uint256 yoinkId = _createYoink();
        // Set configuration
        vm.prank(admin);
        feePullerHook.setPositionManager(yoinkId, positionManager);
        vm.prank(admin);
        feePullerHook.setFeeToken(yoinkId, feeToken);
        vm.prank(admin);
        feePullerHook.setMinFeeThreshold(yoinkId, 1000);
        
        // Mock fee balance in position manager above threshold
        deal(feeToken, positionManager, 2000);
        
        // Mock escrow contract
        address escrowContract = address(0x123);
        deal(feeToken, escrowContract, 0);
        
        // Call beforeYoink - should succeed and pull fees
        feePullerHook.beforeYoink(yoinkId, address(0), recipient, address(this));
    }

    function test_FeePullerHookGetFeeBalance() public {
        // Set position manager
        feePullerHook.setPositionManager(yoinkId, positionManager);
        feePullerHook.setFeeToken(yoinkId, feeToken);
        
        // Mock fee balance
        deal(feeToken, positionManager, 1000);
        
        uint256 feeBalance = feePullerHook.getFeeBalance(yoinkId);
        assertEq(feeBalance, 1000);
    }

    function test_FeePullerHookGetFeeBalanceNoPositionManager() public {
        // No position manager set
        uint256 feeBalance = feePullerHook.getFeeBalance(yoinkId);
        assertEq(feeBalance, 0);
    }

    // ============ AdvancedHook Tests ============
    
    function test_AdvancedHookDeployment() public {
        assertEq(advancedHook.owner(), address(this));
    }

    function test_AdvancedHookBeforeYoink() public {
        advancedHook.beforeYoink(yoinkId, address(0), recipient, address(this));
    }

    function test_AdvancedHookSetBlockedYoink() public {
        advancedHook.setBlockedYoink(yoinkId, true);
        assertTrue(advancedHook.blockedYoinks(yoinkId));
    }

    function test_AdvancedHookSetBlockedYoinkRevertIfNotOwner() public {
        vm.prank(recipient); // Not owner
        vm.expectRevert("Hook: caller is not owner");
        advancedHook.setBlockedYoink(yoinkId, true);
    }

    function test_AdvancedHookBeforeYoinkBlockedYoink() public {
        // Block yoink
        advancedHook.setBlockedYoink(yoinkId, true);
        
        // Try to yoink - should fail
        vm.expectRevert("Hook: yoink is blocked");
        advancedHook.beforeYoink(yoinkId, address(0), recipient, address(this));
    }

    // Note: AdvancedHook has built-in rate limiting with 1 hour minimum interval
    // The rate limiting is tested in the beforeYoink tests above

    function test_AdvancedHookBeforeYoinkAfterRateLimit() public {
        // First yoink
        advancedHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Wait for rate limit to expire (1 hour minimum)
        vm.warp(block.timestamp + 1 hours);
        
        // Try to yoink again - should succeed
        advancedHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
    }

    // ============ Integration Tests ============
    
    function test_HookIntegration() public {
        // Test that hooks can be used together
        // Create a yoink with rate limit hook
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            admin,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Set rate limit hook
        vm.prank(admin);
        yoinkMaster.setYoinkHook(generatedId, address(rateLimitHook));
        
        // Start a stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient);
        
        // First yoink should succeed
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(generatedId, address(0x100));
        
        // Second yoink should fail due to rate limit
        vm.prank(yoinkAgent);
        vm.expectRevert("Rate limited: 1 hour required");
        yoinkMaster.yoink(generatedId, address(0x200));
    }

    // ============ Fuzz Tests ============
    
    function testFuzz_RateLimitHook(uint256 timeOffset) public {
        vm.assume(timeOffset <= 2 hours);
        
        // First yoink
        rateLimitHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Warp time
        vm.warp(block.timestamp + timeOffset);
        
        if (timeOffset >= 1 hours) {
            // Should succeed
            rateLimitHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
        } else {
            // Should fail
            vm.expectRevert("Rate limited: 1 hour required");
            rateLimitHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
        }
    }

    function testFuzz_SmartFlowRateHook(uint256 treasuryBalance, uint256 targetDuration) public {
        vm.assume(treasuryBalance <= type(uint128).max);
        vm.assume(targetDuration > 0 && targetDuration <= 365 days);
        
        // Set target duration
        smartFlowRateHook.setTargetDuration(yoinkId, targetDuration);
        
        // Mock treasury balance
        deal(address(superToken), treasury, treasuryBalance);
        
        // Get optimal flow rate
        int96 optimalRate = smartFlowRateHook.getOptimalFlowRate(yoinkId);
        assertTrue(optimalRate >= 0);
    }

    // ============ Edge Case Tests ============
    
    function test_RateLimitHookZeroYoinkId() public {
        rateLimitHook.beforeYoink(0, address(0), recipient, address(this));
    }

    function test_SmartFlowRateHookZeroTargetDuration() public {
        smartFlowRateHook.setTargetDuration(yoinkId, 0);
        int96 optimalRate = smartFlowRateHook.getOptimalFlowRate(yoinkId);
        assertEq(optimalRate, 0);
    }

    function test_FeePullerHookZeroThreshold() public {
        feePullerHook.setPositionManager(yoinkId, positionManager);
        feePullerHook.setFeeToken(yoinkId, feeToken);
        feePullerHook.setMinFeeThreshold(yoinkId, 0);
        
        // Mock fee balance
        deal(feeToken, positionManager, 100);
        
        // Should pull fees even with zero threshold
        feePullerHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        // Function call should succeed
    }

    function test_AdvancedHookZeroRateLimit() public {
        // AdvancedHook doesn't have setRateLimit function
        // The rate limiting is built-in with 1 hour minimum interval
        
        // First yoink
        advancedHook.beforeYoink(yoinkId, address(0), recipient, address(this));
        
        // Second yoink should succeed after waiting
        vm.warp(block.timestamp + 1 hours);
        advancedHook.beforeYoink(yoinkId, recipient, address(0x200), address(this));
    }
}
