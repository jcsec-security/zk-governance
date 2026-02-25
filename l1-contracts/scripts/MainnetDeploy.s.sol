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

import {IZKsyncEra} from "../src/interfaces/IZKsyncEra.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MainnetDeploy is Script {
    ICREATE3Factory CREATE3_FACTORY = ICREATE3Factory(vm.envAddress("CREATE3_FACTORY"));

    // This becomes the PUBLIC PUH address (the PROXY).
    bytes32 PROTOCOL_UPGRADE_HANDLER_SALT = keccak256("ProtocolUpgradeHandler");

    // Extra salts for infra.
    bytes32 PROTOCOL_UPGRADE_HANDLER_IMPL_SALT = keccak256("ProtocolUpgradeHandler_Impl");
    bytes32 PROXY_ADMIN_SALT = keccak256("ProxyAdmin");

    bytes32 GUARDIANS_SALT = keccak256("Guardians");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard");

    // PUH constructor deps
    address ZKSYNC_ERA = vm.envAddress("ZKSYNC_ERA");
    address CHAIN_TYPE_MANAGER = vm.envAddress("CHAIN_TYPE_MANAGER");
    address BRIDGE_HUB = vm.envAddress("BRIDGE_HUB");
    address L1_NULLIFIER = vm.envAddress("L1_NULLIFIER");
    address L1_ASSET_ROUTER = vm.envAddress("L1_ASSET_ROUTER");
    address L1_NATIVE_TOKEN_VAULT = vm.envAddress("L1_NATIVE_TOKEN_VAULT");
    address CHAIN_ASSET_HANDLER = vm.envAddress("CHAIN_ASSET_HANDLER");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        address[] memory guardiansMembers = Utils.sortAddresses(vm.envAddress("GUARDIAN_MEMBERS", ","));
        address[] memory securityCouncilMembers = Utils.sortAddresses(vm.envAddress("SECURITY_COUNCIL_MEMBERS", ","));

        address zkFoundation = vm.envAddress("ZK_FOUNDATION");
        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");

        (
            address proxyAdmin,
            address protocolUpgradeHandlerImpl,
            address protocolUpgradeHandlerProxy,
            address guardians,
            address securityCouncil,
            address emergencyUpgradeBoard
        ) = predictAddresses(deployerWallet.addr);

        require(guardiansMembers.length == 8, "GUARDIAN_MEMBERS must be exactly 8");
        require(securityCouncilMembers.length == 12, "SECURITY_COUNCIL_MEMBERS must be exactly 12");

        vm.startBroadcast(deployerPrivateKey);
        // 1) ProxyAdmin
        address initialOwner = vm.envAddress("PROXY_ADMIN");
        bytes memory proxyAdminCreationCode =
            abi.encodePacked(type(ProxyAdmin).creationCode, abi.encode(initialOwner));
        CREATE3_FACTORY.deploy(PROXY_ADMIN_SALT, proxyAdminCreationCode);

        // 2) PUH implementation
        bytes memory implArgs = abi.encode(
            l2ProtocolGovernor,
            IZKsyncEra(ZKSYNC_ERA),
            IChainTypeManager(CHAIN_TYPE_MANAGER),
            IBridgeHub(BRIDGE_HUB),
            IPausable(L1_NULLIFIER),
            IPausable(L1_ASSET_ROUTER),
            IPausable(L1_NATIVE_TOKEN_VAULT),
            IChainAssetHandler(CHAIN_ASSET_HANDLER)
        );
        bytes memory implCreationCode =
            abi.encodePacked(type(ProtocolUpgradeHandler).creationCode, implArgs);
        CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_IMPL_SALT, implCreationCode);

        // 3) PUH proxy
        bytes memory proxyCreationCode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(
                protocolUpgradeHandlerImpl,
                proxyAdmin,
                bytes("")
            )
        );
        CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_SALT, proxyCreationCode);

        // 4) Deploy Guardians (no proxy)
        bytes memory guardiansArgs =
            abi.encode(IProtocolUpgradeHandler(protocolUpgradeHandlerProxy), IZKsyncEra(ZKSYNC_ERA), guardiansMembers);
        bytes memory guardiansCreationCode = abi.encodePacked(type(Guardians).creationCode, guardiansArgs);
        CREATE3_FACTORY.deploy(GUARDIANS_SALT, guardiansCreationCode);

        // 5) Deploy SecurityCouncil (no proxy)
        bytes memory scArgs =
            abi.encode(IProtocolUpgradeHandler(protocolUpgradeHandlerProxy), securityCouncilMembers);
        bytes memory scCreationCode = abi.encodePacked(type(SecurityCouncil).creationCode, scArgs);
        CREATE3_FACTORY.deploy(SECURITY_COUNCIL_SALT, scCreationCode);

        // 6) Deploy EmergencyUpgradeBoard (no proxy)
        bytes memory eubArgs =
            abi.encode(IProtocolUpgradeHandler(protocolUpgradeHandlerProxy), securityCouncil, guardians, zkFoundation);
        bytes memory eubCreationCode = abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, eubArgs);
        CREATE3_FACTORY.deploy(EMERGENCY_UPGRADE_BOARD_SALT, eubCreationCode);

        // 7) Initialize PUH via proxy after the other three exist
        ProtocolUpgradeHandler(payable(protocolUpgradeHandlerProxy)).initialize(securityCouncil, guardians, emergencyUpgradeBoard);

        vm.stopBroadcast();    
    }

    function predictAddresses(address deployer)
        public
        view
        returns (
            address proxyAdmin,
            address protocolUpgradeHandlerImpl,
            address protocolUpgradeHandlerProxy,
            address guardians,
            address securityCouncil,
            address emergencyUpgradeBoard
        )
    {
        proxyAdmin = CREATE3_FACTORY.getDeployed(deployer, PROXY_ADMIN_SALT);
        console2.log("ProxyAdmin (pred):", proxyAdmin);

        protocolUpgradeHandlerImpl = CREATE3_FACTORY.getDeployed(deployer, PROTOCOL_UPGRADE_HANDLER_IMPL_SALT);
        console2.log("PUH Impl (pred):", protocolUpgradeHandlerImpl);

        // The public PUH address is the proxy
        protocolUpgradeHandlerProxy = CREATE3_FACTORY.getDeployed(deployer, PROTOCOL_UPGRADE_HANDLER_SALT);
        console2.log("PUH Proxy (pred):", protocolUpgradeHandlerProxy);

        guardians = CREATE3_FACTORY.getDeployed(deployer, GUARDIANS_SALT);
        console2.log("Guardians (pred):", guardians);

        securityCouncil = CREATE3_FACTORY.getDeployed(deployer, SECURITY_COUNCIL_SALT);
        console2.log("SecurityCouncil (pred):", securityCouncil);

        emergencyUpgradeBoard = CREATE3_FACTORY.getDeployed(deployer, EMERGENCY_UPGRADE_BOARD_SALT);
        console2.log("EmergencyUpgradeBoard (pred):", emergencyUpgradeBoard);
    }
}