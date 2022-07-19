// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./TokenOperations.sol";

/**
 * @title GAME NFT
 */
contract NFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;

    address private serverAddress;
    address private _stakingContractAddress;
    uint256 private _maxCharacterId;
    uint256 private _maxCharacterTier;
    uint256 private _maxCharNumSameType; // Number of characters of the same type
    string private _customBaseURI;
    IERC20 private immutable _token;
    Counters.Counter private _tokenIdCounter;
    TokenManagement private immutable _tokenManagement;
    mapping(uint256 => uint256) private _charNumSameType;
    mapping(bytes32 => bool) private usedSalt;

    /**
     * @dev Emited in stakeMint and safeMint functions
     * @param to address of the user for whom owner mint NFT
     * @param characterId ID of game character
     * @param tokenId ID of NFT minted in function
     * @param amount amount of tokens used for mint
     */
    event Minted(
        address indexed to,
        uint256 indexed characterId,
        uint256 tokenId,
        uint256 amount
    );

    /**
     * @dev Emited in ownerMint function
     * @param to address of the user for whom owner mint NFT
     * @param characterId ID of game character
     * @param tier character level in the game
     * @param tokenId ID of NFT minted in function
     */
    event MintedWithTier(
        address indexed to,
        uint256 indexed characterId,
        uint256 indexed tier,
        uint256 tokenId
    );

    /**
     * @dev Creates a NFT contract.
     * @param token_ address of the IERC20/BEP20 token contract
     * @param tokenOperations_ address of the token Operations contract (for approve once all operations with tokens)
     */
    constructor(address token_, address tokenOperations_)
        ERC721("GAME NFT", "GNFT")
    {
        require(
            token_ != address(0) && tokenOperations_ != address(0x0),
            "Incorrect contracts addresses!"
        );
        _token = IERC20(token_);
        _tokenOperations = TokenOperations(tokenOperations_);
    }

    /**
     * @dev Overriding ERC721Enumerable function.
     * @param from param
     * @param to param
     * @param tokenId param
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Overriding ERC721Enumerable function.
     * @param interfaceId param
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Set Game stake contract address.
     * @param stakingContractAddress_ server address
     */
    function setStakingContractAddress(address stakingContractAddress_)
        external
        onlyOwner
    {
        _stakingContractAddress = stakingContractAddress_;
    }

    /**
     * @dev Set max character tier.
     * @param maxCharacterTier_ max character tier
     */
    function setMaxCharacterTier(uint256 maxCharacterTier_) external onlyOwner {
        _maxCharacterTier = maxCharacterTier_;
    }

    /**
     * @dev Set max number of characters of the same type.
     * @param maxCharNumSameType_ max number of characters of the same type
     */
    function setMaxCharNumSameType(uint256 maxCharNumSameType_)
        external
        onlyOwner
    {
        _maxCharNumSameType = maxCharNumSameType_;
    }

    /**
     * @notice Returns NFT's base URI
     * @return NFT's base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _customBaseURI;
    }

    /**
     * @dev Set NFT's base URI
     * @param baseURI_ NFT's base URIerver address
     */
    function setBaseURI(string memory baseURI_) external onlyOwner {
        _customBaseURI = baseURI_;
    }

    /**
     * @dev Set limit for characters ID's
     * @param maxCharacterId_ upper bound of the identifier interval
     */
    function setMaxCharacterId(uint256 maxCharacterId_) external onlyOwner {
        _maxCharacterId = maxCharacterId_;
    }

    /**
     * @dev Set server address.
     * @param _serverAddress server address
     */
    function setServerAddress(address _serverAddress) external onlyOwner {
        serverAddress = _serverAddress;
    }

    /**
     * @notice Returns array of user's token IDs
     * @param _user user address
     * @return array of user's token IDs
     */
    function walletOfUser(address _user)
        external
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_user);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_user, i);
        }
        return tokenIds;
    }

    /**
     * @notice Returns paginated array of user's token IDs
     * @param _user user address
     * @param _resultsPerPage number of tokens in result
     * @param _page number of page (starts form 1)
     * @return array of user's token IDs
     */
    function paginateWalletOfUser(
        address _user,
        uint256 _resultsPerPage,
        uint256 _page
    ) external view returns (uint256[] memory) {
        require(_resultsPerPage > 0, "Result per page must be greater than 0");
        require(_page > 0, "Pages starts from #1");
        uint256 ownerTokenCount = balanceOf(_user);
        uint256 lastElement = _resultsPerPage * _page;
        if (lastElement > ownerTokenCount) {
            lastElement = ownerTokenCount;
        }
        uint256[] memory tokenIds = new uint256[](_resultsPerPage);
        for (
            uint256 i = _resultsPerPage * _page - _resultsPerPage;
            i < lastElement;
            i++
        ) {
            tokenIds[i] = tokenOfOwnerByIndex(_user, i);
        }
        return tokenIds;
    }

    /**
     * @notice  Increases the number of characters per type when staking
     * @param _characterId character identifier
     */
    function stakeIncrement(uint256 _characterId) external {
        require(msg.sender == _stakingContractAddress, "Only for staking");
        require(
            _characterId < _maxCharacterId,
            "Character ID exceeds max character type"
        );
        require(
            _charNumSameType[_characterId] < _maxCharNumSameType,
            "Character count limit exceeded within type"
        );
        _charNumSameType[_characterId]++;
    }

    /**
     * @notice Mint by Owner new character for user
     * @param _to user address
     * @param _characterId character identifier
     * @param _tier character level in the game
     */
    function ownerMint(
        address _to,
        uint256 _characterId,
        uint256 _tier
    ) external onlyOwner {
        require(
            _characterId < _maxCharacterId,
            "Character ID exceeds max character type"
        );
        require(
            _charNumSameType[_characterId] < _maxCharNumSameType,
            "Character count limit exceeded within type"
        );
        require(
            _tier >= 1 && _tier <= _maxCharacterTier,
            "Character tier exceeds limit"
        );
        _charNumSameType[_characterId]++;
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(_to, tokenId);
        emit MintedWithTier(_to, _characterId, _tier, tokenId);
    }

    /**
     * @notice Mint after staking
     * @param _to user address
     * @param _characterId character identifier
     */
    function stakeMint(address _to, uint256 _characterId) external {
        require(msg.sender == _stakingContractAddress, "Only for staking");
        require(
            _characterId < _maxCharacterId,
            "Character ID exceeds max character type"
        );
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(_to, tokenId);
        emit Minted(_to, _characterId, tokenId, 0);
    }

    /**
     * @notice Mint for users for Tokens
     * @param _characterId character identifier
     * @param _salt random hash. Protection against replay attacks.
     * @param vrs signature
     */
    function safeMint(
        uint256 _characterId,
        uint256 _characterPrice,
        bytes32 _salt,
        bytes memory vrs
    ) external {
        require(!usedSalt[_salt], "Unauthorized access, re-entry");
        usedSalt[_salt] = true;
        bytes32 message = ECDSA.toEthSignedMessageHash(
            keccak256(abi.encodePacked(_characterId, _characterPrice, _salt))
        );
        require(
            ECDSA.recover(message, vrs) == serverAddress,
            "Unauthorized access"
        );
        require(
            _charNumSameType[_characterId] < _maxCharNumSameType,
            "Character count limit exceeded within type"
        );
        _charNumSameType[_characterId]++;
        address to = msg.sender;
        _tokenOperations.receiveTokensFromUser(to, _characterPrice);
        _tokenOperations.sendTokensToTreasury(_characterPrice);

        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        _safeMint(to, tokenId);
        emit Minted(to, _characterId, tokenId, _characterPrice);
    }
}
