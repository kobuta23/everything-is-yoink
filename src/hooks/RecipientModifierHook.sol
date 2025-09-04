// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYoinkHook} from "./IYoinkHook.sol";

/**
 * @title RecipientModifierHook
 * @dev Hook that demonstrates recipient modification functionality
 * This hook can modify the recipient based on custom logic
 */
contract RecipientModifierHook is IYoinkHook {

    // Events
    event RecipientModified(uint256 indexed yoinkId, address originalRecipient, address modifiedRecipient);

    // State
    mapping(uint256 => address) public forcedRecipients;
    mapping(address => bool) public allowedRecipients;

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
     * Can modify the recipient based on custom logic
     */
    function beforeYoink(
        uint256 yoinkId,
        address oldRecipient,
        address newRecipient,
        address caller
    ) external returns (address) {

        // Example 1: Force a specific recipient for certain yoinks
        if (forcedRecipients[yoinkId] != address(0)) {
            address forcedRecipient = forcedRecipients[yoinkId];
            emit RecipientModified(yoinkId, newRecipient, forcedRecipient);
            return forcedRecipient;
        }

        // Example 2: Only allow specific recipients
        if (!allowedRecipients[newRecipient]) {
            // If recipient is not allowed, redirect to owner
            emit RecipientModified(yoinkId, newRecipient, owner);
            return owner;
        }

        // Example 3: Custom recipient logic could go here
        // For example: whitelist/blacklist logic, fee-based redirection, etc.

        // Return address(0) to use the original recipient
        return address(0);
    }

    // ============ Management Functions ============

    /**
     * @dev Forces a specific recipient for a yoink
     */
    function setForcedRecipient(uint256 yoinkId, address forcedRecipient) external onlyOwner {
        forcedRecipients[yoinkId] = forcedRecipient;
    }

    /**
     * @dev Sets whether a recipient is allowed
     */
    function setAllowedRecipient(address recipient, bool allowed) external onlyOwner {
        allowedRecipients[recipient] = allowed;
    }

    /**
     * @dev Transfers ownership of the hook
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Hook: new owner cannot be zero");
        owner = newOwner;
    }
}
