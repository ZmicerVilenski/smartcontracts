// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./War.sol";

interface IWar {
    function addManyToWarAndPack(address account, uint16[] calldata tokenIds)
        external;

    function randomOfficerOwner(uint256 seed) external view returns (address);

    function war(uint256)
        external
        view
        returns (
            uint16,
            uint80,
            address
        );

    function totalGoldEarned() external view returns (uint256);

    function lastClaimTimestamp() external view returns (uint256);

    function setOldTokenInfo(uint256 _tokenId) external;

    function pack(uint256, uint256) external view returns (War.Stake memory);

    function packIndices(uint256) external view returns (uint256);
}
