// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "./IERC721Receiver.sol";
import "./Pauseable.sol";
import "./OffecersAndSoldiers.sol";
import "./GOLD.sol";

contract War is Ownable, IERC721Receiver, Pauseable {
    // maximum alpha score for an Officers
    uint8 public constant MAX_ALPHA = 8;

    // struct to store a stake's token, owner, and earning values
    struct Stake {
        uint16 tokenId;
        uint80 value;
        address owner;
    }

    event TokenStaked(address owner, uint256 tokenId, uint256 value);
    event SoldierClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event OfficerClaimed(uint256 tokenId, uint256 earned, bool unstaked);

    // reference to the OffecersAndSoldiers NFT contract
    OffecersAndSoldiers game;
    // reference to the $GOLD contract for minting $GOLD earnings
    GOLD gold;

    // maps tokenId to stake
    mapping(uint256 => Stake) public war;
    // maps alpha to all Officers stakes with that alpha
    mapping(uint256 => Stake[]) public pack;
    // tracks location of each Officers in Pack
    mapping(uint256 => uint256) public packIndices;
    // total alpha scores staked
    uint256 public totalAlphaStaked = 0;
    // any rewards distributed when no wolves are staked
    uint256 public unaccountedRewards = 0;
    // amount of $GOLD due for each alpha point staked
    uint256 public goldPerAlpha = 0;

    // soldier earn 10000 $GOLD per day
    uint256 public DAILY_GOLD_RATE = 10000 ether;
    // soldier must have 2 days worth of $GOLD to unstake or else it's too cold
    uint256 public MINIMUM_TO_EXIT = 2 days;
    // officer take a 20% tax on all $GOLD claimed
    uint256 public constant GOLD_CLAIM_TAX_PERCENTAGE = 20;
    // there will only ever be (roughly) 2.4 billion $GOLD earned through staking
    uint256 public constant MAXIMUM_GLOBAL_GOLD = 2400000000 ether;

    // amount of $GOLD earned so far
    uint256 public totalgoldEarned;
    // number of soldiers staked in the war
    uint256 public totalSoldierStaked;
    // the last time $GOLD was claimed
    uint256 public lastClaimTimestamp;

    // emergency rescue to allow unstaking without any checks but without $GOLD
    bool public rescueEnabled = false;

    bool private _reentrant = false;

    modifier nonReentrant() {
        require(!_reentrant, "No reentrancy");
        _reentrant = true;
        _;
        _reentrant = false;
    }

    /**
     * @param _game reference to the OffecersAndSoldiers NFT contract
     * @param _gold reference to the $GOLD token
     */
    constructor(OffecersAndSoldiers _game, GOLD _gold) {
        game = _game;
        gold = _gold;
    }

    /***STAKING */

    /**
     * adds Soldiers and Officers to the War and Pack
     * @param account the address of the staker
     * @param tokenIds the IDs of the Soldiers and Officers to stake
     */
    function addManyToWarAndPack(address account, uint16[] calldata tokenIds)
        external
        nonReentrant
    {
        require(
            (account == _msgSender() && account == tx.origin) ||
                _msgSender() == address(game),
            "DONT GIVE YOUR TOKENS AWAY"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == 0) {
                continue;
            }

            if (_msgSender() != address(game)) {
                // dont do this step if its a mint + stake
                require(
                    game.ownerOf(tokenIds[i]) == _msgSender(),
                    "AINT YO TOKEN"
                );
                game.transferFrom(_msgSender(), address(this), tokenIds[i]);
            }

            if (isSoldier(tokenIds[i])) _addSoldierToWar(account, tokenIds[i]);
            else _addOfficerToPack(account, tokenIds[i]);
        }
    }

    /**
     * adds a single Soldier to the War
     * @param account the address of the staker
     * @param tokenId the ID of the Soldier to add to the War
     */
    function _addSoldierToWar(address account, uint256 tokenId)
        internal
        whenNotPaused
        _updateEarnings
    {
        war[tokenId] = Stake({
            owner: account,
            tokenId: uint16(tokenId),
            value: uint80(block.timestamp)
        });
        totalSoldierStaked += 1;
        emit TokenStaked(account, tokenId, block.timestamp);
    }

    /**
     * adds a single Officer to the Pack
     * @param account the address of the staker
     * @param tokenId the ID of the Officer to add to the Pack
     */
    function _addOfficerToPack(address account, uint256 tokenId) internal {
        uint256 alpha = _alphaForOfficer(tokenId);
        totalAlphaStaked += alpha;
        // Portion of earnings ranges from 8 to 5
        packIndices[tokenId] = pack[alpha].length;
        // Store the location of the officer in the Pack
        pack[alpha].push(
            Stake({
                owner: account,
                tokenId: uint16(tokenId),
                value: uint80(goldPerAlpha)
            })
        );
        // Add the officer to the Pack
        emit TokenStaked(account, tokenId, goldPerAlpha);
    }

    /***CLAIMING / UNSTAKING */

    /**
     * realize $GOLD earnings and optionally unstake tokens from the War / Pack
     * to unstake a Soldier it will require it has 2 days worth of $GOLD unclaimed
     * @param tokenIds the IDs of the tokens to claim earnings from
     * @param unstake whether or not to unstake ALL of the tokens listed in tokenIds
     */
    function claimManyFromWarAndPack(uint16[] calldata tokenIds, bool unstake)
        external
        nonReentrant
        whenNotPaused
        _updateEarnings
    {
        require(msg.sender == tx.origin, "Only EOA");
        uint256 owed = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (isSoldier(tokenIds[i]))
                owed += _claimSoldierFromWar(tokenIds[i], unstake);
            else owed += _claimOffecerFromPack(tokenIds[i], unstake);
        }
        if (owed == 0) return;
        gold.mint(_msgSender(), owed);
    }

    /**
     * realize $GOLD earnings for a single Soldier and optionally unstake it
     * if not unstaking, pay a 20% tax to the staked Offecers
     * if unstaking, there is a 50% chance all $GOLD
     * @param tokenId the ID of the Soldier to claim earnings from
     * @param unstake whether or not to unstake the Soldier
     * @return owed - the amount of $GOLD earned
     */
    function _claimSoldierFromWar(uint256 tokenId, bool unstake)
        internal
        returns (uint256 owed)
    {
        Stake memory stake = war[tokenId];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        require(
            !(unstake && block.timestamp - stake.value < MINIMUM_TO_EXIT),
            "GONNA BE COLD WITHOUT TWO DAY'S GOLD"
        );
        if (totalgoldEarned < MAXIMUM_GLOBAL_GOLD) {
            owed = ((block.timestamp - stake.value) * DAILY_GOLD_RATE) / 1 days;
        } else if (stake.value > lastClaimTimestamp) {
            owed = 0;
            // $GOLD production stopped already
        } else {
            owed =
                ((lastClaimTimestamp - stake.value) * DAILY_GOLD_RATE) /
                1 days;
            // stop earning additional $GOLD if it's all been earned
        }
        if (unstake) {
            if (random(tokenId) & 1 == 1) {
                // 50% chance of all $GOLD earned
                _payOfficerTax(owed);
                owed = 0;
            }
            game.transferFrom(address(this), _msgSender(), tokenId);
            // send back Soldier
            delete war[tokenId];
            totalSoldierStaked -= 1;
        } else {
            _payOfficerTax((owed * GOLD_CLAIM_TAX_PERCENTAGE) / 100);
            // percentage tax to staked officers
            owed = (owed * (100 - GOLD_CLAIM_TAX_PERCENTAGE)) / 100;
            // remainder goes to Soldier owner
            war[tokenId] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(block.timestamp)
            });
            // reset stake
        }
        emit SoldierClaimed(tokenId, owed, unstake);
    }

    /**
     * realize $GOLD earnings for a single Offecer and optionally unstake it
     * Offecers earn $GOLD proportional to their Alpha rank
     * @param tokenId the ID of the Offecer to claim earnings from
     * @param unstake whether or not to unstake the Offecer
     * @return owed - the amount of $GOLD earned
     */
    function _claimOffecerFromPack(uint256 tokenId, bool unstake)
        internal
        returns (uint256 owed)
    {
        require(
            game.ownerOf(tokenId) == address(this),
            "AINT A PART OF THE PACK"
        );
        uint256 alpha = _alphaForOfficer(tokenId);
        Stake memory stake = pack[alpha][packIndices[tokenId]];
        require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
        owed = (alpha) * (goldPerAlpha - stake.value);
        // Calculate portion of tokens based on Alpha
        if (unstake) {
            totalAlphaStaked -= alpha;
            // Remove Alpha from total staked
            game.transferFrom(address(this), _msgSender(), tokenId);
            // Send back Officer
            Stake memory lastStake = pack[alpha][pack[alpha].length - 1];
            pack[alpha][packIndices[tokenId]] = lastStake;
            // Shuffle last Officer to current position
            packIndices[lastStake.tokenId] = packIndices[tokenId];
            pack[alpha].pop();
            // Remove duplicate
            delete packIndices[tokenId];
            // Delete old mapping
        } else {
            pack[alpha][packIndices[tokenId]] = Stake({
                owner: _msgSender(),
                tokenId: uint16(tokenId),
                value: uint80(goldPerAlpha)
            });
            // reset stake
        }
        emit OfficerClaimed(tokenId, owed, unstake);
    }

    /**
     * emergency unstake tokens
     * @param tokenIds the IDs of the tokens to claim earnings from
     */
    function rescue(uint256[] calldata tokenIds) external nonReentrant {
        require(rescueEnabled, "RESCUE DISABLED");
        uint256 tokenId;
        Stake memory stake;
        Stake memory lastStake;
        uint256 alpha;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            if (isSoldier(tokenId)) {
                stake = war[tokenId];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                game.transferFrom(address(this), _msgSender(), tokenId);
                // send back Soldier
                delete war[tokenId];
                totalSoldierStaked -= 1;
                emit SoldierClaimed(tokenId, 0, true);
            } else {
                alpha = _alphaForOfficer(tokenId);
                stake = pack[alpha][packIndices[tokenId]];
                require(stake.owner == _msgSender(), "SWIPER, NO SWIPING");
                totalAlphaStaked -= alpha;
                // Remove Alpha from total staked
                game.transferFrom(address(this), _msgSender(), tokenId);
                // Send back Officers
                lastStake = pack[alpha][pack[alpha].length - 1];
                pack[alpha][packIndices[tokenId]] = lastStake;
                // Shuffle last Officer to current position
                packIndices[lastStake.tokenId] = packIndices[tokenId];
                pack[alpha].pop();
                // Remove duplicate
                delete packIndices[tokenId];
                // Delete old mapping
                emit OfficerClaimed(tokenId, 0, true);
            }
        }
    }

    /***ACCOUNTING */

    /**
     * add $GOLD to claimable pot for the Pack
     * @param amount $GOLD to add to the pot
     */
    function _payOfficerTax(uint256 amount) internal {
        if (totalAlphaStaked == 0) {
            // if there's no staked officers
            unaccountedRewards += amount;
            // keep track of $GOLD due to officers
            return;
        }
        // makes sure to include any unaccounted $GOLD
        goldPerAlpha += (amount + unaccountedRewards) / totalAlphaStaked;
        unaccountedRewards = 0;
    }

    /**
     * tracks $GOLD earnings to ensure it stops once 2.4 billion is eclipsed
     */
    modifier _updateEarnings() {
        if (totalgoldEarned < MAXIMUM_GLOBAL_GOLD) {
            totalgoldEarned +=
                ((block.timestamp - lastClaimTimestamp) *
                    totalSoldierStaked *
                    DAILY_GOLD_RATE) /
                1 days;
            lastClaimTimestamp = block.timestamp;
        }
        _;
    }

    /***ADMIN */

    function setSettings(uint256 rate, uint256 exit) external onlyOwner {
        MINIMUM_TO_EXIT = exit;
        DAILY_GOLD_RATE = rate;
    }

    /**
     * allows owner to enable "rescue mode"
     * simplifies accounting, prioritizes tokens out in emergency
     */
    function setRescueEnabled(bool _enabled) external onlyOwner {
        rescueEnabled = _enabled;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    /***READ ONLY */

    /**
     * checks if a token is a Soldier
     * @param tokenId the ID of the token to check
     * @return soldier - whether or not a token is a Soldier
     */
    function isSoldier(uint256 tokenId) public view returns (bool soldier) {
        (soldier, , , , , , , , ) = game.tokenTraits(tokenId);
    }

    /**
     * gets the alpha score for an Offecer
     * @param tokenId the ID of the Offecer to get the alpha score for
     * @return the alpha score of the Offecer (5-8)
     */
    function _alphaForOfficer(uint256 tokenId) internal view returns (uint8) {
        (, , , , , , , , uint8 alphaIndex) = game.tokenTraits(tokenId);
        return MAX_ALPHA - alphaIndex;
        // alpha index is 0-3
    }

    /**
     * chooses a random Offecer soldier when a newly minted token is earned
     * @param seed a random value to choose a Offecer from
     * @return the owner of the randomly selected Offecer soldier
     */
    function randomOffecerOwner(uint256 seed) external view returns (address) {
        if (totalAlphaStaked == 0) return address(0x0);
        uint256 bucket = (seed & 0xFFFFFFFF) % totalAlphaStaked;
        // choose a value from 0 to total alpha staked
        uint256 cumulative;
        seed >>= 32;
        // loop through each bucket of Officers with the same alpha score
        for (uint256 i = MAX_ALPHA - 3; i <= MAX_ALPHA; i++) {
            cumulative += pack[i].length * i;
            // if the value is not inside of that bucket, keep going
            if (bucket >= cumulative) continue;
            // get the address of a random Offecer with that alpha score
            return pack[i][seed % pack[i].length].owner;
        }
        return address(0x0);
    }

    /**
     * generates a pseudorandom number
     * @param seed a value ensure different outcomes for different sources in the same block
     * @return a pseudorandom value
     */
    function random(uint256 seed) internal view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        tx.origin,
                        blockhash(block.number - 1),
                        block.timestamp,
                        seed,
                        totalSoldierStaked,
                        totalAlphaStaked,
                        lastClaimTimestamp
                    )
                )
            ) ^ game.randomSource().seed();
    }

    function onERC721Received(
        address,
        address from,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        require(from == address(0x0), "Cannot send tokens to Barn directly");
        return IERC721Receiver.onERC721Received.selector;
    }
}
