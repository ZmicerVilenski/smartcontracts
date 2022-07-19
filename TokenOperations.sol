// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title TokenOperations, used for approve once for all Token operations
 */
contract TokenOperations is AccessControl {
    using SafeERC20 for IERC20;
    address private serverAddress;
    address private treasuryAddress;
    mapping(bytes32 => bool) private usedSalt;
    IERC20 private immutable token;
    bytes32 public constant PROJECT_CONTRACTS_ROLE =
        keccak256("PROJECT_CONTRACTS_ROLE");

    event boughtItem(
        address indexed buyer,
        uint256 indexed itemType,
        uint256 amount
    );

    /**
     * @dev Creates a token Operations contract.
     * @param _token address of the IERC20/BEP20 token contract
     */
    constructor(address _token) {
        require(_token != address(0x0));
        token = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Set server address.
     * @param _serverAddress server address
     */
    function setServerAddress(address _serverAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        serverAddress = _serverAddress;
    }

    /**
     * @dev Set project contracts addresses.
     * @param _address contract address
     */
    function setProjectContractAddress(address _address)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantRole(PROJECT_CONTRACTS_ROLE, _address);
    }

    /**
     * @dev Set treasury address.
     * @param _treasuryAddress treasury address
     */
    function setTreasuryAddress(address _treasuryAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        treasuryAddress = _treasuryAddress;
    }

    /**
     * @notice Returns treasury address.
     */
    function getTreasuryAddress() external view returns (address) {
        return address(treasuryAddress);
    }

    /**
     * @notice Receive Tokens from user. Used only by project contracts
     * @param _user user address
     * @param _amount amount of Tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs vrs signature from server
     */
    function receiveTokensFromUserWithSignature(
        address _user,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        require(!usedSalt[_salt], "Unauthorized access, re-entry");
        usedSalt[_salt] = true;

        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(_user, _amount, _salt))
        );
        require(
            ECDSA.recover(message, vrs) == serverAddress,
            "Unauthorized access"
        );
        token.transferFrom(_user, address(this), _amount);
    }

    /**
     * @notice Receive Tokens from user. Used only by contracts
     * @param _user user address
     * @param _amount amount of Tokens
     */
    function receiveTokensFromUser(address _user, uint256 _amount)
        external
        onlyRole(PROJECT_CONTRACTS_ROLE)
    {
        token.transferFrom(_user, address(this), _amount);
    }

    /**
     * @notice Receive Tokens from current user. Used by user to send tokens to the Token Operations balance
     * @param _amount amount of Tokens
     */
    function receiveTokensFromCurrentUser(uint256 _amount) external {
        token.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Send Tokens to user. Used only by contracts
     * @param _user user address
     * @param _amount amount of Tokens
     */
    function sendTokensToUser(address _user, uint256 _amount)
        external
        onlyRole(PROJECT_CONTRACTS_ROLE)
    {
        token.safeTransfer(_user, _amount);
    }

    /**
     * @notice Send Tokens to user. Used by user to claim specified by server amount. vrs signature needed
     * @param _user user address
     * @param _amount amount of Tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs vrs signature from server
     */
    function sendTokens(
        address _user,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        require(!usedSalt[_salt], "Unauthorized access, re-entry");
        usedSalt[_salt] = true;

        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(_user, _amount, _salt))
        );
        require(
            ECDSA.recover(message, vrs) == serverAddress,
            "Unauthorized access"
        );

        token.safeTransfer(_user, _amount);
    }

    /**
     * @notice Send Tokens to treasury balance. Used only by contracts
     * @param _amount amount of Tokens
     */
    function sendTokensToTreasury(uint256 _amount)
        external
        onlyRole(PROJECT_CONTRACTS_ROLE)
    {
        require(
            treasuryAddress != address(0x0),
            "Treasury address not defined"
        );
        token.safeTransfer(treasuryAddress, _amount);
    }

    /**
     * @notice Buy game items (experience booster etc.)
     * @param _type type of Item
     * @param _amount amount of Tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs vrs signature from server
     */
    function buyItem(
        uint256 _type,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        require(!usedSalt[_salt], "Unauthorized access, re-entry");
        usedSalt[_salt] = true;
        require(
            treasuryAddress != address(0x0),
            "Treasury address not defined"
        );

        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(_type, _amount, _salt))
        );
        require(
            ECDSA.recover(message, vrs) == serverAddress,
            "Unauthorized access"
        );
        token.safeTransferFrom(msg.sender, treasuryAddress, _amount);
        emit boughtItem(msg.sender, _type, _amount);
    }
}
