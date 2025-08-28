// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract SuperfluidExample {
    using SuperTokenV1Library for ISuperToken;

    function getFlowRate(ISuperToken superToken, address sender, address receiver) 
        external 
        view 
        returns (int96 flowRate) 
    {
        return superToken.getFlowRate(sender, receiver);
    }
}
