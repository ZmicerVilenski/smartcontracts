// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Vesting
 */
contract Vesting is ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // Investor data structure. Mapping from these structures is stored in the contract, it is filled before the start of vesting
    struct InvestorData {
        bool cliffPaid;
        address investor; // investor address
        uint256 amount; // amount of tokens to be released at the end of the vesting except for amount paid after the cliff
        uint256 released; // amount of tokens released
        uint256 amountAfterCliff; // amount paid after cliff, must be calculated outside the contract from the percentage (cliffPercent)
        uint256 phaseID; // ID of the vesting phase, for each phase set a unique number outside the contract
    }

    // The structure of the vesting phases. Mapping from these structures is stored in the contract, it is filled before the start of vesting
    struct VestingPhase {
        uint256 start; // start time of the vesting period
        uint256 duration; // duration of the vesting period arter cliff in seconds (total duration - cliff)
        uint256 cliff; // cliff period in seconds
        uint256 cliffPercent; // % after cliff period (multiply by 10, because could be fractional percentage, like - 7.5)
        uint256 slicePeriodSeconds; // duration of a slice period in seconds
        string phaseName; // name of the vesting phase
    }

    // The full structure of vesting in the context of the investor. Not stored in the contract, but returned upon request from the web application
    struct VestingSchedule {
        bool cliffPaid;
        address investor; // investor address
        uint256 cliff; // cliff period in seconds
        uint256 cliffPercent; // % after cliff period (multiply by 10, because could be fractional percentage, like - 7,5)
        uint256 amountAfterCliff; // amount paid after cliff
        uint256 start; // start time of the vesting period
        uint256 duration; // duration of the vesting period arter cliff in seconds
        uint256 slicePeriodSeconds; // duration of a slice period for the vesting in seconds
        uint256 amount; // amount of tokens to be released at the end of the vesting except for percentages after the cliff
        uint256 released; // amount of tokens released exept cliff percent
        uint256 releasedTotal; // total amount of tokens released with cliff percent
        uint256 releasableAmount; // amount of tokens ready for claim now
        uint256 phaseID; // ID of the vesting phase
        string phaseName; // name of the vesting phase
    }

    IERC20 private immutable _token;
    // Create a new role identifier for the admin role
    bytes32 public constant STAGE_ADJUSTMENT_ROLE =
        keccak256("STAGE_ADJUSTMENT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(bytes32 => InvestorData) private investorsData;
    mapping(uint256 => VestingPhase) private vestingPhases;
    uint256 private vestingTotalAmount;
    mapping(address => uint256) private holdersVestingCount;

    event Released(address indexed investor, uint256 amount);

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfNotRevoked(bytes32 investorDataId) {
        require(investorsData[investorDataId].amount > 0);
        _;
    }

    /**
     * @dev Throws if called by any accounts other than the SA (stage adjustment) or admin.
     */
    modifier onlyAdminOrSA() {
        require(
            hasRole(ADMIN_ROLE, msg.sender) ||
                hasRole(STAGE_ADJUSTMENT_ROLE, msg.sender),
            "Caller is not an admin and has no stage adjustment role"
        );
        _;
    }

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the IERC20/BEP20 token contract
     */
    constructor(address token_) {
        require(token_ != address(0x0));
        _token = IERC20(token_);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice Returns the total amount of vesting.
     * @return the total amount of vesting
     */
    function getvestingTotalAmount() external view returns (uint256) {
        return vestingTotalAmount;
    }

    /**
     * @dev Returns the number of vesting schedules associated to an investor.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByInvestor(address _investor)
        external
        view
        returns (uint256)
    {
        return holdersVestingCount[_investor];
    }

    /**
     * @notice Returns the investor data information for a given holder and index.
     * @return the investor data structure information
     */
    function getInvestorDataByAddressAndIndex(address holder, uint256 index)
        external
        view
        returns (InvestorData memory)
    {
        return
            getInvestorData(
                computeInvestorDataIdForAddressAndIndex(holder, index)
            );
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index)
        public
        view
        returns (VestingSchedule memory)
    {
        InvestorData memory investorData = getInvestorData(
            computeInvestorDataIdForAddressAndIndex(holder, index)
        );
        uint256 releasedTotal = investorData.released;
        if (investorData.cliffPaid) {
            releasedTotal = releasedTotal + investorData.amountAfterCliff;
        }
        VestingPhase memory vestingPhase = vestingPhases[investorData.phaseID];
        return
            VestingSchedule(
                investorData.cliffPaid,
                investorData.investor,
                vestingPhase.cliff,
                vestingPhase.cliffPercent,
                investorData.amountAfterCliff,
                vestingPhase.start,
                vestingPhase.duration,
                vestingPhase.slicePeriodSeconds,
                investorData.amount,
                investorData.released,
                releasedTotal,
                _computeReleasableAmount(investorData),
                investorData.phaseID,
                vestingPhase.phaseName
            );
    }

    /**
     * @notice Returns the array of vesting schedules for a given holder.
     * @return the array of vesting schedule structures
     * @param _investor address of investor
     */
    function getScheduleArrayByInvestor(address _investor)
        external
        view
        returns (VestingSchedule[] memory)
    {
        uint256 vestingSchedulesCount = holdersVestingCount[_investor];
        VestingSchedule[] memory schedulesArray = new VestingSchedule[](
            vestingSchedulesCount
        );
        for (uint256 i = 0; i < vestingSchedulesCount; i++) {
            schedulesArray[i] = getVestingScheduleByAddressAndIndex(
                _investor,
                i
            );
        }
        return schedulesArray;
    }

    /**
     * @dev Returns the address of the IERC20/BEP20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @notice Creates a new vesting phase.
     * @param _phaseId ID of vesting phase
     * @param _start start time of the vesting period
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _cliffPercent % of token amount could be clamed after the cliff
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _phaseName name of the vesting phase
     */
    function createVestingPhase(
        uint256 _phaseId,
        uint256 _start,
        uint256 _duration,
        uint256 _cliff,
        uint256 _cliffPercent,
        uint256 _slicePeriodSeconds,
        string memory _phaseName
    ) external onlyAdminOrSA {
        require(_duration >= 0, "Vesting: duration must be >= 0");
        require(
            _slicePeriodSeconds >= 1,
            "Vesting: slicePeriodSeconds must be >= 1"
        );
        vestingPhases[_phaseId] = VestingPhase(
            _start,
            _duration,
            _start + _cliff,
            _cliffPercent,
            _slicePeriodSeconds,
            _phaseName
        );
    }

    /**
     * @notice Change vesting phase.
     * @param _phaseId ID of vesting phase
     * @param _start start time of the vesting period
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _cliffPercent % of token amount could be clamed after the cliff
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _phaseName name of the vesting phase
     */
    function changeVestingPhase(
        uint256 _phaseId,
        uint256 _start,
        uint256 _duration,
        uint256 _cliff,
        uint256 _cliffPercent,
        uint256 _slicePeriodSeconds,
        string memory _phaseName
    ) external onlyAdminOrSA {
        require(_duration >= 0, "Vesting: duration must be >= 0");
        require(
            _slicePeriodSeconds >= 1,
            "Vesting: slicePeriodSeconds must be >= 1"
        );
        VestingPhase storage vestingPhase = vestingPhases[_phaseId];
        vestingPhase.start = _start;
        vestingPhase.duration = _duration;
        vestingPhase.cliff = _start + _cliff;
        vestingPhase.cliffPercent = _cliffPercent;
        vestingPhase.slicePeriodSeconds = _slicePeriodSeconds;
        vestingPhase.phaseName = _phaseName;
    }

    /**
     * @notice Creates a new vesting schedule for an investor.
     * @param _investor address of the investor to whom vested tokens are transferred
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @param _cliffPercent percent from total amount to be payd after cliff
     * @param _phaseID ID of the vesting phase
     */
    function addInvestor(
        address _investor,
        uint256 _amount,
        uint256 _cliffPercent,
        uint256 _phaseID
    ) external onlyAdminOrSA {
        require(_amount > 0, "Vesting: amount must be > 0");
        bytes32 investorDataId = computeNextinvestorDataIdForHolder(_investor);
        uint256 _amountAfterCliff = (_amount * _cliffPercent) / 1000;

        investorsData[investorDataId] = InvestorData(
            false,
            _investor,
            _amount - _amountAfterCliff,
            0,
            _amountAfterCliff,
            _phaseID
        );
        vestingTotalAmount = vestingTotalAmount + _amount;
        holdersVestingCount[_investor] += 1;
    }

    /**
     * @notice Cancels an existing schedule by resetting the amount
     * @param investorDataId the vesting schedule identifier
     */
    function cancelInvestorSchedule(bytes32 investorDataId)
        external
        onlyAdminOrSA
    {
        InvestorData storage investorData = investorsData[investorDataId];
        vestingTotalAmount =
            vestingTotalAmount -
            ((investorData.amount + investorData.amountAfterCliff) -
                investorData.released);
        investorData.amount = 0;
        investorData.amountAfterCliff = 0;
        investorData.cliffPaid = true;
    }

    /**
     * @notice Change an existing schedule by overwriting all parameters
     * @param investorDataId the vesting schedule identifier
     * @param _cliffPaid was the amount paid after the cliff
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @param _released how much has already been paid to the investor
     * @param _cliffPercent percent from total amount to be payd after cliff
     * @param _phaseID ID of the vesting phase
     */
    function changeInvestorSchedule(
        bytes32 investorDataId,
        bool _cliffPaid,
        uint256 _amount,
        uint256 _released,
        uint256 _cliffPercent,
        uint256 _phaseID
    ) external onlyAdminOrSA {
        uint256 _amountAfterCliff = (_amount * _cliffPercent) / 1000;
        InvestorData storage investorData = investorsData[investorDataId];

        if (_released == 0) {
            _released = investorData.released;
        }
        if (_phaseID == 0) {
            _phaseID = investorData.phaseID;
        }

        vestingTotalAmount =
            vestingTotalAmount -
            ((investorData.amount + investorData.amountAfterCliff) -
                investorData.released);

        investorData.cliffPaid = _cliffPaid;
        investorData.amount = _amount - _amountAfterCliff;
        investorData.released = _released;
        investorData.amountAfterCliff = _amountAfterCliff;
        investorData.phaseID = _phaseID;

        vestingTotalAmount = (vestingTotalAmount + _amount) - _released;
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _token.safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param investorDataId the vesting schedule identifier
     * @param amount the amount to be claim
     */
    function claim(bytes32 investorDataId, uint256 amount)
        public
        nonReentrant
        onlyIfNotRevoked(investorDataId)
    {
        InvestorData storage investorData = investorsData[investorDataId];
        require(
            msg.sender == investorData.investor ||
                hasRole(ADMIN_ROLE, msg.sender),
            "Vesting: only investor and admin can claim vested tokens"
        );
        uint256 vestedAmount = _computeReleasableAmount(investorData);
        require(
            vestedAmount >= amount,
            "Vesting: cannot claim tokens, not enough vested tokens"
        );
        if (amount != 0) {
            if (investorData.cliffPaid) {
                investorData.released = investorData.released + amount;
            } else {
                investorData.released =
                    (investorData.released + amount) -
                    investorData.amountAfterCliff;
            }
            vestingTotalAmount = vestingTotalAmount - amount;
            investorData.cliffPaid = true;
            address payable investorPayable = payable(investorData.investor);

            _token.safeTransfer(investorPayable, amount);

            emit Released(investorData.investor, amount);
        }
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(bytes32 investorDataId)
        external
        view
        onlyIfNotRevoked(investorDataId)
        returns (uint256)
    {
        //InvestorData storage investorData = investorsData[investorDataId];
        return _computeReleasableAmount(investorsData[investorDataId]);
    }

    /**
     * @notice Returns the investor data information for a given identifier.
     * @return the investor data structure information
     */
    function getInvestorData(bytes32 investorDataId)
        public
        view
        returns (InvestorData memory)
    {
        return investorsData[investorDataId];
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the admin.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() external view returns (uint256) {
        return _token.balanceOf(address(this)) - vestingTotalAmount;
    }

    /**
     * @dev Computes the next investor data identifier for a given holder address.
     */
    function computeNextinvestorDataIdForHolder(address holder)
        public
        view
        returns (bytes32)
    {
        return
            computeInvestorDataIdForAddressAndIndex(
                holder,
                holdersVestingCount[holder]
            );
    }

    /**
     * @dev Get vesting phase.
     * @param _phaseID ID of phase
     * @return structure of vesting phase
     */
    function getVestingPhase(uint256 _phaseID)
        external
        view
        returns (VestingPhase memory)
    {
        return vestingPhases[_phaseID];
    }

    /**
     * @dev Get current timestamp in seconds.
     * @return current timestamp
     */
    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Computes the investor data identifier for an address and an index.
     */
    function computeInvestorDataIdForAddressAndIndex(
        address holder,
        uint256 index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Grant the stage adjustment role to a specified account
     * @param saRole_ the address to which SA permissions are set
     */
    function grantSARole(address saRole_) external {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _setupRole(STAGE_ADJUSTMENT_ROLE, saRole_);
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(InvestorData memory investorData)
        internal
        view
        returns (uint256)
    {
        uint256 currentTime = getCurrentTime();
        VestingPhase memory vestingPhase = vestingPhases[investorData.phaseID];

        if (
            (currentTime < vestingPhase.cliff) || (investorData.amount == 0) // If cliff not finished or total amount = 0 (schedule was canceled)
        ) {
            return 0;
        } else if (currentTime >= vestingPhase.cliff + vestingPhase.duration) {
            // If vesting period finished
            return investorData.amount - investorData.released;
        } else {
            uint256 timeFromStart = currentTime - vestingPhase.cliff;
            uint256 secondsPerSlice = vestingPhase.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            uint256 vestedAmount = (investorData.amount * vestedSeconds) /
                vestingPhase.duration;
            if (investorData.cliffPaid) {
                vestedAmount = vestedAmount - investorData.released;
            } else {
                vestedAmount = vestedAmount + investorData.amountAfterCliff;
            }
            return vestedAmount;
        }
    }
}
