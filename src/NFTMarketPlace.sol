// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {TBA} from "./TBA.sol";

contract NFTMarketPlace {
    ERC721 public nft;
    struct Offers{
        address buyer;
        uint256 amount;
    }
    mapping(uint256 => address) public listedNFTOwners;
    mapping(uint256 => Offers) public listedNFTOffers;
    constructor(address _nft) {
        nft = ERC721(_nft);
    }
    function listNFT(uint256 tokenID) public {
        listedNFTOwners[tokenID] = msg.sender;
        require(nft.getApproved(tokenID) == address(this), "Contract not approved");
    }

    function advanceList(uint256 tokenID, address tbaAddress) public {
        require(TBA(payable(tbaAddress)).getState() == 1, "TBA is not locked");
        require(TBA(payable(tbaAddress)).getReceiver() == address(this), "TBA is not locked");
        require(TBA(payable(tbaAddress)).getReset(), "TBA is not reset");
        listedNFTOwners[tokenID] = msg.sender;
    }

    function buyOffer(uint256 tokenID, uint256 _amount) public payable {
        require(_amount == msg.value, "Amount not equal to value");
        listedNFTOffers[tokenID] = Offers(msg.sender, _amount);
    }

    function acceptOffer(uint256 tokenID) public {
        require(msg.sender == listedNFTOwners[tokenID], "Owner cannot buy his own NFT");
        require(listedNFTOffers[tokenID].amount > 0, "No offers available");
        address owner = listedNFTOwners[tokenID];
        address buyer = listedNFTOffers[tokenID].buyer;
        nft.transferFrom(owner, buyer, tokenID);
        owner.call{value: listedNFTOffers[tokenID].amount}("");
    }

    function advanceAcceptOffer(uint256 tokenID, address tbaAddress) public {
        require(msg.sender == listedNFTOwners[tokenID], "Owner cannot buy his own NFT");
        require(listedNFTOffers[tokenID].amount > 0, "No offers available");
        address owner = listedNFTOwners[tokenID];
        address buyer = listedNFTOffers[tokenID].buyer;
        TBA(payable(tbaAddress)).unlock();
        nft.transferFrom(owner, buyer, tokenID);
        owner.call{value: listedNFTOffers[tokenID].amount}("");
    }
}