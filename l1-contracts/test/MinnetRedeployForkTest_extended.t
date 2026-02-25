// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, stdStorage, StdStorage, Vm} from "forge-std/Test.sol";

import {Callee} from "./utils/Callee.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {StateTransitionManagerMock} from "./mocks/StateTransitionManagerMock.t.sol";

import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {IStateTransitionManager} from "../src/interfaces/IStateTransitionManager.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {Guardians} from "../src/Guardians.sol";
import {SecurityCouncil} from "../src/SecurityCouncil.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {Multisig} from "../src/Multisig.sol";

import {MainnetRedeploy} from "../scripts/MainnetRedeploy.s.sol";
import {DeployedContracts} from "../scripts/Redeploy.s.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @dev Small “versioned” wrappers used by this fork-test to ensure that a brand new bytecode version
/// can be deployed and wired into the system through the upgrade flow.
contract ProtocolUpgradeHandlerV2 is ProtocolUpgradeHandler {
    constructor(
        address _l2ProtocolGovernor,
        IChainTypeManager _chainTypeManager,
        IBridgeHub _bridgeHub,
        IPausable _l1Nullifier,
        IPausable _l1AssetRouter,
        IPausable _l1NativeTokenVault,
        IChainAssetHandler _chainAssetHandler,
        uint256 _eraChainId
    )
        ProtocolUpgradeHandler(
            _l2ProtocolGovernor,
            _chainTypeManager,
            _bridgeHub,
            _l1Nullifier,
            _l1AssetRouter,
            _l1NativeTokenVault,
            _chainAssetHandler,
            _eraChainId
        )
    {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract GuardiansV2 is Guardians {
    constructor(
        IProtocolUpgradeHandler _protocolUpgradeHandler,
        IBridgeHub _bridgeHub,
        uint256 _eraChainId,
        address[] memory _members
    ) Guardians(_protocolUpgradeHandler, _bridgeHub, _eraChainId, _members) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract SecurityCouncilV2 is SecurityCouncil {
    constructor(IProtocolUpgradeHandler _protocolUpgradeHandler, address[] memory _members)
        SecurityCouncil(_protocolUpgradeHandler, _members)
    {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract EmergencyUpgradeBoardV2 is EmergencyUpgradeBoard {
    constructor(
        IProtocolUpgradeHandler _protocolUpgradeHandler,
        address _securityCouncil,
        address _guardians,
        address _zkFoundation
    ) EmergencyUpgradeBoard(_protocolUpgradeHandler, _securityCouncil, _guardians, _zkFoundation) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @dev This test is focused to ensure that the new Proxy-based setup works correctly on a mainnet fork.
contract MainnetRedeployForkTest is Test {
    using stdStorage for StdStorage;

    MainnetRedeploy script;
    DeployedContracts addresses;

    modifier onlyMainnet() {
        if (block.chainid == 1) {
            _;
        } else {
            return;
        }
    }

    function setUp() external onlyMainnet {
        Vm.Wallet memory deployerWallet = vm.createWallet("deployerWalelt");

        vm.setEnv("PRIVATE_KEY", vm.toString(deployerWallet.privateKey));
        vm.setEnv("L2_PROTOCOL_GOVERNOR", vm.toString(address(uint160(1))));

        MainnetRedeploy s = new MainnetRedeploy();
        s.run();

        addresses = s.getDeployedAddresses();
    }

    // -----------------------
    // Upgrade helpers
    // -----------------------

    function _emergencyUpgradeCalls(IProtocolUpgradeHandler.Call[] memory _calls) internal {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: _calls,
            executor: addresses.emergencyUpgradeBoard,
            salt: bytes32(0)
        });

        vm.broadcast(addresses.emergencyUpgradeBoard);
        ProtocolUpgradeHandler(payable(addresses.protocolUpgradeHandlerProxy)).executeEmergencyUpgrade(proposal);
    }

    function _emergencyUpgradeCall(address _to, bytes memory _data) internal {
        IProtocolUpgradeHandler.Call;
        calls[0] = IProtocolUpgradeHandler.Call({target: _to, value: 0, data: _data});
        _emergencyUpgradeCalls(calls);
    }

    function _proxyAdmin(address _transparentProxy) internal view returns (address admin) {
        // EIP-1967 admin slot.
        admin = address(
            uint160(
                uint256(
                    vm.load(
                        _transparentProxy,
                        bytes32(
                            uint256(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)
                        )
                    )
                )
            )
        );
    }

    function _readMembers(address _multisig) internal view returns (address[] memory members) {
        uint256 totalMembers = uint256(vm.load(_multisig, bytes32(uint256(0))));
        members = new address[](totalMembers);

        for (uint256 i = 0; i < totalMembers; i++) {
            members[i] = Multisig(_multisig).members(i);
            require(members[i] != address(0), "empty member");
        }

        // Cross-check we read the right length.
        try Multisig(_multisig).members(totalMembers) returns (address) {
            revert("wrong member length");
        } catch {
            // expected
        }
    }

    function _makeSortedWalletMembers(uint256 n)
        internal
        returns (address[] memory members, uint256[] memory privateKeys)
    {
        members = new address[](n);
        privateKeys = new uint256[](n);

        for (uint256 i = 0; i < n; i++) {
            Vm.Wallet memory w = vm.createWallet(string(abi.encodePacked("member-", vm.toString(i))));
            members[i] = w.addr;
            privateKeys[i] = w.privateKey;
        }

        // Insertion sort by address, keeping privateKeys aligned.
        for (uint256 i = 1; i < n; i++) {
            address keyAddr = members[i];
            uint256 keyPk = privateKeys[i];
            uint256 j = i;
            while (j > 0 && members[j - 1] > keyAddr) {
                members[j] = members[j - 1];
                privateKeys[j] = privateKeys[j - 1];
                j--;
            }
            members[j] = keyAddr;
            privateKeys[j] = keyPk;
        }

        // Ensure strictly increasing.
        for (uint256 i = 1; i < n; i++) {
            require(members[i - 1] < members[i], "duplicate member generated");
        }
    }

    // -----------------------
    // Deploy + wiring tests
    // -----------------------

    /// @dev Verifies that the redeploy script deploys *all* /src contracts and the wiring is consistent.
    function test_MainnetForkDeployAllContractsAndWiring() external onlyMainnet {
        // Deployed contracts should have code.
        assertGt(addresses.protocolUpgradeHandlerImpl.code.length, 0, "puh impl not deployed");
        assertGt(addresses.protocolUpgradeHandlerProxy.code.length, 0, "puh proxy not deployed");
        assertGt(addresses.guardians.code.length, 0, "guardians not deployed");
        assertGt(addresses.securityCouncil.code.length, 0, "security council not deployed");
        assertGt(addresses.emergencyUpgradeBoard.code.length, 0, "emergency upgrade board not deployed");

        // PUH should point to the deployed governance contracts.
        ProtocolUpgradeHandler puh = ProtocolUpgradeHandler(payable(addresses.protocolUpgradeHandlerProxy));
        assertEq(puh.guardians(), addresses.guardians, "puh.guardians mismatch");
        assertEq(puh.securityCouncil(), addresses.securityCouncil, "puh.securityCouncil mismatch");
        assertEq(puh.emergencyUpgradeBoard(), addresses.emergencyUpgradeBoard, "puh.emergencyUpgradeBoard mismatch");

        // EmergencyUpgradeBoard should be wired to the same contracts.
        EmergencyUpgradeBoard eub = EmergencyUpgradeBoard(addresses.emergencyUpgradeBoard);
        assertEq(address(eub.PROTOCOL_UPGRADE_HANDLER()), addresses.protocolUpgradeHandlerProxy, "eub.puh mismatch");
        assertEq(eub.SECURITY_COUNCIL(), addresses.securityCouncil, "eub.sc mismatch");
        assertEq(eub.GUARDIANS(), addresses.guardians, "eub.guardians mismatch");
        assertTrue(eub.ZK_FOUNDATION_SAFE() != address(0), "eub.zk safe zero");

        // Guardians / SecurityCouncil should point to the PUH proxy.
        assertEq(
            address(Guardians(addresses.guardians).PROTOCOL_UPGRADE_HANDLER()),
            addresses.protocolUpgradeHandlerProxy,
            "guardians.puh mismatch"
        );
        assertEq(
            address(SecurityCouncil(addresses.securityCouncil).PROTOCOL_UPGRADE_HANDLER()),
            addresses.protocolUpgradeHandlerProxy,
            "sc.puh mismatch"
        );

        // Sanity: multisig member arrays are non-empty (copied from the existing system).
        assertGt(_readMembers(addresses.guardians).length, 0, "guardians members empty");
        assertGt(_readMembers(addresses.securityCouncil).length, 0, "sc members empty");
    }

    /// @dev Tests that the ProtocolUpgradeHandler can:
    /// 1) upgrade its own proxy implementation to a new bytecode version, and
    /// 2) “upgrade” the other governance contracts by deploying fresh versions and updating PUH pointers
    ///    via an emergency upgrade proposal.
    /// Additionally, performs a real EIP-1271 signature verification on the newly deployed governance contracts.
    function test_MainnetForkUpgradeAndRedeployAllSrcContracts_WithEIP1271() external onlyMainnet {
        ProtocolUpgradeHandler puh = ProtocolUpgradeHandler(payable(addresses.protocolUpgradeHandlerProxy));

        // ---- Deploy new versions (fresh bytecode) of *all* /src contracts ----

        // ProtocolUpgradeHandler new implementation version.
        ProtocolUpgradeHandlerV2 newPuhImpl = new ProtocolUpgradeHandlerV2(
            address(uint160(1)), // L2_PROTOCOL_GOVERNOR from setUp
            puh.CHAIN_TYPE_MANAGER(),
            puh.BRIDGE_HUB(),
            puh.L1_NULLIFIER(),
            puh.L1_ASSET_ROUTER(),
            puh.L1_NATIVE_TOKEN_VAULT(),
            puh.CHAIN_ASSET_HANDLER(),
            puh.ERA_CHAIN_ID()
        );

        // Use locally generated members so we can actually exercise EIP-1271 verification.
        // SecurityCouncil requires >= 9, Guardians requires >= 5 (thresholds are fixed in constructors).
        (address[] memory members9, uint256[] memory pks9) = _makeSortedWalletMembers(9);

        Guardians deployedGuardians = Guardians(addresses.guardians);
        EmergencyUpgradeBoard deployedEub = EmergencyUpgradeBoard(addresses.emergencyUpgradeBoard);

        GuardiansV2 newGuardians = new GuardiansV2(
            IProtocolUpgradeHandler(addresses.protocolUpgradeHandlerProxy),
            deployedGuardians.BRIDGE_HUB(),
            deployedGuardians.ERA_CHAIN_ID(),
            members9
        );

        SecurityCouncilV2 newSecurityCouncil = new SecurityCouncilV2(
            IProtocolUpgradeHandler(addresses.protocolUpgradeHandlerProxy),
            members9
        );

        EmergencyUpgradeBoardV2 newEub = new EmergencyUpgradeBoardV2(
            IProtocolUpgradeHandler(addresses.protocolUpgradeHandlerProxy),
            address(newSecurityCouncil),
            address(newGuardians),
            deployedEub.ZK_FOUNDATION_SAFE()
        );

        // ---- Execute the emergency upgrade proposal with multiple calls ----

        address proxyAdmin = _proxyAdmin(addresses.protocolUpgradeHandlerProxy);

        IProtocolUpgradeHandler.Call;

        // (1) Upgrade PUH proxy implementation.
        calls[0] = IProtocolUpgradeHandler.Call({
            target: proxyAdmin,
            value: 0,
            data: abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(addresses.protocolUpgradeHandlerProxy), address(newPuhImpl), hex"")
            )
        });

        // (2-4) Update “governance contract” pointers (onlySelf, so they must be executed as self-calls).
        calls[1] = IProtocolUpgradeHandler.Call({
            target: addresses.protocolUpgradeHandlerProxy,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateGuardians, (address(newGuardians)))
        });

        calls[2] = IProtocolUpgradeHandler.Call({
            target: addresses.protocolUpgradeHandlerProxy,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateSecurityCouncil, (address(newSecurityCouncil)))
        });

        calls[3] = IProtocolUpgradeHandler.Call({
            target: addresses.protocolUpgradeHandlerProxy,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (address(newEub)))
        });

        _emergencyUpgradeCalls(calls);

        // ---- Post-conditions ----

        // (a) Implementation upgrade took effect.
        assertEq(ProtocolUpgradeHandlerV2(addresses.protocolUpgradeHandlerProxy).version(), 2, "puh impl not upgraded");

        // (b) PUH pointers updated to new versions.
        assertEq(puh.guardians(), address(newGuardians), "guardians not updated");
        assertEq(puh.securityCouncil(), address(newSecurityCouncil), "security council not updated");
        assertEq(puh.emergencyUpgradeBoard(), address(newEub), "eub not updated");

        // (c) New contracts are wired correctly to the PUH proxy.
        assertEq(address(newGuardians.PROTOCOL_UPGRADE_HANDLER()), addresses.protocolUpgradeHandlerProxy, "new guardians.puh mismatch");
        assertEq(address(newSecurityCouncil.PROTOCOL_UPGRADE_HANDLER()), addresses.protocolUpgradeHandlerProxy, "new sc.puh mismatch");
        assertEq(address(newEub.PROTOCOL_UPGRADE_HANDLER()), addresses.protocolUpgradeHandlerProxy, "new eub.puh mismatch");
        assertEq(newEub.SECURITY_COUNCIL(), address(newSecurityCouncil), "new eub.sc mismatch");
        assertEq(newEub.GUARDIANS(), address(newGuardians), "new eub.guardians mismatch");

        // (d) “Version” markers are callable (ensures bytecode differs).
        assertEq(newGuardians.version(), 2, "guardians v2 mismatch");
        assertEq(newSecurityCouncil.version(), 2, "sc v2 mismatch");
        assertEq(newEub.version(), 2, "eub v2 mismatch");

        // ---- Real action: EIP-1271 signature verification on new multisigs ----

        bytes32 digest = keccak256("fork-test-eip1271");

        // Guardians threshold is 5.
        address;
        bytes;
        for (uint256 i = 0; i < 5; i++) {
            gSigners[i] = members9[i];
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pks9[i], digest);
            gSigs[i] = abi.encodePacked(r, s, v);
        }
        bytes memory gPayload = abi.encode(gSigners, gSigs);
        assertEq(newGuardians.isValidSignature(digest, gPayload), 0x1626ba7e, "guardians EIP-1271 failed");

        // SecurityCouncil threshold is 9.
        address;
        bytes;
        for (uint256 i = 0; i < 9; i++) {
            scSigners[i] = members9[i];
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pks9[i], digest);
            scSigs[i] = abi.encodePacked(r, s, v);
        }
        bytes memory scPayload = abi.encode(scSigners, scSigs);
        assertEq(newSecurityCouncil.isValidSignature(digest, scPayload), 0x1626ba7e, "sc EIP-1271 failed");
    }

    // -----------------------
    // Existing focused tests
    // -----------------------

    // Tests that the new ProtocolUpgradeHandler can upgrade itself
    function test_MainnetForkProxyUpgrade() external onlyMainnet {
        address proxyAdmin = _proxyAdmin(addresses.protocolUpgradeHandlerProxy);

        // We upgrade to an incorrect address (guardians), we just test that we can upgrade to a different impl.
        _emergencyUpgradeCall(
            proxyAdmin,
            abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(addresses.protocolUpgradeHandlerProxy), addresses.guardians, hex"")
            )
        );
    }

    // Ensures that the new ProtocolUpgradeHandler can call itself
    function test_MainnetForkSelfCall() external onlyMainnet {
        _emergencyUpgradeCall(
            addresses.protocolUpgradeHandlerProxy,
            abi.encodeCall(ProtocolUpgradeHandler.updateSecurityCouncil, (address(uint160(1))))
        );
    }
}