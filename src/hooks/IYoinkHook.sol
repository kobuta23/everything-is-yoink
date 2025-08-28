// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IYoinkHook
 * @dev Interface for yoink hooks
 */
interface IYoinkHook {
    /**
     * @dev Hook function called before yoink
     * @param yoinkId Unique identifier for the yoink
     * @param oldRecipient Previous recipient address
     * @param newRecipient New recipient address
     * @param caller Address that initiated the yoink
     */
    function beforeYoink(
        uint256 yoinkId,
        address oldRecipient,
        address newRecipient,
        address caller
    ) external;
}
