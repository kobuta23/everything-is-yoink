// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {YoinkMaster} from "./YoinkMaster.sol";
import {YoinkEscrowWrapper} from "./YoinkEscrowWrapper.sol";
import {YoinkEscrowPure} from "./YoinkEscrowPure.sol";
import {RateLimitHook} from "./hooks/RateLimitHook.sol";
import {SmartFlowRateHook} from "./hooks/SmartFlowRateHook.sol";
import {FeePullerHook} from "./hooks/FeePullerHook.sol";

/**
 * @title YoinkFactory
 * @dev Factory contract for creating yoinks with preset configurations
 * Provides easy-to-use presets for different use cases
 */
contract YoinkFactory {
    
    // ============ State Variables ============
    
    YoinkMaster public immutable yoinkMaster;
    address public immutable escrowTemplateWrapper;
    address public immutable escrowTemplatePure;
    
    // Preset hook contracts
    address public immutable rateLimitHook;
    address public immutable smartFlowRateHook;
    address public immutable feePullerHook;
    
    // ============ Events ============
    
    event YoinkCreated(
        uint256 indexed yoinkId,
        address indexed escrowContract,
        string preset,
        address indexed admin,
        address token
    );
    
    // ============ Constructor ============
    
    constructor(
        address _yoinkMaster,
        address _escrowTemplateWrapper,
        address _escrowTemplatePure
    ) {
        yoinkMaster = YoinkMaster(_yoinkMaster);
        escrowTemplateWrapper = _escrowTemplateWrapper;
        escrowTemplatePure = _escrowTemplatePure;
        
        // Deploy preset hooks
        rateLimitHook = address(new RateLimitHook());
        smartFlowRateHook = address(new SmartFlowRateHook(address(yoinkMaster)));
        feePullerHook = address(new FeePullerHook(address(yoinkMaster)));
    }
    
    // ============ Preset Functions ============
    
    /**
     * @dev Creates a yoink with rate limiting (1 hour between yoinks)
     * @param admin Admin of the yoink (becomes owner of escrow)
     * @param yoinkAgent Address authorized to change recipients
     * @param flowRateAgent Address authorized to change flow rates
     * @param token SuperToken to be streamed
     * @param metadataURI Optional metadata URI
     */
    function createRateLimitedYoink(
        address admin,
        address yoinkAgent,
        address flowRateAgent,
        ISuperToken token,
        string memory metadataURI
    ) external returns (address escrowContract, uint256 yoinkId) {
        (escrowContract, yoinkId) = _createYoinkWithEscrow(
            admin,
            yoinkAgent,
            flowRateAgent,
            token,
            metadataURI,
            rateLimitHook
        );
        
        emit YoinkCreated(yoinkId, escrowContract, "RATE_LIMITED", admin, address(token));
    }
    
    /**
     * @dev Creates a yoink with smart flow rate modulation
     * The hook automatically adjusts flow rate to run out within a specified window
     * @param admin Admin of the yoink (becomes owner of escrow)
     * @param yoinkAgent Address authorized to change recipients
     * @param token SuperToken to be streamed
     * @param metadataURI Optional metadata URI
     * @param targetDuration Target duration in seconds for the flow to run out
     */
    function createSmartFlowRateYoink(
        address admin,
        address yoinkAgent,
        ISuperToken token,
        string memory metadataURI,
        uint256 targetDuration
    ) external returns (address escrowContract, uint256 yoinkId) {
        (escrowContract, yoinkId) = _createYoinkWithEscrow(
            admin,
            yoinkAgent,
            smartFlowRateHook, // Hook acts as flow rate agent
            token,
            metadataURI,
            smartFlowRateHook
        );
        
        // Set the target duration for the smart flow rate hook
        SmartFlowRateHook(smartFlowRateHook).setTargetDuration(yoinkId, targetDuration);
        
        emit YoinkCreated(yoinkId, escrowContract, "SMART_FLOW_RATE", admin, address(token));
    }
    
    /**
     * @dev Creates a yoink with fee pulling from position manager
     * The hook automatically pulls fees and deposits them into the escrow contract
     * @param admin Admin of the yoink (becomes owner of escrow)
     * @param yoinkAgent Address authorized to change recipients
     * @param token SuperToken to be streamed
     * @param metadataURI Optional metadata URI
     * @param positionManager Address of the position manager contract
     * @param feeToken Address of the fee token
     * @param minFeeThreshold Minimum fee threshold to pull
     */
    function createFeePullerYoink(
        address admin,
        address yoinkAgent,
        ISuperToken token,
        string memory metadataURI,
        address positionManager,
        address feeToken,
        uint256 minFeeThreshold
    ) external returns (address escrowContract, uint256 yoinkId) {
        (escrowContract, yoinkId) = _createYoinkWithEscrow(
            admin,
            yoinkAgent,
            feePullerHook, // Hook acts as flow rate agent
            token,
            metadataURI,
            feePullerHook
        );
        
        // Configure the fee puller hook
        FeePullerHook(feePullerHook).setPositionManager(yoinkId, positionManager);
        FeePullerHook(feePullerHook).setFeeToken(yoinkId, feeToken);
        FeePullerHook(feePullerHook).setMinFeeThreshold(yoinkId, minFeeThreshold);
        
        emit YoinkCreated(yoinkId, escrowContract, "FEE_PULLER", admin, address(token));
    }
    
    /**
     * @dev Creates a yoink with custom hook
     * @param admin Admin of the yoink (becomes owner of escrow)
     * @param yoinkAgent Address authorized to change recipients
     * @param flowRateAgent Address authorized to change flow rates
     * @param token SuperToken to be streamed
     * @param metadataURI Optional metadata URI
     * @param customHook Custom hook contract address
     */
    function createCustomYoink(
        address admin,
        address yoinkAgent,
        address flowRateAgent,
        ISuperToken token,
        string memory metadataURI,
        address customHook
    ) external returns (address escrowContract, uint256 yoinkId) {
        (escrowContract, yoinkId) = _createYoinkWithEscrow(
            admin,
            yoinkAgent,
            flowRateAgent,
            token,
            metadataURI,
            customHook
        );
        
        emit YoinkCreated(yoinkId, escrowContract, "CUSTOM", admin, address(token));
    }
    
    // ============ Internal Functions ============
    
    function _createYoinkWithEscrow(
        address admin,
        address yoinkAgent,
        address flowRateAgent,
        ISuperToken token,
        string memory metadataURI,
        address hook
    ) internal returns (address escrowContract, uint256 yoinkId) {
        // Always create escrow contract as treasury
        // Detect if this is a wrapper superToken
        (bool isWrapper, address underlyingToken) = _detectWrapperToken(token);
        
        if (isWrapper) {
            // Deploy wrapper escrow contract
            escrowContract = Clones.clone(escrowTemplateWrapper);
            YoinkEscrowWrapper(escrowContract).initialize(
                admin, // admin becomes owner of escrow
                address(yoinkMaster),
                token,
                underlyingToken
            );
            // Create yoink from escrow contract
            yoinkId = YoinkEscrowWrapper(escrowContract).createYoink(
                admin,
                yoinkAgent,
                flowRateAgent,
                metadataURI,
                hook
            );
        } else {
            // Deploy pure escrow contract
            escrowContract = Clones.clone(escrowTemplatePure);
            YoinkEscrowPure(escrowContract).initialize(
                admin, // admin becomes owner of escrow
                address(yoinkMaster),
                token
            );
            // Create yoink from escrow contract
            yoinkId = YoinkEscrowPure(escrowContract).createYoink(
                admin,
                yoinkAgent,
                flowRateAgent,
                metadataURI,
                hook
            );
        }
        
        return (escrowContract, yoinkId);
    }
    
    function _detectWrapperToken(ISuperToken superToken) internal view returns (bool isWrapper, address underlyingToken) {
        try superToken.getUnderlyingToken() returns (address underlying) {
            return (true, underlying);
        } catch {
            return (false, address(0));
        }
    }
}
