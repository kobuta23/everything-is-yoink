// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {YoinkFactory} from "../src/YoinkFactory.sol";
import {YoinkMaster} from "../src/YoinkMaster.sol";
import {YoinkEscrowWrapper} from "../src/YoinkEscrowWrapper.sol";
import {YoinkEscrowPure} from "../src/YoinkEscrowPure.sol";

contract DeployFactory is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy YoinkMaster first
        YoinkMaster yoinkMaster = new YoinkMaster();
        console.log("YoinkMaster deployed at:", address(yoinkMaster));
        
        // Deploy escrow templates
        YoinkEscrowWrapper escrowTemplateWrapper = new YoinkEscrowWrapper();
        YoinkEscrowPure escrowTemplatePure = new YoinkEscrowPure();
        
        console.log("EscrowTemplateWrapper deployed at:", address(escrowTemplateWrapper));
        console.log("EscrowTemplatePure deployed at:", address(escrowTemplatePure));
        
        // Deploy YoinkFactory
        YoinkFactory factory = new YoinkFactory(
            address(yoinkMaster),
            address(escrowTemplateWrapper),
            address(escrowTemplatePure)
        );
        
        console.log("YoinkFactory deployed at:", address(factory));
        console.log("RateLimitHook deployed at:", factory.rateLimitHook());
        console.log("SmartFlowRateHook deployed at:", factory.smartFlowRateHook());
        console.log("FeePullerHook deployed at:", factory.feePullerHook());
        
        vm.stopBroadcast();
    }
}
