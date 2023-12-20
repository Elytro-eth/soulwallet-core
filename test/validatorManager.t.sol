// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IOwnerManager} from "../contracts/interface/IOwnerManager.sol";
import {BasicModularAccount} from "../examples/BasicModularAccount.sol";
import {Execution} from "../contracts/interface/IStandardExecutor.sol";
import "../contracts/validators/EOAValidator.sol";
import {ReceiverHandler} from "./dev/ReceiverHandler.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {DeployEntryPoint} from "./dev/deployEntryPoint.sol";
import {SoulWalletFactory} from "./dev/SoulWalletFactory.sol";
import {UserOperation} from "@account-abstraction/contracts/interfaces/UserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "../contracts/utils/Constants.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ValidatorManagerTest is Test {
    using MessageHashUtils for bytes32;

    IEntryPoint entryPoint;

    SoulWalletFactory walletFactory;
    BasicModularAccount walletImpl;

    EOAValidator validator;
    ReceiverHandler _fallback;

    address public walletOwner;
    uint256 public walletOwnerPrivateKey;

    BasicModularAccount wallet;

    function setUp() public {
        entryPoint = new DeployEntryPoint().deploy();
        walletImpl = new BasicModularAccount(address(entryPoint));
        walletFactory = new SoulWalletFactory(address(walletImpl), address(entryPoint), address(this));
        validator = new EOAValidator();
        _fallback = new ReceiverHandler();
        (walletOwner, walletOwnerPrivateKey) = makeAddrAndKey("owner1");

        bytes32 salt = 0;
        bytes memory initializer;
        {
            bytes32 owner = bytes32(uint256(uint160(walletOwner)));
            address defaultValidator = address(validator);
            address defaultFallback = address(_fallback);
            initializer = abi.encodeWithSelector(
                BasicModularAccount.initialize.selector, owner, defaultValidator, defaultFallback
            );
        }

        wallet = BasicModularAccount(payable(walletFactory.createWallet(initializer, salt)));
    }

    event InitCalled(bytes data);
    event DeInitCalled();

    error CALLER_MUST_BE_SELF_OR_MODULE();
    error INVALID_HOOK();
    error INVALID_HOOK_TYPE();
    error HOOK_NOT_EXISTS();
    error INVALID_HOOK_SIGNATURE();

    function _packHash(address account, bytes32 hash) private view returns (bytes32) {
        uint256 _chainid;
        assembly {
            _chainid := chainid()
        }
        return keccak256(abi.encode(hash, account, _chainid));
    }

    function _packSignature(address validatorAddress, bytes memory signature) private pure returns (bytes memory) {
        uint32 sigLen = uint32(signature.length);
        return abi.encodePacked(validatorAddress, sigLen, signature);
    }

    function getUserOpHash(UserOperation memory userOp) private view returns (bytes32) {
        return entryPoint.getUserOpHash(userOp);
    }

    function signUserOp(UserOperation memory userOperation) private view returns (bytes32 userOpHash) {
        userOpHash = getUserOpHash(userOperation);
        bytes32 hash = _packHash(userOperation.sender, userOpHash).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletOwnerPrivateKey, hash);
        bytes memory _signature = _packSignature(address(validator), abi.encodePacked(r, s, v));
        userOperation.signature = _signature;
    }

    function newUserOp(address sender) private pure returns (UserOperation memory) {
        uint256 nonce = 0;
        bytes memory initCode;
        bytes memory callData;
        uint256 callGasLimit;
        uint256 verificationGasLimit = 1e6;
        uint256 preVerificationGas = 1e5;
        uint256 maxFeePerGas = 100 gwei;
        uint256 maxPriorityFeePerGas = 100 gwei;
        bytes memory paymasterAndData;
        bytes memory signature;
        UserOperation memory userOperation = UserOperation(
            sender,
            nonce,
            initCode,
            callData,
            callGasLimit,
            verificationGasLimit,
            preVerificationGas,
            maxFeePerGas,
            maxPriorityFeePerGas,
            paymasterAndData,
            signature
        );
        return userOperation;
    }

    error INVALID_VALIDATOR();
    error ADDRESS_ALREADY_EXISTS();

    function test_Validator() public {
        address[] memory validators = wallet.listValidator();
        assertEq(validators.length, 1);

        vm.expectRevert(CALLER_MUST_BE_SELF_OR_MODULE.selector);
        wallet.installValidator(address(this));

        vm.startPrank(address(wallet));
        vm.expectRevert(INVALID_VALIDATOR.selector);
        wallet.installValidator(address(this));
        vm.stopPrank();

        vm.startPrank(address(wallet));
        vm.expectRevert(ADDRESS_ALREADY_EXISTS.selector);
        wallet.installValidator(address(validator));
        vm.stopPrank();

        EOAValidator validator2 = new EOAValidator();
        vm.startPrank(address(wallet));
        wallet.installValidator(address(validator2));
        validators = wallet.listValidator();
        assertEq(validators.length, 2);
        vm.stopPrank();

        vm.expectRevert(CALLER_MUST_BE_SELF_OR_MODULE.selector);
        wallet.uninstallValidator(address(validator));

        vm.startPrank(address(wallet));
        wallet.uninstallValidator(address(validator));
        validators = wallet.listValidator();
        assertEq(validators.length, 1);
        vm.stopPrank();

        UserOperation memory userOperation = newUserOp(address(wallet));
        userOperation.nonce = 1;
        userOperation.callGasLimit = 200000;
        // function execute(address target, uint256 value, bytes calldata data) external payable;
        userOperation.callData = abi.encodeWithSelector(walletImpl.execute.selector, address(10), 1 ether, "");
        userOperation.verificationGasLimit = 1e6;
        userOperation.preVerificationGas = 1e5;
        userOperation.maxFeePerGas = 100 gwei;
        userOperation.maxPriorityFeePerGas = 100 gwei;

        // function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        vm.startPrank(address(entryPoint));

        bytes32 userOpHash = signUserOp(userOperation);

        assertEq(wallet.validateUserOp(userOperation, userOpHash, 1), SIG_VALIDATION_FAILED);
        vm.startPrank(address(wallet));
        wallet.installValidator(address(validator));
        vm.stopPrank();

        vm.prank(address(entryPoint));
        assertEq(wallet.validateUserOp(userOperation, userOpHash, 1), SIG_VALIDATION_SUCCESS);
    }
}
