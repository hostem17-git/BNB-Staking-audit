// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract StakingBNB {
    // DECLARATION
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    // OWNER
    address public owner;
    // address public treasury;
    bool public isActive;

    // CONSTANTS
    uint256 MINIMUM_CONTRIBUTION = 10000000000000000; // 0.01 BNB
    uint256 MAXIMUM_CONTRIBUTION = 500000000000000000000; // 500 BNB
    uint256 MAXIMUM_STAKING_PERIOD = 250 days;
    uint256 MAXIMUM_REFERRAL_STACK = 5;

    // GLOBAL VERIABLES
    Counters.Counter private stakeId;
    uint256[5] private refLvlRate = [uint256(10), 5, 3, 2, 1];

    // STRUCTS
    struct UserFunds {
        uint256 id;
        uint256 balance; // net balance after deducting fee
        uint256 createdAt;
        uint256 lastWithdrawal;
        uint256 timeLeft;
    }

    struct UserDetails {
        address refferedBy; // parent node
        ReferalLevels referrals; // child nodes
        uint256 level; // level in the tree
        bool isRegistered;
    }

    struct UserBalance {
        uint256 totalBalance;
        uint256 balance;
        uint256 ownEarnings;
        uint256 oeTs; //Own Earning Time?
        uint256 totalRefEarnings; // exclude commission earned during withdrawal by a Referral
        uint256 tRefTs;// total referral earning timestamp
        Withdrawals totalWithdrawal;
     
        uint256 maxWithdrawal;
        uint256 totalWithdrawalCommission; // commission earned when a direct referall withdrawas
        uint256 referralBonus;
    }

    struct Withdrawals {
        uint256[] amountWithdrawan;
        uint256[] twTs;
        uint256[] refWtihdrawalCommission;
        uint256[] wcTs;
    }

    struct ReferalLevels {
        address[][5] refAddrs; // stores all addresses of referrals.
        uint256[5] refBalances; // referral earnings for each level. it gets updated when the lower level referrer deposits some amount.
        uint256[5] rbTs; // Time Stamp get updated when lower level user depoisits some amount.
        uint256[5] referralEarnings; // gets updated when the user initiates withdrawal of referral amount.
        uint256[5] reTs; // gets updated when the user initiates withdrawal of referral amount.
    }

    // MAPPING
    mapping(address => UserBalance) public stakedBalance;
    mapping(address => UserFunds[]) public userFundDetails;
    mapping(uint256 => uint256) public levelInfo;
    mapping(address => UserDetails) public userDetails;

    // EVENTS
    event STAKED(address indexed staker, uint256 indexed amount);
    event WITHDRAW(address indexed withdrawer, uint256 indexed amount);
    event REGISTERED(address _userAdd, address _referredBy);

    constructor() {
        owner = msg.sender;
        isActive = true;
        levelInfo[1] = 10000000000000000;
        levelInfo[2] = 100000000000000000;
        levelInfo[3] = 1000000000000000000;
        levelInfo[4] = 5000000000000000000;
        levelInfo[5] = 10000000000000000000;

        userDetails[msg.sender].level = 0;
        userDetails[msg.sender].refferedBy = address(0);
        userDetails[msg.sender].isRegistered = true;
    }

    /// @notice Flip the active tag to false and will pause the contract
    function pauseContract() public onlyOwner {
        require(isActive, "Already Paused");
        isActive = false;
    }

    /// @notice Flip the active tag to true and will active the contract again
    function activeContract() public onlyOwner {
        require(!isActive, "Already Actived");
        isActive = true;
    }

    function registerUser(address referrer) public {
        require(
            userDetails[msg.sender].isRegistered != true,
            "User already registered"
        );
        require(
            userDetails[referrer].isRegistered,
            "Referrer is not registered"
        );

        _registerUser(referrer);
    }

    function stakeBnb() public payable isRegisteredUser {
        address _user = msg.sender;
        uint256 _value = msg.value;
        require(
            _value > MINIMUM_CONTRIBUTION,
            "Staking amount should be greater than 0.01 BNB"
        );
        require(
            _value < MAXIMUM_CONTRIBUTION,
            "Staking amount should be less than 500 BNB"
        );

        if (_value > stakedBalance[_user].maxWithdrawal) {
            stakedBalance[_user].maxWithdrawal = _value;
        }

        UserFunds memory newUserStake;
        uint256 amountAfterDeduction = (_value * 9) / 10;

        calculateDailyEarnings();

        stakedBalance[_user].totalBalance = stakedBalance[_user]
            .totalBalance
            .add(_value);
        stakedBalance[_user].balance = stakedBalance[_user].balance.add(
            amountAfterDeduction
        );

        newUserStake.balance = amountAfterDeduction;
        newUserStake.createdAt = block.timestamp;
        newUserStake.lastWithdrawal = 0 days;
        newUserStake.timeLeft = 250 days;
        newUserStake.id = stakeId.current();
        stakeId.increment();

        userFundDetails[_user].push(newUserStake);
        _updateRefBalance(_value);
        _deductDepositFees(_value);

        emit STAKED(_user, _value);
    }

    function _updateRefBalance(uint256 _amount) internal {  
        address _referredBy = msg.sender;

        for (uint256 i = 0; i < MAXIMUM_REFERRAL_STACK; i++) {
            _referredBy = userDetails[_referredBy].refferedBy;

            uint256 _curLvlBalance = userDetails[_referredBy]
                .referrals
                .refBalances[i];

            uint256 _lastTs = userDetails[_referredBy].referrals.rbTs[i];

            if (_lastTs == 0) {
                _lastTs = block.timestamp;
            } else if (userDetails[_referredBy].referrals.reTs[i] >= _lastTs) {
                _lastTs = userDetails[_referredBy].referrals.reTs[i];
            }
            uint256 _rate = refLvlRate[i];
            uint256 _timeDiff = block.timestamp - _lastTs;

            uint256 _earnings = (_curLvlBalance * _rate * _timeDiff) /
                (100 * 24 * 60 * 60);

            userDetails[_referredBy].referrals.refBalances[i] =
                _curLvlBalance +
                _amount;
            userDetails[_referredBy].referrals.rbTs[i] = block.timestamp;

            uint256 _totalRefEar = userDetails[_referredBy]
                .referrals
                .referralEarnings[i];
                
            userDetails[_referredBy].referrals.referralEarnings[i] =
                _totalRefEar +
                _earnings;

            userDetails[_referredBy].referrals.reTs[i] = block.timestamp;

            if (_isAdminOrNullAddress(_referredBy)) {
                return;
            }
        }
    }

    function getDailyEarningsRate(uint256 _amount)
        internal
        pure
        returns (uint256 _roi){
        if (_amount >= 251 * 10**18) {
            return 150;
        } else if (_amount >= 101 * 10**18) {
            return 125;
        } else if (_amount > 0.01 * 10**18) {
            return 100;
        }
    }

    function calculateDailyEarnings()
        public
        payable
        isRegisteredUser
        returns (uint256 _earnings){
        // check earnings rate
        address _user = msg.sender;

        UserFunds[] memory uf = userFundDetails[_user];
        uint256 _dailyEarnings = stakedBalance[_user].ownEarnings;

        uint256 _lastIndex = 0;
        uint256 _lastTs = block.timestamp;
        if (uf.length >= 1) {
            _lastIndex = uf.length - 1;
            _lastTs = uf[_lastIndex].lastWithdrawal;    
        }

        uint256 _lastBalance = stakedBalance[_user].balance;
        if (stakedBalance[_user].oeTs > _lastTs) {
            _lastTs = stakedBalance[_user].oeTs;
        }

        uint256 _time = block.timestamp - _lastTs; // in seconds
        uint256 _rate = getDailyEarningsRate(_lastBalance);
        _dailyEarnings += (_lastBalance * _rate * _time) / (10000 * 24 * 3600);

        uint256 _maxEarnings = checkMaxEarnings();

        if (_dailyEarnings >= _maxEarnings) {
            _dailyEarnings = _maxEarnings;
        }

        stakedBalance[_user].ownEarnings = _dailyEarnings;
        stakedBalance[_user].oeTs = block.timestamp;

        // //console.log("_dailyEarnings: ", _dailyEarnings);

        uint256 _performanceFee = _deductPerformanceFees(_dailyEarnings);
        return _dailyEarnings - _performanceFee;
    }

    function getUserFunds(address _user)
        public
        view
        returns (UserFunds[] memory){
        UserFunds[] memory uf = userFundDetails[_user];
        return uf;
    }

    function calculateReferalEarnings()
        public
        payable
        isRegisteredUser
        returns (uint256){
        // check earnings rate
        address _user = msg.sender;
     
        uint256[5] memory _curLvlBalance = userDetails[_user]
            .referrals
            .refBalances;
        uint256[5] memory _refTs = userDetails[_user].referrals.reTs;
        uint256 _eligibleLvl = _getMaximumReferralStack(_user);

        //console.log("_eligibleLvl: ", _eligibleLvl);

        uint256 _totalRefEarr = stakedBalance[_user].totalRefEarnings;

        for (uint256 i = 0; i < _eligibleLvl; i++) {
            uint256 _rate = refLvlRate[i];
            uint256 _timeDiff = block.timestamp - _refTs[i];
            uint256 _earnings = (_curLvlBalance[i] * _rate * _timeDiff) /
                (100 * 24 * 60 * 60);
            userDetails[_user].referrals.reTs[i] = block.timestamp;
            _totalRefEarr += _earnings;

            //console.log("_timeDiff: ", _timeDiff);
            //console.log("_rate: ", _rate);
            //console.log("_earnings: ", _earnings);
            //console.log("_totalRefEarr: ", _totalRefEarr);
        }

        uint256 _maxEarnings = checkMaxEarnings();

        if (_totalRefEarr >= _maxEarnings) {
            _totalRefEarr = _maxEarnings;
        }

        stakedBalance[_user].totalRefEarnings = _totalRefEarr;
        stakedBalance[_user].tRefTs = block.timestamp;
        uint256 _refFee = _deductReferralFees(_totalRefEarr);
        return _totalRefEarr - _refFee;
    }

    function withdrawOwnBonus(uint256 _amount) public payable {
        require(_amount >= MINIMUM_CONTRIBUTION, "withdraw atleast 0.01 BNB");
        address _user = payable(msg.sender);
        require(
            checkMaxWithdrawal() >= _amount,
            "daily withdrawal limit reached"
        );
        uint256 _grossEarnigns = calculateDailyEarnings();
        require(_grossEarnigns >= _amount, "earnings are less");
        uint256 _taxes = _deductWithdrawalFees(_amount) +
            _checkAntiWhaleTaxes(_amount);
        uint256 _netEarnings = _amount - _taxes;
        stakedBalance[_user].ownEarnings = _grossEarnigns - _amount;
        stakedBalance[_user].totalWithdrawal.amountWithdrawan.push(_amount);
        stakedBalance[_user].totalWithdrawal.twTs.push(block.timestamp);
        stakedBalance[_user].oeTs = block.timestamp;
        payable(_user).transfer(_netEarnings);
        emit WITHDRAW(_user, _netEarnings);
    }

    function withdrawReferralBonus(uint256 _amount) public {
        require(_amount >= MINIMUM_CONTRIBUTION, "withdraw atleast 0.01 BNB");
        address _user = payable(msg.sender);
        require(
            checkMaxWithdrawal() >= _amount,
            "daily withdrawal limit reached"
        );
        uint256 _grossEarnigns = calculateReferalEarnings();
        require(_grossEarnigns >= _amount, "earnings are less");
        uint256 _taxes = _deductWithdrawalFees(_amount) +
            _checkAntiWhaleTaxes(_amount);
        uint256 _netEarnings = _amount - _taxes;
        stakedBalance[_user].totalRefEarnings = _grossEarnigns - _amount;
        stakedBalance[_user].totalWithdrawal.amountWithdrawan.push(_amount);
        stakedBalance[_user].totalWithdrawal.twTs.push(block.timestamp);
        stakedBalance[_user].tRefTs = block.timestamp;

        payable(_user).transfer(_netEarnings);
        emit WITHDRAW(_user, _netEarnings);
    }

    function withdrawReferralCommission(uint256 _amount) public {
        require(_amount >= MINIMUM_CONTRIBUTION, "withdraw atleast 0.01 BNB");
        address _user = payable(msg.sender);
        require(
            checkMaxWithdrawal() >= _amount,
            "daily withdrawal limit reached"
        );
        uint256 _grossEarnigns = stakedBalance[_user].totalWithdrawalCommission;
        require(_grossEarnigns >= _amount, "earnings are less");
        uint256 _taxes = _deductWithdrawalFees(_amount) +
            _checkAntiWhaleTaxes(_amount);
        uint256 _netEarnings = _amount - _taxes;
        stakedBalance[_user].totalWithdrawalCommission =
            _grossEarnigns -
            _amount;
        stakedBalance[_user].totalWithdrawal.amountWithdrawan.push(_amount);
        stakedBalance[_user].totalWithdrawal.twTs.push(block.timestamp);

        payable(_user).transfer(_netEarnings);
        emit WITHDRAW(_user, _netEarnings);
    }

    function withdrawBalacne(uint256 _amount) public {
        require(_amount >= MINIMUM_CONTRIBUTION, "withdraw atleast 0.01 BNB");
        address _user = payable(msg.sender);
        require(
            checkMaxWithdrawal() >= _amount,
            "daily withdrawal limit reached"
        );
      
        uint256 _grossTotalEarnigns = checkTotalEarnings();
        uint256 _grossTotalBalance = stakedBalance[_user].balance +
            _grossTotalEarnigns;

        //console.log("_grossTotalEarnigns: ", _grossTotalEarnigns);

        require(_grossTotalBalance >= _amount, "earnings are less");

        uint256 _taxes = _deductWithdrawalFees(_amount) +
            _checkAntiWhaleTaxes(_amount);

        uint256 _netEarnings = _amount - _taxes;
        stakedBalance[_user].tRefTs = block.timestamp;
        stakedBalance[_user].oeTs = block.timestamp;
        stakedBalance[_user].totalWithdrawal.amountWithdrawan.push(_amount);
        stakedBalance[_user].totalWithdrawal.twTs.push(block.timestamp);
        uint256 _netBalanceChange = stakedBalance[_user].balance -
            (_amount + _grossTotalEarnigns);
        stakedBalance[_user].balance =
            stakedBalance[_user].balance -
            _netBalanceChange;
        stakedBalance[_user].totalBalance =
            stakedBalance[_user].totalBalance -
            ((_netBalanceChange * 100) / 90);

        payable(_user).transfer(_netEarnings);

        emit WITHDRAW(_user, _netEarnings);
    }

    function checkTotalEarnings() public returns (uint256) {
        address _user = msg.sender;

        uint256 _grossOwnEarnings = calculateDailyEarnings();
        uint256 _grossRefEarnings = calculateReferalEarnings();
        uint256 _grossTotalEarnigns = stakedBalance[_user]
            .totalWithdrawalCommission +
            _grossRefEarnings +
            _grossOwnEarnings;
        uint256 _maxEarnings = checkMaxEarnings();

        if (_grossTotalEarnigns >= _maxEarnings) {
            _grossTotalEarnigns = _maxEarnings;
        }
        //console.log(
        //     "checkTotalEarnings ~ _grossTotalEarnigns",
        //     _grossTotalEarnigns
        // );
        return _grossTotalEarnigns;
    }

    function checkMaxEarnings() public view returns (uint256) {
        address _user = msg.sender;
        uint256 _currentBalance = stakedBalance[_user].balance;
        //console.log(
        //     "checkMaxEarnings ~ (_currentBalance * 250) / 100",
        //     (_currentBalance * 250) / 100
        // );
        return (_currentBalance * 250) / 100;
    }

    function checkMaxWithdrawal() public view returns (uint256) {
        address _user = msg.sender;
        uint256 _maxAllowed = stakedBalance[_user].maxWithdrawal;

        uint256[] memory _withdrawalAmout = stakedBalance[_user]
            .totalWithdrawal
            .amountWithdrawan;
        uint256[] memory _lastTs = stakedBalance[_user].totalWithdrawal.twTs;
        uint256 _currentTs = block.timestamp;
        if (_lastTs.length >= 1) {
            uint256 _amount = 0;
            for (uint256 i = _lastTs.length; i > 0; i--) {
                uint256 _day = _currentTs - 86400;
                if (_lastTs[i - 1] >= _day) {
                    _amount += _withdrawalAmout[i - 1];
                } else if (_lastTs[i - 1] < _day) {
                    break;
                }
            }
            if (_maxAllowed >= _amount) {
                //console.log(
                //     "checkMaxWithdrawal ~ _maxAllowed - _amount",
                //     _maxAllowed - _amount
                // );
                return _maxAllowed - _amount;
            } else {
                return 0;
            }
        } else {
            //console.log("checkMaxWithdrawal ~ _maxAllowed", _maxAllowed);
            return _maxAllowed;
        }
    }

    function _checkAntiWhaleTaxes(uint256 _amount)
        public
        view
        returns (uint256){
        uint256 _stakingBalance = address(this).balance;
        uint256 _percentage = _getRelativePercentage(_amount, _stakingBalance);

        for (uint256 i = 1; i <= 10; i++) {
            if (_percentage >= i) {
                return (_amount * i * 5) / 100;
            }
        }

        return 0;
    }

    function _getRelativePercentage(uint256 partialValue, uint256 totalValue)
        internal
        pure
        returns (uint256){
        return (100 * partialValue) / totalValue;
    }

    // MISCELLANEOUS FUNCTIONS
    function _registerUser(address _refferer) internal {
        address _user = msg.sender;
        if (_refferer != owner) {
            require(_user != _refferer, "Cannot refer to yourself");
        }
        
        userDetails[_user].level = 0;
        userDetails[_user].refferedBy = _refferer;
        userDetails[_user].isRegistered = true;

        _updateRefAddrs(_refferer);
        emit REGISTERED(_user, _refferer);
        //console.log(
        //     "Registration Successful. User Add: ",
        //     _user,
        //     " Referred By: ",
        //     _refferer
        // );
    }

    function _updateRefAddrs(address _refAdrs) internal {
        address _user = msg.sender;
        // Need to check till max referral allowed and add in refferal level wise
        address _referredBy = _refAdrs;
        for (uint256 i = 0; i < MAXIMUM_REFERRAL_STACK; i++) {
            if (i == 0) {
                userDetails[_referredBy].referrals.refAddrs[i].push(_user);
            } else {
                _referredBy = userDetails[_referredBy].refferedBy;
                userDetails[_referredBy].referrals.refAddrs[i].push(_user);
                if (_isAdminOrNullAddress(_referredBy)) {
                    return;
                }
            }
        }
    }

    function _deductDepositFees(uint256 _amount)
        internal
        pure
        returns (uint256){
        uint256 _amountToDeduct = _amount / 10; // 10%
        // 50% of 10% and the remaining 50% will reaming with this SC
        // payable(treasury).transfer(_amountToDeduct / 2);
        // payable(address(this)).transfer(_amountToDeduct / 2);
        return _amountToDeduct;
    }

    function _deductWithdrawalFees(uint256 _amount) internal returns (uint256) {
        // 50% of 10% to treasury and send 10% to direct sponsor and the remaining 40% will reaming with this SC
        uint256 _amountToDeduct = _amount / 10; // 10%
        // uint256 _treasuryShare = _amountToDeduct / 2;
        uint256 _directRefShare = _amountToDeduct / 10;

        // payable(treasury).transfer(_treasuryShare);

        address _user = userDetails[msg.sender].refferedBy;
        stakedBalance[_user].totalWithdrawal.refWtihdrawalCommission.push(
            _directRefShare
        );
        stakedBalance[_user].totalWithdrawal.wcTs.push(block.timestamp);
        stakedBalance[_user].totalWithdrawalCommission += _directRefShare;
        return _amountToDeduct;
    }

    function _deductReferralFees(uint256 _amount)
        internal
        pure
        returns (uint256){
        uint256 _amountToDeduct = _amount / 10; // 10%
        // 50% of 10% and the remaining 50% will reaming with this SC
        // payable(treasury).transfer(_amountToDeduct / 2);
        return _amountToDeduct;
    }

    function _deductPerformanceFees(uint256 _amount)
        internal
        returns (uint256){
        uint256 _amountToDeduct = _amount / 4; // 25%
        // 25% is split into three parts - 50% to treasury, 35% ramains with this SC
        //15% will be spilt equally between 5 levels.
        // payable(treasury).transfer(_amountToDeduct / 2);
        _distributeReferralBonus((_amountToDeduct * 15) / 100);
        return _amountToDeduct;
    }

    function _isAdminOrNullAddress(address _address)
        internal
        view
        returns (bool){
        return owner == _address || address(0) == _address;
    }

    function _getInitialReferral(address _refferer)
        internal
        view
        returns (address _address){
        return userDetails[_refferer].refferedBy;
    }

    function _getMaximumReferralStack(address _address)
        internal
        view
        returns (uint256 stack){
        uint256 balance = stakedBalance[_address].balance;
        if (balance >= levelInfo[5]) {
            return 5;
        }
        if (balance >= levelInfo[4]) {
            return 4;
        }
        if (balance >= levelInfo[3]) {
            return 3;
        }
        if (balance >= levelInfo[2]) {
            return 2;
        }
        if (balance >= levelInfo[1]) {
            return 1;
        }
    }

    function _getTotalActiveStake(address _address) internal returns (uint256) {
        UserFunds[] memory uf = userFundDetails[_address];
        uint256 amountToWidthraw;
        for (uint256 i = 0; i <= uf.length - 1; i++) {
            uint256 withdrawalAmount = MAXIMUM_STAKING_PERIOD.sub(
                uf[i].timeLeft.add(uf[i].lastWithdrawal)
            );
            if (withdrawalAmount > 0) {
                amountToWidthraw = amountToWidthraw.add(withdrawalAmount);
                userFundDetails[_address][i].lastWithdrawal = 0 days;
            }
        }
        return amountToWidthraw;
    }

    function _distributeReferralBonus(uint256 _amount) internal {
        uint256 splitAmount = _amount / 5;
        address _referredBy = userDetails[msg.sender].refferedBy;
        
        for (uint256 i = 1; i <= MAXIMUM_REFERRAL_STACK; i++) {

            if (i == 1) {
                // level1
                stakedBalance[_referredBy].referralBonus = stakedBalance[
                    _referredBy
                ].referralBonus.add(splitAmount);
            } else if (i == 2) {
                // level2
                // get refferedBy of refferal
                _referredBy = userDetails[_referredBy].refferedBy;
                stakedBalance[_referredBy].referralBonus = stakedBalance[
                    _referredBy
                ].referralBonus.add(splitAmount);
                if (_isAdminOrNullAddress(_referredBy)) {
                    return;
                }
            } else if (i == 3) {
                // level3
                _referredBy = userDetails[_referredBy].refferedBy;
                stakedBalance[_referredBy].referralBonus = stakedBalance[
                    _referredBy
                ].referralBonus.add(splitAmount);
                if (_isAdminOrNullAddress(_referredBy)) {
                    return;
                }
            } else if (i == 4) {
                // level4
                _referredBy = userDetails[_referredBy].refferedBy;
                stakedBalance[_referredBy].referralBonus = stakedBalance[
                    _referredBy
                ].referralBonus.add(splitAmount);
                if (_isAdminOrNullAddress(_referredBy)) {
                    return;
                }
            } else if (i == 5) {
                // level5
                _referredBy = userDetails[_referredBy].refferedBy;
                stakedBalance[_referredBy].referralBonus = stakedBalance[
                    _referredBy
                ].referralBonus.add(splitAmount);
                if (_isAdminOrNullAddress(_referredBy)) {
                    return;
                }
            } else {
                return;
            }
        }
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function withdrawContractBalance() public onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    function getDailyWithdrawalLimit(address user) public view returns (uint256){
        UserBalance memory userf = stakedBalance[user];
        return userf.maxWithdrawal;
    }
    // MODIFIERS
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier isRegisteredUser() {
        require(userDetails[msg.sender].isRegistered, "User not registered");
        _;
    }

    receive() external payable {}
}   
