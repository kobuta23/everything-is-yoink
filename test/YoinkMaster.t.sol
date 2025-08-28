// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {YoinkMaster} from "../src/YoinkMaster.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YoinkMasterTest is Test {
    YoinkMaster public yoinkMaster;
    
    // Real Superfluid tokens on Base mainnet
    address public constant BASE_STREME = 0x3B3Cd21242BA44e9865B066e5EF5d1cC1030CC58; // STREME (pure superToken)
    address public constant BASE_USDCX = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx (wrapper superToken)
    
    address public treasury;
    address public owner = address(2);
    address public yoinkAgent = address(3);
    address public flowRateAgent = address(4);
    address public recipient1 = address(5);
    address public recipient2 = address(6);
    address public hook = address(7);
    
    ISuperToken public superToken; // Pure superToken (STREME)
    ISuperToken public wrapperSuperToken; // Wrapper superToken (USDCx)

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://base-mainnet.arpc.x.superfluid.dev");
        
        // Deploy YoinkMaster
        yoinkMaster = new YoinkMaster();
        
        // Use real Superfluid tokens
        superToken = ISuperToken(BASE_STREME); // Pure superToken
        wrapperSuperToken = ISuperToken(BASE_USDCX); // Wrapper superToken
        
        // Set treasury to this test contract
        treasury = address(this);
    }

    // ============ Creation Tests ============
    
    function test_CreateYoink() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        
        assertEq(yoinkData.treasury, treasury);
        assertEq(yoinkData.admin, owner);
        assertEq(address(yoinkData.token), address(superToken));
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.flowRateAgent, flowRateAgent);
        assertEq(yoinkData.hook, address(0)); // No hook by default
        assertFalse(yoinkData.isActive);
        
        // Check that NFT doesn't exist yet since no stream is active
        vm.expectRevert("ERC721: invalid token ID");
        yoinkMaster.ownerOf(generatedId);
        assertEq(yoinkMaster.balanceOf(owner), 0);
    }

    function test_CreateYoinkWithHook() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Set a hook
        vm.prank(owner);
        yoinkMaster.setYoinkHook(generatedId, hook);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertEq(yoinkData.hook, hook);
    }

    function test_CreateYoinkRevertIfInvalidOwner() public {
        vm.prank(treasury);
        vm.expectRevert();
        yoinkMaster.createYoink(
            address(0), // Invalid owner
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
    }

    function test_CreateYoinkRevertIfInvalidToken() public {
        vm.prank(treasury);
        vm.expectRevert();
        yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            ISuperToken(address(0)), // Invalid token
            "ipfs://test"
        );
    }

    // ============ Yoink Function Tests ============
    
    function test_Yoink() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Start a stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        // Yoink to new recipient
        vm.prank(yoinkAgent);
        yoinkMaster.yoink(generatedId, recipient2);
        
        // Check that NFT is now owned by new recipient
        assertEq(yoinkMaster.ownerOf(generatedId), recipient2);
        assertEq(yoinkMaster.balanceOf(recipient2), 1);
        assertEq(yoinkMaster.balanceOf(recipient1), 0);
    }

    function test_YoinkWithHook() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Set a hook that reverts
        vm.prank(owner);
        yoinkMaster.setYoinkHook(generatedId, address(this));
        
        // Start a stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        // Yoink should revert due to hook
        vm.prank(yoinkAgent);
        vm.expectRevert("Hook reverted");
        yoinkMaster.yoink(generatedId, recipient2);
    }

    function test_YoinkRevertIfNotYoinkAgent() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Start a stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        // Try to yoink as non-yoink agent
        vm.prank(recipient1);
        vm.expectRevert("Yoink: caller is not the yoink agent");
        yoinkMaster.yoink(generatedId, recipient2);
    }

    function test_YoinkRevertIfStreamNotActive() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Try to yoink without active stream
        vm.prank(yoinkAgent);
        vm.expectRevert("Yoink: stream is not active");
        yoinkMaster.yoink(generatedId, recipient2);
    }

    // ============ Flow Rate Tests ============
    
    function test_SetFlowRateStartStream() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Set flow rate and start stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertTrue(yoinkData.isActive);
        
        // Check that NFT is minted to recipient
        assertEq(yoinkMaster.ownerOf(generatedId), recipient1);
        assertEq(yoinkMaster.balanceOf(recipient1), 1);
    }

    function test_SetFlowRateUpdateStream() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Start stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        // Update flow rate
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 200, recipient1);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertTrue(yoinkData.isActive);
    }

    function test_SetFlowRateStopStream() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        // Start stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
        
        // Stop stream
        vm.prank(flowRateAgent);
        yoinkMaster.setFlowRate(generatedId, 0, recipient1);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertFalse(yoinkData.isActive);
        
        // Check that NFT is burned
        vm.expectRevert("ERC721: invalid token ID");
        yoinkMaster.ownerOf(generatedId);
        assertEq(yoinkMaster.balanceOf(recipient1), 0);
    }

    function test_SetFlowRateRevertIfNotFlowRateAgent() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Try to set flow rate as non-flow rate agent
        vm.prank(recipient1);
        vm.expectRevert("Yoink: caller is not authorized to change flow rates");
        yoinkMaster.setFlowRate(generatedId, 100, recipient1);
    }

    // ============ Agent Management Tests ============
    
    function test_SetYoinkAgent() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        address newAgent = address(99);
        vm.prank(owner);
        yoinkMaster.setYoinkAgent(generatedId, newAgent);
        
        assertTrue(yoinkMaster.isYoinkAgent(generatedId, newAgent));
        assertFalse(yoinkMaster.isYoinkAgent(generatedId, yoinkAgent));
    }

    function test_SetFlowRateAgent() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        address newAgent = address(99);
        vm.prank(owner);
        yoinkMaster.setFlowRateAgent(generatedId, newAgent);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertEq(yoinkData.flowRateAgent, newAgent);
    }

    function test_SetYoinkAgentRevertIfNotOwner() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        address newAgent = address(99);
        vm.prank(recipient1); // Not owner
        vm.expectRevert("Yoink: caller is not the yoink admin");
        yoinkMaster.setYoinkAgent(generatedId, newAgent);
    }

    function test_SetFlowRateAgentRevertIfNotOwner() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        address newAgent = address(99);
        vm.prank(recipient1); // Not owner
        vm.expectRevert("Yoink: caller is not the yoink admin");
        yoinkMaster.setFlowRateAgent(generatedId, newAgent);
    }

    // ============ Hook Management Tests ============
    
    function test_SetYoinkHook() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        vm.prank(owner);
        yoinkMaster.setYoinkHook(generatedId, hook);
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertEq(yoinkData.hook, hook);
    }

    function test_RemoveYoinkHook() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Set hook
        vm.prank(owner);
        yoinkMaster.setYoinkHook(generatedId, hook);
        
        // Remove hook
        vm.prank(owner);
        yoinkMaster.setYoinkHook(generatedId, address(0));
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertEq(yoinkData.hook, address(0));
    }

    function test_SetYoinkHookRevertIfNotOwner() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        vm.prank(recipient1); // Not owner
        vm.expectRevert("Yoink: caller is not the yoink admin");
        yoinkMaster.setYoinkHook(generatedId, hook);
    }

    // ============ Treasury Management Tests ============
    
    // Note: Treasury is immutable and cannot be updated after creation

    function test_GetTreasuryBalance() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        // Fund treasury with tokens
        uint256 fundingAmount = 1000000;
        deal(address(superToken), treasury, fundingAmount);
        
        uint256 balance = yoinkMaster.getTreasuryBalance(generatedId);
        assertEq(balance, fundingAmount);
    }

    // ============ View Function Tests ============
    
    function test_GetYoink() public {
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            owner,
            yoinkAgent,
            flowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        
        assertEq(yoinkData.treasury, treasury);
        assertEq(yoinkData.admin, owner);
        assertEq(address(yoinkData.token), address(superToken));
        assertEq(yoinkData.yoinkAgent, yoinkAgent);
        assertEq(yoinkData.flowRateAgent, flowRateAgent);
        assertEq(yoinkData.hook, address(0));
        assertFalse(yoinkData.isActive);
    }

    function test_GetYoinkRevertIfNotExists() public {
        vm.expectRevert("Yoink: yoink does not exist");
        yoinkMaster.getYoink(999);
    }

    // ============ Fuzz Tests ============
    
    function testFuzz_CreateYoink(address testOwner, address testYoinkAgent, address testFlowRateAgent) public {
        vm.assume(testOwner != address(0));
        vm.assume(testYoinkAgent != address(0));
        vm.assume(testFlowRateAgent != address(0));
        
        vm.prank(treasury);
        uint256 generatedId = yoinkMaster.createYoink(
            testOwner,
            testYoinkAgent,
            testFlowRateAgent,
            superToken,
            "ipfs://test"
        );
        
        YoinkMaster.YoinkData memory yoinkData = yoinkMaster.getYoink(generatedId);
        assertEq(yoinkData.admin, testOwner);
        assertEq(yoinkData.yoinkAgent, testYoinkAgent);
        assertEq(yoinkData.flowRateAgent, testFlowRateAgent);
    }

    // ============ Hook Interface Implementation ============
    
    // This contract implements the hook interface for testing
    function beforeYoink(uint256 yoinkId, address newRecipient) external pure returns (bool) {
        // Always revert for testing
        revert("Hook reverted");
    }
}
