// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

abstract contract Guardian {
    address[] public guardians = new address[](3);
    mapping(address => bool) public guardiansMap;

    struct Recovery {
        address newOwner;
        address tokenAddress;
        uint256 tokenID;
        uint8 approvalCount;
        uint startTime;
        mapping(address => bool) voted; 
    }

    Recovery public currentRecovery;
    uint256 public recoveryPeriod = 10 minutes;

    uint8 guardianCount;
    uint8 public threshold = 2;
    bool public guardianFlag = false;

    modifier onlyGuardian() {
        require(guardiansMap[msg.sender], "only guardian");
        _;
    }

    // -----If your TBA base contract inherits this module, you MUST override these functions-----

    //check if the caller is the owner of the NFT
    function checkCallerIsOwner() internal virtual {}

    //break ownershipCyle
    function breakCycle(address _newOwner, address _tokenAddress, uint256 _tokenID) internal virtual {}

    // -------------------------------------------------------------------------------------------

    function initializeGuardians(address[] memory _guardians) external {
        checkCallerIsOwner();
        require(_guardians.length > 0 && _guardians.length < 4, "0 < Number of guardians < 4");
        require(!guardianFlag, "guardians already initialized");
        for (uint256 i = 0; i < _guardians.length; i++) {
            guardians.push(_guardians[i]);
            guardiansMap[_guardians[i]] = true;
        }
        guardianCount = uint8(_guardians.length);
        guardianFlag = true;
    }

    function addGuardian(address _guardian) external {
        checkCallerIsOwner();
        require(guardianCount < 3, "guardian count must be less than 8");
        require(!guardiansMap[_guardian], "guardian already exists");
        guardians.push(_guardian);
        guardiansMap[_guardian] = true;
        guardianCount++;
    }

    function removeGuardian(address _guardian) external {
        checkCallerIsOwner();
        require(guardiansMap[_guardian], "guardian does not exist");
        if (guardianCount == 1) {
            guardianFlag = false;
        } 
        for (uint8 i = 0; i < guardianCount; i++) {
            if (guardians[i] == _guardian) {
                if(i == 0){
                    guardians[i] = guardians[1];
                    guardians[1] = guardians[2];
                    guardians[2] = address(0);
                } else if(i == 1){
                    guardians[i] = guardians[2];
                    guardians[2] = address(0);
                } else {
                    guardians[i] = address(0);
                }
                guardiansMap[_guardian] = false;
            }
        }
        guardianCount--;
    }

    function removeAllGuardians() internal {
        for (uint8 i = 0; i < guardianCount; i++) {
            guardiansMap[guardians[i]] = false;
            guardians[i] = address(0);
        }
        guardianCount = 0;
        guardianFlag = false;
    }

    function getGuardianCount() public view returns (uint256) {
        return guardianCount;
    }

    function getThreshold() public view returns (uint8) {
        return threshold;
    }

    function validateNewOwner(address _newOwner) internal view {
        require(_newOwner != address(0), "invalid new owner");
        require(_newOwner != address(this), "invalid new owner");
    }

    function proposeRecovery(address _newOwner, address _tokenAddress, uint256 _tokenID) external onlyGuardian() {
        require(_tokenAddress != address(0), "invalid token address");
        validateNewOwner(_newOwner);
        // Strings.toString(valid);
        // if (valid != 0) revert(string(abi.encodePacked("valid = ", Strings.toString(valid))));
        if (currentRecovery.approvalCount > 0){
            require(block.timestamp >currentRecovery.startTime + recoveryPeriod, "There is currently an active proposal");   
        }
        currentRecovery.startTime = block.timestamp;
        currentRecovery.approvalCount = 1;
        currentRecovery.voted[msg.sender] = true;
        currentRecovery.newOwner = _newOwner;
        currentRecovery.tokenAddress = _tokenAddress;
        currentRecovery.tokenID = _tokenID;
    }

    function voteRecovery() external onlyGuardian() {
        require(currentRecovery.approvalCount > 0, "no recovery in progress");
        require(!currentRecovery.voted[msg.sender], "already voted");
        currentRecovery.approvalCount++;
        currentRecovery.voted[msg.sender] = true;
    }

    function executeRecovery() external onlyGuardian() {
        require(currentRecovery.approvalCount > 0, "no recovery in progress");
        require(currentRecovery.approvalCount >= threshold, "not enough votes");
        breakCycle(
            currentRecovery.newOwner, 
            currentRecovery.tokenAddress, 
            currentRecovery.tokenID
        );
        removeAllGuardians();
    }
}