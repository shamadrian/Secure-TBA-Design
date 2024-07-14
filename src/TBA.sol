// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "../lib/openzeppelin-contracts/contracts/interfaces/IERC1271.sol";
import {Guardian} from "./Guardian.sol";
import {TokenCallbackHandler} from "./TokenCallbackHandler.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

//---------------------------------------------------------------------------
//                            IERC6551 INTERFACES
//---------------------------------------------------------------------------

interface IERC6551Account {
    receive() external payable;

    function token()
        external
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId);

    function state() external view returns (uint256);

    function isValidSigner(address signer, bytes calldata context)
        external
        view
        returns (bytes4 magicValue);
}

interface IERC6551Executable {
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory);
}

//---------------------------------------------------------------------------
//                              ERC6551 CONTRACT
//---------------------------------------------------------------------------

contract TBA is
    IERC165, 
    IERC6551Account, 
    IERC6551Executable,
    TokenCallbackHandler,
    Guardian {
    //STORAGE
    uint256 public state;
    bool isReset = true;
    struct TokenData{
        address tokenAddress;
        address userAddress;
        uint256 amount;
    }
    TokenData[] public tokenApprovals;
    struct NFTData{
        address tokenAddress;
        uint256 tokenID;
    }
    NFTData[] public nftApprovals;
    address[] public nftOperators;

    address receiver;
    uint256 lockTimeStamp;
    uint256 lockTime;

    modifier isLocked() {
        require(state == 0, "Contract is locked");
        _;
    }
    
    //--------------------PUBLIC VIEW FUNCTIONS--------------------
    function token() public view virtual returns (uint256, address, uint256) {
        bytes memory footer = new bytes(0x60);

        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }

        return abi.decode(footer, (uint256, address, uint256));
    }
    //Account Bound to Token Owner
    function owner() public view virtual returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);

        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function getApprovals() public view returns (TokenData[] memory, NFTData[] memory, address[] memory) {
        return (tokenApprovals, nftApprovals, nftOperators);
    }

    function getState() public view returns (uint256) {
        return state;
    }

    function getReset() public view returns (bool) {
        return isReset;
    }

    function getReceiver() public view returns (address) {
        return receiver;
    }
    //-------------------EXTERNAL WRITE FUNCTIONS-------------------

    function _isValidSigner(address signer) internal view virtual returns (bool) {
        return signer == owner();
    }

    function isValidSigner(address signer, bytes calldata) external view virtual returns (bytes4) {
        if (_isValidSigner(signer)) {
            return IERC6551Account.isValidSigner.selector;
        }

        return bytes4(0);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * execute a transaction (called directly from owner)
     */
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        isLocked()
        returns (bytes memory result)
    {
        checkCallerIsOwner();
        require(operation == 0, "Only call operations are supported");
        if(data.length != 0){
            bytes4 approveSelector = bytes4(keccak256("approve(address,uint256)"));
            require(bytes4(data[:4]) != approveSelector, "Approve is not allowed");
            bytes4 setApprovalForAllSelector = bytes4(keccak256("setApprovalForAll(address,bool)"));
            require(bytes4(data[:4]) != setApprovalForAllSelector, "setApprovalForAll is not allowed");
        }
        _call(to, value, data);
    }

    //---------------------------------------------------------------------------
    //                              GUARDIAN FUNCTIONS
    //---------------------------------------------------------------------------

    function checkCallerIsOwner() internal override virtual {
        require(msg.sender == owner(), "Caller is not Owner");
    }

    function breakCycle(address _newOwner, address _tokenAddress, uint256 _tokenID) internal override virtual {
        IERC721(_tokenAddress).transferFrom(address(this), _newOwner, _tokenID);
    }

    //---------------------------------------------------------------------------
    //                                OWNER FUNCTIONS
    //---------------------------------------------------------------------------
    function approveToken(address _tokenAddress, address _to, uint256 _amount) external isLocked() {
        checkCallerIsOwner();
        tokenApprovals.push(TokenData(_tokenAddress, _to, _amount));
        IERC20(_tokenAddress).approve(_to, _amount);
        if (isReset) {
            isReset = false;
        }
    }
    function approveNFT(address _tokenAddress, uint256 _tokenID, address _to) external isLocked() {
        checkCallerIsOwner();
        nftApprovals.push(NFTData(_tokenAddress, _tokenID));
        IERC721(_tokenAddress).approve(_to, _tokenID);
        if (isReset) {
            isReset = false;
        }
    }
    function setOperator(address _tokenAddress, address _operator, bool _flag) external isLocked() {
        checkCallerIsOwner();
        require(_operator != address(0), "Invalid Operator");
        require(_operator != address(this), "Invalid Operator");
        require(_operator != owner(), "Invalid Operator");
        nftOperators.push(_operator);
        IERC721(_tokenAddress).setApprovalForAll(_operator, _flag);
        if (isReset) {
            isReset = false;
        }
    }

    function reset() external {
        checkCallerIsOwner();
        require(!isReset, "Already Reset");
        isReset = true;
        for (uint256 i = 0; i < tokenApprovals.length; i++) {
            IERC20(tokenApprovals[i].tokenAddress).approve(tokenApprovals[i].userAddress, 0);
        }
        for (uint256 i = 0; i < nftApprovals.length; i++) {
            IERC721(nftApprovals[i].tokenAddress).approve(address(0), nftApprovals[i].tokenID);
        }
        for (uint256 i = 0; i < nftOperators.length; i++) {
            IERC721(nftOperators[i]).setApprovalForAll(address(0), false);
        }
        delete tokenApprovals;
        delete nftApprovals;
        delete nftOperators;
    }

    function setReceiver(address _receiver) external {
        checkCallerIsOwner();
        receiver = _receiver;
    }

    function lock(uint256 _lockTime) external {
        require(receiver != address(0), "Receiver not set");
        checkCallerIsOwner();
        state = 1;
        lockTimeStamp = block.timestamp;
        lockTime = _lockTime;
    }

    function unlock() external {
        if (block.timestamp >= lockTimeStamp + lockTime) {
            state = 0;
            receiver = address(0);
        }
        if (msg.sender == receiver) {
            state = 0;
            receiver = address(0);
        }
    }

    //---------------------------------------------------------------------------
    //                              TOKEN AND STATE FUNCTIONS
    //---------------------------------------------------------------------------
    receive() external payable {}
}