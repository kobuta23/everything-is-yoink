// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IPositionManager
 * @dev Interface for position manager contracts that collect fees
 */
interface IPositionManager {
    /**
     * @dev Gets the fee balance for a specific token
     * @param token Address of the fee token
     * @return Fee balance
     */
    function getFeeBalance(address token) external view returns (uint256);
    
    /**
     * @dev Withdraws fees for a specific token
     * @param token Address of the fee token
     * @param amount Amount to withdraw
     * @return Amount actually withdrawn
     */
    function withdrawFees(address token, uint256 amount) external returns (uint256);
    
    /**
     * @dev Gets the owner/admin of the position manager
     * @return Owner address
     */
    function owner() external view returns (address);
}
