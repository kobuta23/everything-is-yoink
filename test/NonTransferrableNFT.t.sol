// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {NonTransferrableNFT} from "../src/NonTransferrableNFT.sol";
import {IERC721} from "../src/NonTransferrableNFT.sol";

// Test contract that can access internal functions
contract TestableNonTransferrableNFT is NonTransferrableNFT {
    constructor() NonTransferrableNFT("Test NFT", "TNFT") {}
    
    function testEmitMint(address to, uint256 tokenId) external {
        _emitMint(to, tokenId);
    }
    
    function testEmitBurn(address from, uint256 tokenId) external {
        _emitBurn(from, tokenId);
    }
    
    function testEmitTransfer(address from, address to, uint256 tokenId) external {
        _emitTransfer(from, to, tokenId);
    }
}

contract NonTransferrableNFTTest is Test {
    TestableNonTransferrableNFT public nft;
    
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    function setUp() public {
        nft = new TestableNonTransferrableNFT();
    }
    
    function test_EmitMint() public {
        nft.testEmitMint(user1, 1);
        
        // ownerOf should revert since we don't track ownership in base contract
        vm.expectRevert("NonTransferrableNFT: ownerOf must be implemented by inheriting contract");
        nft.ownerOf(1);
        
        // balanceOf always returns 0
        assertEq(nft.balanceOf(user1), 0);
    }
    
    function test_EmitBurn() public {
        nft.testEmitBurn(user1, 1);
        
        // ownerOf should revert since we don't track ownership in base contract
        vm.expectRevert("NonTransferrableNFT: ownerOf must be implemented by inheriting contract");
        nft.ownerOf(1);
        
        // balanceOf always returns 0
        assertEq(nft.balanceOf(user1), 0);
    }
    
    function test_EmitTransfer() public {
        nft.testEmitTransfer(user1, user2, 1);
        
        // ownerOf should revert since we don't track ownership in base contract
        vm.expectRevert("NonTransferrableNFT: ownerOf must be implemented by inheriting contract");
        nft.ownerOf(1);
        
        // balanceOf always returns 0
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 0);
    }
    
    function test_TransferFromReverts() public {
        vm.prank(user1);
        vm.expectRevert("NonTransferrableNFT: NFTs are non-transferrable");
        nft.transferFrom(user1, user2, 1);
    }
    
    function test_SafeTransferFromReverts() public {
        vm.prank(user1);
        vm.expectRevert("NonTransferrableNFT: NFTs are non-transferrable");
        nft.safeTransferFrom(user1, user2, 1);
    }
    
    function test_SafeTransferFromWithDataReverts() public {
        vm.prank(user1);
        vm.expectRevert("NonTransferrableNFT: NFTs are non-transferrable");
        nft.safeTransferFrom(user1, user2, 1, "");
    }
    
    function test_ApproveReverts() public {
        vm.prank(user1);
        vm.expectRevert("NonTransferrableNFT: NFTs are non-transferrable");
        nft.approve(user2, 1);
    }
    
    function test_SetApprovalForAllReverts() public {
        vm.prank(user1);
        vm.expectRevert("NonTransferrableNFT: NFTs are non-transferrable");
        nft.setApprovalForAll(user2, true);
    }
    
    function test_GetApprovedReturnsZero() public {
        assertEq(nft.getApproved(1), address(0));
    }
    
    function test_IsApprovedForAllReturnsFalse() public {
        assertFalse(nft.isApprovedForAll(user1, user2));
    }
    
    function test_NFTMetadata() public {
        assertEq(nft.name(), "Test NFT");
        assertEq(nft.symbol(), "TNFT");
    }
    
    function test_EmitMintEmitsTransferEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), user1, 1);
        
        nft.testEmitMint(user1, 1);
    }
    
    function test_EmitBurnEmitsTransferEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(0), 1);
        
        nft.testEmitBurn(user1, 1);
    }
    
    function test_EmitTransferEmitsTransferEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, 1);
        
        nft.testEmitTransfer(user1, user2, 1);
    }
}
