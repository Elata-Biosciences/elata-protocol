// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Errors {
    error NotAuthorized();
    error ZeroAddress();
    error InvalidAmount();
    error CapExceeded();
    error TransfersDisabled();
    error LockActive();
    error NoActiveLock();
    error LockTooShort();
    error LockTooLong();
    error LockNotExpired();
    error VotingClosed();
    error VotingNotStarted();
    error InsufficientXP();
    error ArrayLengthMismatch();
    error DuplicateOption();
    error SignatureExpired();
    error InvalidSignature();
}
