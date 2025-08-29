// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {YoinkMaster} from "../src/YoinkMaster.sol";
import {YoinkEscrowWrapper} from "../src/YoinkEscrowWrapper.sol";
import {YoinkEscrowPure} from "../src/YoinkEscrowPure.sol";

contract DeployYoinkScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        

        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy YoinkEscrowWrapper template first
        YoinkEscrowWrapper escrowTemplateWrapper = new YoinkEscrowWrapper();
        console.log("YoinkEscrowWrapper template deployed at:", address(escrowTemplateWrapper));
        
        // Deploy YoinkEscrowPure template for non-wrapper tokens
        YoinkEscrowPure escrowTemplatePure = new YoinkEscrowPure();
        console.log("YoinkEscrowPure template deployed at:", address(escrowTemplatePure));
        
        // Deploy YoinkMaster
        YoinkMaster yoinkMaster = new YoinkMaster();
        console.log("YoinkMaster deployed at:", address(yoinkMaster));
        
        console.log("Deployer address:", deployer);
        console.log("");
        console.log("Usage:");
        console.log("1. Treasury calls createYoink(owner, yoinkAgent, flowRateAgent, token, metadataURI, hook)");
        console.log("2. Treasury must have given approval to Yoink contract for the token");
        console.log("3. FlowRateAgent can call startStream() to start streams or updateStream() to update flow rates");
        console.log("4. YoinkAgent can call yoink() to change stream recipients");
        console.log("5. Owner can manage agents and transfer ownership");
        console.log("");
        console.log("Note: This contract uses createFlowFrom, so treasury must approve the YoinkMaster contract");
        console.log("Note: Each yoink is represented as a non-transferrable NFT with ID = yoinkId");
        console.log("Note: NFTs use default metadata unless custom URI provided");
        console.log("");
        console.log("Factory Usage:");
        console.log("1. Use YoinkFactory to create pre-configured yoinks with hooks");
        console.log("2. Factory automatically deploys appropriate escrow contracts");
        console.log("3. For wrapper tokens: deploys YoinkEscrowWrapper with wrapping functionality");
        console.log("4. For non-wrapper tokens: deploys YoinkEscrowPure for direct superToken deposits");
        console.log("5. User deposits tokens into the escrow contract");
        console.log("6. User can start streams using the escrow contract as treasury");
        console.log("7. The escrow contract automatically authorizes the YoinkMaster to create streams");
        console.log("8. Users can withdraw tokens from their escrow contract at any time");

        vm.stopBroadcast();
    }
}
