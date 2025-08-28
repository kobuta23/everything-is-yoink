// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYoinkHook} from "./IYoinkHook.sol";

/**
 * @title AdvancedHook
 * @dev Advanced hook contract for YoinkMaster with multiple features
 * This hook can do anything including reverting to prevent yoinks
 */
contract AdvancedHook is IYoinkHook {
    
    // Events
    event HookCalled(uint256 indexed yoinkId, address oldRecipient, address newRecipient, address caller);
    event HookReverted(uint256 indexed yoinkId, string reason);
    
    // State
    mapping(uint256 => bool) public blockedYoinks;
    mapping(uint256 => uint256) public lastYoinkTime;
    uint256 public constant MIN_INTERVAL = 1 hours;
    
    // Owner
    address public owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Hook: caller is not owner");
        _;
    }
    
    /**
     * @dev Hook function called before yoink
     * Can do anything including reverting to prevent the yoink
     */
    function beforeYoink(
        uint256 yoinkId,
        address oldRecipient,
        address newRecipient,
        address caller
    ) external {
        emit HookCalled(yoinkId, oldRecipient, newRecipient, caller);
        
        // Example 1: Block specific yoinks
        if (blockedYoinks[yoinkId]) {
            emit HookReverted(yoinkId, "Yoink is blocked");
            revert("Hook: yoink is blocked");
        }
        
        // Example 2: Rate limiting
        if (block.timestamp < lastYoinkTime[yoinkId] + MIN_INTERVAL) {
            emit HookReverted(yoinkId, "Rate limited");
            revert("Hook: rate limited");
        }
        
        // Example 3: Custom logic (e.g., fee collection, notifications, etc.)
        // This could integrate with other protocols, send cross-chain messages, etc.
        
        // Update last yoink time
        lastYoinkTime[yoinkId] = block.timestamp;
    }
    
    // Management functions
    function setBlockedYoink(uint256 yoinkId, bool blocked) external onlyOwner {
        blockedYoinks[yoinkId] = blocked;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Hook: new owner cannot be zero");
        owner = newOwner;
    }
}
