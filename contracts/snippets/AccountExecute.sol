// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";

abstract contract AccountExecuteSnippet {
    /**
     * Account may implement this execute method.
     * passing this methodSig at the beginning of callData will cause the entryPoint to pass the full UserOp (and hash)
     * to the account.
     * The account should skip the methodSig, and use the callData (and optionally, other UserOp fields)
     *
     * @param userOp              - The operation that was just validated.
     * @param userOpHash          - Hash of the user's request data.
     *
     */
    function _executeUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) internal virtual;
}
