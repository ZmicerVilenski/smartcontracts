// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFT is ERC721, AccessControl {
    using Counters for Counters.Counter;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    Counters.Counter private _tokenIdCounter;
    string private _customBaseURI;

    modifier onlyAdminOrService() {
        require(
            hasRole(ADMIN_ROLE, msg.sender) ||
                hasRole(SERVICE_ROLE, msg.sender),
            "No privileges for this operation"
        );
        _;
    }

    constructor() ERC721("Test MFNFT", "MFNFT") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view override returns (string memory) {
        return _customBaseURI;
    }

    function setBaseURI(string memory baseURI_) public onlyAdminOrService {
        _customBaseURI = baseURI_;
    }

    function safeMint(address to) public onlyAdminOrService {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    function grantServiceRole(address serviceRoleAddress_) public {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _setupRole(SERVICE_ROLE, serviceRoleAddress_);
    }
}
