// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYoinkHook} from "./IYoinkHook.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {YoinkMaster} from "../YoinkMaster.sol";

/**
 * @title SmartFlowRateHook
 * @dev Hook that automatically modulates flow rate to run out within a specified window
 * This hook acts as both a yoink hook and a flow rate agent
 */
contract SmartFlowRateHook is IYoinkHook {
    
    // ============ Events ============
    
    event FlowRateModulated(uint256 indexed yoinkId, int96 oldRate, int96 newRate, uint256 targetDuration);
    event TargetDurationSet(uint256 indexed yoinkId, uint256 targetDuration);
    
    // ============ State Variables ============
    
    YoinkMaster public immutable yoinkMaster;
    
    // Mapping from yoinkId to target duration (in seconds)
    mapping(uint256 => uint256) public targetDurations;
    
    // Minimum flow rate to prevent dust amounts
    int96 public constant MIN_FLOW_RATE = 1e12; // 0.000001 tokens per second
    
    // ============ Constructor ============
    
    constructor(address _yoinkMaster) {
        yoinkMaster = YoinkMaster(_yoinkMaster);
    }
    
    // ============ Hook Functions ============
    
    /**
     * @dev Hook function called before yoink
     * Modulates flow rate based on treasury balance and target duration
     */
    function beforeYoink(
        uint256 yoinkId,
        address oldRecipient,
        address newRecipient,
        address caller
    ) external {
        // Modulate flow rate when recipient changes
        _modulateFlowRate(yoinkId);
    }
    
    // ============ Flow Rate Agent Functions ============
    
    /**
     * @dev Sets the target duration for a yoink
     * @param yoinkId Unique identifier for the yoink
     * @param targetDuration Target duration in seconds
     */
    function setTargetDuration(uint256 yoinkId, uint256 targetDuration) external {
        if(msg.sender != yoinkMaster.getAdmin(yoinkId)) {
            revert("SmartFlowRateHook: only yoink admin can set target duration");
        }
        require(targetDuration > 0, "SmartFlowRateHook: duration must be positive");
        targetDurations[yoinkId] = targetDuration;
        emit TargetDurationSet(yoinkId, targetDuration);
    }
    
    /**
     * @dev Modulates flow rate based on treasury balance and target duration
     * @param yoinkId Unique identifier for the yoink
     */
    function modulateFlowRate(uint256 yoinkId) external {
        _modulateFlowRate(yoinkId);
    }
    
    // ============ Internal Functions ============
    
    function _modulateFlowRate(uint256 yoinkId) internal {
        uint256 targetDuration = targetDurations[yoinkId];
        if (targetDuration == 0) return; // No target set, don't modulate
        
        // Get current flow rate from YoinkMaster
        int96 currentRate = yoinkMaster.getCurrentFlowRate(yoinkId);
        
        // Calculate new flow rate based on treasury balance
        int96 newRate = _calculateOptimalFlowRate(yoinkId, targetDuration);
        
        if (newRate != currentRate && newRate >= MIN_FLOW_RATE) {
            // Update flow rate via YoinkMaster
            address currentRecipient = yoinkMaster.getCurrentRecipient(yoinkId);
            yoinkMaster.updateStream(yoinkId, newRate);
            emit FlowRateModulated(yoinkId, currentRate, newRate, targetDuration);
        }
    }
    
    function _calculateOptimalFlowRate(uint256 yoinkId, uint256 targetDuration) internal view returns (int96) {
        // Get treasury balance from YoinkMaster
        uint256 treasuryBalance = yoinkMaster.getTreasuryBalance(yoinkId);
        
        if (treasuryBalance == 0) return 0;
        
        // Calculate flow rate: balance / duration
        // Convert to int96 (Superfluid flow rate format)
        uint256 flowRate = treasuryBalance / targetDuration;
        
        // Ensure minimum flow rate
        if (flowRate < uint256(uint96(MIN_FLOW_RATE))) {
            flowRate = uint256(uint96(MIN_FLOW_RATE));
        }
        
        return int96(uint96(flowRate));
    }
    
    // ============ View Functions ============
    
    /**
     * @dev Gets the optimal flow rate for a yoink without modifying it
     * @param yoinkId Unique identifier for the yoink
     * @return Optimal flow rate
     */
    function getOptimalFlowRate(uint256 yoinkId) external view returns (int96) {
        uint256 targetDuration = targetDurations[yoinkId];
        if (targetDuration == 0) return 0;
        
        return _calculateOptimalFlowRate(yoinkId, targetDuration);
    }
}
