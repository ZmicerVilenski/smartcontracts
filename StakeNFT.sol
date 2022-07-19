// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./NFT.sol";
import "./TokenOperations.sol";

/**
 * @title GameStake
 */
contract GameStake is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    address private serverAddress;
    uint256 private totalStaked;
    IERC20 private immutable token;
    NFT private immutable nft;
    TokenOperations private immutable tokenOperations;
    mapping(address => StakeInfo[]) private stakesInfo;
    mapping(address => uint256) private stakedByUser;
    mapping(bytes32 => bool) private usedSalt;
    // Stake data structure. Mapping from these structures is stored in the contract
    struct StakeInfo {
        bool active;
        uint256 stakeType; // type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
        uint256 id; // ID [0-Character1; 1-Character2; 2-Character3; 3-Character4...] || [0-2x_booster; 1-4x_booster] || [NFT id]
        uint256 timelock; // stake timelock
        uint256 amount; // amount of staked tokens
    }

    event stakedWithoutNFTOwnerChecking(
        address indexed _user,
        uint256 indexed _stakeType,
        uint256 indexed _id,
        uint256 _timelock,
        uint256 _amount,
        uint256 _stakeID
    );

    event stakedWithNFTOwnerChecking(
        address indexed _user,
        uint256 indexed _stakeType,
        uint256 indexed _id,
        uint256 _idNFT,
        uint256 _timelock,
        uint256 _amount,
        uint256 _stakeID
    );

    event userUnstaked(
        address indexed _user,
        uint256 indexed _stakeType,
        uint256 indexed _id,
        uint256 _amount
    );

    /**
     * @dev Throws if called by any accounts other than the service role or admin.
     */
    modifier onlyAdminOrService() {
        require(
            hasRole(ADMIN_ROLE, msg.sender) ||
                hasRole(SERVICE_ROLE, msg.sender),
            "No privileges for this operation"
        );
        _;
    }

    /**
     * @dev Creates a staking contract.
     * @param _token address of the IERC20/BEP20 token contract
     * @param _nft address of the IERC721/BEP721 NFT token contract
     * @param _tokenOperations address of the token Operations contract (used for approve once for all Token operations)
     */
    constructor(
        address _token,
        address _nft,
        address _tokenOperations
    ) {
        require(
            _token != address(0x0) &&
                _nft != address(0x0) &&
                _tokenOperations != address(0x0),
            "Incorrect contracts addresses!"
        );
        nft = NFT(_nft);
        token = IERC20(_token);
        tokenOperations = TokenOperations(_tokenOperations);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }

    // receive() external payable {}

    // fallback() external payable {}

    /**
     * @dev Set server address.
     * @param _serverAddress server address
     */
    function setServerAddress(address _serverAddress)
        external
        onlyAdminOrService
    {
        serverAddress = _serverAddress;
    }

    /**
     * @notice Returns the address of the ERC20/BEP20 token managed by the GameStake contract.
     */
    function getToken() external view returns (address) {
        return address(token);
    }

    /**
     * @notice Returns the address of the ERC721 (NFT) token managed by the GameStake contract.
     */
    function getNFT() external view returns (address) {
        return address(nft);
    }

    /**
     * @notice Returns array of all stakes of the user in structure
     * @param _staker user address
     */
    function getAllUserStakes(address _staker)
        public
        view
        returns (StakeInfo[] memory)
    {
        return stakesInfo[_staker];
    }

    /**
     * @notice Returns array of all stakes available for unstake
     * @param _staker user address
     */
    function getAllAvailableForUnstake(address _staker)
        public
        view
        returns (StakeInfo[] memory)
    {
        StakeInfo[] memory arrStakesInfo = stakesInfo[_staker];

        uint256 currentTime = block.timestamp;
        uint256 n = 0;
        for (uint256 i = 0; i < arrStakesInfo.length; i++) {
            if (
                arrStakesInfo[i].active &&
                arrStakesInfo[i].timelock < currentTime
            ) {
                n++;
            }
        }
        StakeInfo[] memory stakeInfoArray = new StakeInfo[](n);
        n = 0;
        for (uint256 i = 0; i < arrStakesInfo.length; i++) {
            if (
                arrStakesInfo[i].active &&
                arrStakesInfo[i].timelock < currentTime
            ) {
                stakeInfoArray[n] = arrStakesInfo[i];
                n++;
            }
        }
        return stakeInfoArray;
    }

    /**
     * @notice Returns array of active stakes in structure for a specific type
     * @param _staker user address
     * @param _stakeType type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
     */
    function getStakesPerType(address _staker, uint256 _stakeType)
        external
        view
        returns (StakeInfo[] memory)
    {
        StakeInfo[] memory arrStakesInfo = stakesInfo[_staker];
        uint256 currentTime = block.timestamp;
        uint256 n = 0;
        for (uint256 i = 0; i < arrStakesInfo.length; i++) {
            if (
                arrStakesInfo[i].active &&
                arrStakesInfo[i].timelock < currentTime &&
                arrStakesInfo[i].stakeType == _stakeType
            ) {
                n++;
            }
        }
        StakeInfo[] memory stakeInfoArray = new StakeInfo[](n);
        n = 0;
        for (uint256 i = 0; i < arrStakesInfo.length; i++) {
            if (
                arrStakesInfo[i].active &&
                arrStakesInfo[i].timelock < currentTime &&
                arrStakesInfo[i].stakeType == _stakeType
            ) {
                stakeInfoArray[n] = arrStakesInfo[i];
                n++;
            }
        }
        return stakeInfoArray;
    }

    /**
     * @notice Returns the total amount of tokens staked by user
     * @param _user user address
     */
    function getStakedByUser(address _user) external view returns (uint256) {
        return stakedByUser[_user];
    }

    /**
     * @notice Returns the total amount of tokens staked for all users
     */
    function getTotalStaked() external view returns (uint256) {
        return totalStaked;
    }

    /**
     * @notice Stake tokens.
     * @param _functionID calling function ID. In order for the vrs-signature for one function not to be replaced by a call to another function
     * @param _stakeType type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
     * @param _id ID [0-Character1; 1-Character2; 2-Character3; 3-Character4...] || [0-2x_booster; 1-4x_booster] || [NFT id]
     * @param _timelock stake timelock
     * @param _amount amount of staked tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs signature
     */
    function stake(
        uint256 _functionID,
        uint256 _stakeType,
        uint256 _id,
        uint256 _timelock,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) internal returns (uint256 _stakeID) {
        require(!usedSalt[_salt], "Unauthorized access, re-entry");
        usedSalt[_salt] = true;
        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    _functionID,
                    _stakeType,
                    _timelock,
                    _amount,
                    _salt
                )
            )
        );
        require(
            ECDSA.recover(message, vrs) == serverAddress,
            "Unauthorized access"
        );

        address staker = msg.sender;
        stakesInfo[staker].push(
            StakeInfo(true, _stakeType, _id, _timelock, _amount)
        );
        stakedByUser[staker] += _amount;
        totalStaked += _amount;
        _stakeID = stakesInfo[staker].length - 1;
        // transfer tokens from user account to TokenOperations contract
        tokenOperations.receiveTokensFromUser(staker, _amount);
    }

    /**
     * @notice Stake tokens without checking NFT owner.
     * @param _stakeType type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
     * @param _id ID [0-Character1; 1-Character2; 2-Character3; 3-Character4...] || [0-2x_booster; 1-4x_booster] || [NFT id]
     * @param _timelock stake timelock
     * @param _amount amount of staked tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs signature
     */
    function stakeWithoutNFTOwnerChecking(
        uint256 _stakeType,
        uint256 _id,
        uint256 _timelock,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        uint256 stakeID = stake(
            1,
            _stakeType,
            _id,
            _timelock,
            _amount,
            _salt,
            vrs
        );
        if (_stakeType == 1) {
            // Stake for NFT (Character) increase number of characters allowed for a mint within a type.
            // If the limit is already exceeded, it is forbidden to stake a new character.
            nft.stakeIncrement(_id);
        }
        emit stakedWithoutNFTOwnerChecking(
            msg.sender,
            _stakeType,
            _id,
            _timelock,
            _amount,
            stakeID
        );
    }

    /**
     * @notice Stake tokens with checking NFT owner.
     * @param _stakeType type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
     * @param _id ID [0-Character1; 1-Character2; 2-Character3; 3-Character4...] || [0-2x_booster; 1-4x_booster]
     * @param _idNFT [NFT id]
     * @param _timelock stake timelock
     * @param _amount amount of staked tokens
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs signature
     */
    function stakeWithNFTOwnerChecking(
        uint256 _stakeType,
        uint256 _id,
        uint256 _idNFT,
        uint256 _timelock,
        uint256 _amount,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        require(msg.sender == nft.ownerOf(_idNFT), "Not caller's NFT");
        uint256 stakeID = stake(
            2,
            _stakeType,
            _id,
            _timelock,
            _amount,
            _salt,
            vrs
        );
        emit stakedWithNFTOwnerChecking(
            msg.sender,
            _stakeType,
            _id,
            _idNFT,
            _timelock,
            _amount,
            stakeID
        );
    }

    /**
     * @notice Unstake tokens for all user's stakes.
     */
    function unstakeAll() external nonReentrant {
        address staker = msg.sender;
        StakeInfo[] storage arrStakesInfo = stakesInfo[staker];
        uint256 currentTime = block.timestamp;
        uint256 _unstakeAmount = 0;
        for (uint256 i = 0; i < arrStakesInfo.length; i++) {
            if (
                arrStakesInfo[i].active &&
                arrStakesInfo[i].timelock < currentTime &&
                arrStakesInfo[i].stakeType != 1 // type of staking [0-exp_booster; 1-random_nft; 2-skill_passive; 3-skill_active]
            ) {
                uint256 amount = arrStakesInfo[i].amount;
                _unstakeAmount += amount;
                arrStakesInfo[i].active = false;
                emit userUnstaked(
                    staker,
                    arrStakesInfo[i].stakeType,
                    i,
                    _unstakeAmount
                );
            }
        }
        stakedByUser[staker] -= _unstakeAmount;
        totalStaked -= _unstakeAmount;
        tokenOperations.sendTokensToUser(staker, _unstakeAmount);
    }

    /**
     * @notice Unstake tokens for a specific NFT.
     * @param _stakeID index in stake array
     */
    function unstakeNFT(uint256 _stakeID) external {
        address staker = msg.sender;
        StakeInfo[] storage arrStakesInfo = stakesInfo[staker];
        if (
            arrStakesInfo[_stakeID].active &&
            arrStakesInfo[_stakeID].timelock < block.timestamp
        ) {
            uint256 amount = arrStakesInfo[_stakeID].amount;
            stakedByUser[staker] -= amount;
            totalStaked -= amount;
            arrStakesInfo[_stakeID].active = false;
            tokenOperations.sendTokensToUser(staker, amount);

            nft.stakeMint(staker, arrStakesInfo[_stakeID].id);

            emit userUnstaked(staker, 1, _stakeID, amount);
        }
    }

    /**
     * @notice Unstake tokens for a specific stakeID.
     * @param _stakeID index in stake array
     */
    function unstakeById(uint256 _stakeID) external {
        address staker = msg.sender;
        StakeInfo[] storage arrStakesInfo = stakesInfo[staker];
        if (
            arrStakesInfo[_stakeID].active &&
            arrStakesInfo[_stakeID].timelock < block.timestamp
        ) {
            uint256 amount = arrStakesInfo[_stakeID].amount;
            stakedByUser[staker] -= amount;
            totalStaked -= amount;
            arrStakesInfo[_stakeID].active = false;
            tokenOperations.sendTokensToUser(staker, amount);

            emit userUnstaked(
                staker,
                arrStakesInfo[_stakeID].stakeType,
                _stakeID,
                amount
            );
        }
    }

    /**
     * @notice Unstake tokens for a specific stakeID.
     * @param _stakeIDsArray array of stake IDs
     */
    function unstakeByIDsArray(uint256[] memory _stakeIDsArray) external {
        address staker = msg.sender;
        StakeInfo[] storage arrStakesInfo = stakesInfo[staker];
        uint256 currentTime = block.timestamp;
        uint256 _unstakeAmount = 0;
        for (
            uint256 _stakeID = 0;
            _stakeID < _stakeIDsArray.length;
            _stakeID++
        ) {
            if (
                arrStakesInfo[_stakeID].active &&
                arrStakesInfo[_stakeID].timelock < currentTime
            ) {
                uint256 amount = arrStakesInfo[_stakeID].amount;
                _unstakeAmount += amount;
                arrStakesInfo[_stakeID].active = false;

                emit userUnstaked(
                    staker,
                    arrStakesInfo[_stakeID].stakeType,
                    _stakeID,
                    amount
                );
            }
        }
        stakedByUser[staker] -= _unstakeAmount;
        totalStaked -= _unstakeAmount;
        tokenOperations.sendTokensToUser(staker, _unstakeAmount);
    }
}
