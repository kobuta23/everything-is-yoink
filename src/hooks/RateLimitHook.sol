// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYoinkHook} from "./IYoinkHook.sol";

/**
 * @title RateLimitHook
 * @dev Hook that enforces 1 hour between yoinks
 */
contract RateLimitHook is IYoinkHook {
    mapping(uint256 => uint256) public lastYoinkTime;
    uint256 public constant MIN_INTERVAL = 1 hours;
    
    function beforeYoink(uint256 yoinkId, address, address, address) external {
        require(block.timestamp >= lastYoinkTime[yoinkId] + MIN_INTERVAL, "Rate limited: 1 hour required");
        lastYoinkTime[yoinkId] = block.timestamp;
    }
}
