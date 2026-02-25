// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ICreate3Factory.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/ProtocolUpgradeHandler.sol";
import "../src/EmergencyUpgradeBoard.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";

contract MainnetDeploy is Script {
    ICREATE3Factory CREATE3_FACTORY = ICREATE3Factory(vm.envAddress("CREATE3_FACTORY"));

    bytes32 PROTOCOL_UPGRADE_HANDLER_SALT = keccak256("ProtocolUpgradeHandler");
    bytes32 GUARDIANS_SALT = keccak256("Guardians");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard");

    address ZKSYNC_ERA = vm.envAddress("ZKSYNC_ERA");
    address CHAIN_TYPE_MANAGER = vm.envAddress("CHAIN_TYPE_MANAGER");
    address BRIDGE_HUB = vm.envAddress("BRIDGE_HUB");
    address L1_ASSET_ROUTER = vm.envAddress("L1_ASSET_ROUTER");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        address[] memory guardiansMembers = vm.envAddress("GUARDIAN_MEMBERS", ",");
        guardiansMembers = Utils.sortAddresses(guardiansMembers);

        address[] memory securityCouncilMembers = vm.envAddress("SECURITY_COUNCIL_MEMBERS", ",");
        securityCouncilMembers = Utils.sortAddresses(securityCouncilMembers);
        
        address zkFoundation = vm.envAddress("ZK_FOUNDATION");
        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");

        (address protocolUpgradeHandler, address guardians, address securityCouncil, address emergencyUpgradeBoard) = predictAddresses(deployerWallet.addr);

        // Deploy PUH
        bytes memory protocolUpgradeHandlerConstructorArgs = abi.encode(
            securityCouncil, 
            guardians, 
            emergencyUpgradeBoard, 
            l2ProtocolGovernor, 
            IZKsyncEra(ZKSYNC_ERA), 
            IChainTypeManager(CHAIN_TYPE_MANAGER), 
            IPausable(BRIDGE_HUB), 
            IPausable(L1_ASSET_ROUTER)
        );
        bytes memory protocolUpgradeHandlerCreationCode = abi.encodePacked(type(ProtocolUpgradeHandler).creationCode, protocolUpgradeHandlerConstructorArgs);
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_SALT, protocolUpgradeHandlerCreationCode);
        vm.stopBroadcast();
        console.log("XXXX PUH");

        // Deploy Guardians
        bytes memory guardiansConstructorArgs = abi.encode(protocolUpgradeHandler, IZKsyncEra(ZKSYNC_ERA), guardiansMembers);
        bytes memory guardiansCreationCode = abi.encodePacked(type(Guardians).creationCode, guardiansConstructorArgs);   
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(GUARDIANS_SALT, guardiansCreationCode);
        vm.stopBroadcast();
        console.log("XXXX GUARDIANS");

        // Deploy SecurityCouncil
        bytes memory securityCouncilConstructorArgs = abi.encode(protocolUpgradeHandler, securityCouncilMembers);
        bytes memory securityCouncilCreationCode = abi.encodePacked(type(SecurityCouncil).creationCode, securityCouncilConstructorArgs);
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(SECURITY_COUNCIL_SALT, securityCouncilCreationCode);
        vm.stopBroadcast();
        console.log("XXXX SC");

        // Deploy EmergencyUpgradeBoard
        bytes memory emergencyUpgradeBoardConstructorArgs = abi.encode(protocolUpgradeHandler, securityCouncil, guardians, zkFoundation);
        bytes memory emergencyUpgradeBoardCreationCode = abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, emergencyUpgradeBoardConstructorArgs);      
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(EMERGENCY_UPGRADE_BOARD_SALT, emergencyUpgradeBoardCreationCode);
        vm.stopBroadcast();
        console.log("XXXX EUB");
    }

    function predictAddresses(address deployerWallet) public returns(address protocolUpgradeHandler, address guardians, address securityCouncil, address emergencyUpgradeBoard) {
        protocolUpgradeHandler = CREATE3_FACTORY.getDeployed(deployerWallet, PROTOCOL_UPGRADE_HANDLER_SALT);
        console2.log("Protocol Upgrade Handler address: ", protocolUpgradeHandler);
        guardians = CREATE3_FACTORY.getDeployed(deployerWallet, GUARDIANS_SALT);
        console2.log("Guardians address: ", guardians);
        securityCouncil = CREATE3_FACTORY.getDeployed(deployerWallet, SECURITY_COUNCIL_SALT);
        console2.log("Security Council address: ", securityCouncil);
        emergencyUpgradeBoard = CREATE3_FACTORY.getDeployed(deployerWallet, EMERGENCY_UPGRADE_BOARD_SALT);
        console2.log("Emergency Upgrade Board address: ", emergencyUpgradeBoard);
    }
}
