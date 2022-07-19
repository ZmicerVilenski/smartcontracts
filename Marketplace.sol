// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./BEP20.sol";
import "./NFT.sol";
import "./TokenOperations.sol";

/**
 * @title Marketplace
 */
contract Marketplace is ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 private _tradingFee;
    uint256 private _creatorFee;
    mapping(address => EnumerableSet.UintSet) private _tokenIdsOfSeller;
    mapping(uint256 => Ask) private _askDetails;
    Token private immutable token;
    NFT private immutable nft;
    TokenManagement private immutable tokenManagement;

    struct Ask {
        address seller; // address of the seller
        uint256 price; // price of the token
    }

    // Order is created
    event orderCreated(
        address indexed seller,
        uint256 indexed tokenId,
        uint256 price
    );

    // Order is cancelled
    event orderCancelled(address indexed seller, uint256 indexed tokenId);

    event bought(address buyer, uint256 tokenId, uint256 price);

    /**
     * @dev Creates a marketplace contract.
     * @param _token address of the IERC20/BEP20 token contract
     * @param _nft address of the IERC721/BEP721 NFT token contract
     * @param _tokenManagement address of the token management contract (for approve once all operations with BEP20 tokens)
     */
    constructor(
        address _token,
        address _nft,
        address _tokenManagement
    ) {
        require(
            _token != address(0x0) &&
                _nft != address(0x0) &&
                _tokenManagement != address(0x0),
            "Incorrect contracts addresses!"
        );
        nft = NFT(_nft);
        token = Token(_token);
        tokenManagement = TokenManagement(_tokenManagement);
    }

    /**
     * @notice Create order
     * @param _tokenId: tokenId of the NFT
     * @param _price: price for listing (in wei)
     */
    function createOrder(uint256 _tokenId, uint256 _price)
        external
        nonReentrant
    {
        require(_price > 0, "Order: Price cannot be zero");
        nft.safeTransferFrom(address(msg.sender), address(this), _tokenId);
        _tokenIdsOfSeller[msg.sender].add(_tokenId);
        _askDetails[_tokenId] = Ask({seller: msg.sender, price: _price});
        emit orderCreated(msg.sender, _tokenId, _price);
    }

    /**
     * @notice Cancel existing order
     * @param _tokenId: tokenId of the NFT
     */
    function cancelOrder(uint256 _tokenId) external nonReentrant {
        require(
            _tokenIdsOfSeller[msg.sender].contains(_tokenId),
            "Order: Token not listed"
        );
        _tokenIdsOfSeller[msg.sender].remove(_tokenId);
        delete _askDetails[_tokenId];
        nft.transferFrom(address(this), address(msg.sender), _tokenId);
        emit orderCancelled(msg.sender, _tokenId);
    }

    /**
     * @notice Buy token with BEP20 token by matching the price of an existing order
     * @param _tokenId: tokenId of the NFT purchased
     */
    function buy(uint256 _tokenId) external nonReentrant {
        Ask memory askOrder = _askDetails[_tokenId];
        require(
            _tokenIdsOfSeller[askOrder.seller].contains(_tokenId),
            "Buy: Not for sale"
        );
        uint256 _price = askOrder.price;
        tokenManagement.receiveTokensFromUser(address(msg.sender), _price);
        require(msg.sender != askOrder.seller, "Buy: Buyer cannot be seller");
        _tokenIdsOfSeller[askOrder.seller].remove(_tokenId);
        delete _askDetails[_tokenId];
        tokenManagement.sendTokensToUser(askOrder.seller, _price);
        nft.safeTransferFrom(address(this), address(msg.sender), _tokenId);
        emit bought(msg.sender, _tokenId, _price);
    }
}
