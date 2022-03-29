// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Counters.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract SimpleMarketplace is ReentrancyGuard,Ownable{
    using Counters for Counters.Counter;
    Counters.Counter private _listingIds;
    Counters.Counter private _tokenSold;
    uint256 private _volume;

    mapping(uint256 => Listing) private idToListing;
    Listing[] private listingsArray;

    struct Listing {
        uint256 listingId;
        address contractAddress;
        address seller;
        address[] buyer;
        uint256 tokenId;
        uint256 amout;
        uint256 price;
        uint256 tokenAvailable;
        bool completed;
        bool privateListing;
    }

    struct Stats{
        uint256 volume;
        uint256 itemsSold;
    }

    event TokenListed(
        uint256 listingId,
        address contractAddress,
        address seller,
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerToken,
        address[] privateBuyer,
        bool privateSale
    );

    event TokenSold(
        address contractAddress,
        address seller,
        address buyer,
        uint256 tokenId,
        uint amount,
        uint256 pricePerToken,
        bool privateSale
    );

    event listingDeleted(
        address contractAddress,
        uint256 listingId
    );

    function listToken(address contractAddress,uint256 tokenId,uint256 amount, uint256 price , address[] memory privateBuyer) public nonReentrant returns(uint256) {
        ERC1155 token = ERC1155(contractAddress);

        require(token.balanceOf(msg.sender,tokenId) >= amount,"Caller must own given token!");
        require(token.isApprovedForAll(msg.sender,address(this)),"Contract must be approved!");

        bool privateListing = privateBuyer.length > 0;
        _listingIds.increment();
        uint listingId = _listingIds.current();

        idToListing[listingId] = Listing(listingId,contractAddress,msg.sender,privateBuyer,tokenId,amount,price,amount,false,privateListing);

        listingsArray.push(idToListing[listingId]);

        emit TokenListed(listingId,contractAddress,msg.sender,tokenId,amount,price,privateBuyer,privateListing);

        return listingId;
    }

    function purchaseToken(uint256 listingId,uint256 amount) public payable nonReentrant{
        ERC1155 token = ERC1155(idToListing[listingId].contractAddress);

        if(idToListing[listingId].privateListing == true ){
            bool whitelisted = false;
            for(uint256 i = 0 ; i < idToListing[listingId].buyer.length ; i++ ){
                if(idToListing[listingId].buyer[i] == msg.sender){
                    whitelisted = true ;
                }
            }
            require(whitelisted == true, "Sale is private!");

        }

        require(msg.sender != idToListing[listingId].seller , "Can't buy your onw tokens!");
        require(msg.value >= idToListing[listingId].price*amount , "Insufficient funds!");
        require(token.balanceOf(idToListing[listingId].seller,idToListing[listingId].tokenId) >= amount ,"Seller doesn't have enough tokens!" );
        require(idToListing[listingId].completed == false , "Listing not available anymore!");
        require(idToListing[listingId].tokenAvailable >= amount , "Not enough tokens left!");

        _tokenSold.increment();
        _volume += idToListing[listingId].price*amount;

        idToListing[listingId].tokenAvailable -= amount;
        listingsArray[listingId - 1].tokenAvailable -= amount;

        if(idToListing[listingId].tokenAvailable == 0){
            idToListing[listingId].completed = true;
            listingsArray[listingId-1].completed = true;
        }
        if(idToListing[listingId].privateListing == false){
            idToListing[listingId].buyer.push(msg.sender);
            listingsArray[listingId-1].buyer.push(msg.sender);
        }

        emit TokenSold(
            idToListing[listingId].contractAddress,
            idToListing[listingId].seller,
            msg.sender,
            idToListing[listingId].tokenId,
            amount,
            idToListing[listingId].price,
            idToListing[listingId].privateListing
        );

        token.safeTransferFrom(idToListing[listingId].seller, msg.sender, idToListing[listingId].tokenId, amount, "");

        payable(idToListing[listingId].seller).transfer((idToListing[listingId].price*amount*49)/50); // only pay 98% to seller
    }

    function deleteListing(uint256 listingId) public {
        require(msg.sender == idToListing[listingId].seller , "Not caller's listing!");
        require(idToListing[listingId].completed == false ,"Listing not available!");

        idToListing[listingId].completed = true;
        listingsArray[listingId-1].completed = true;

        emit listingDeleted(idToListing[listingId].contractAddress,listingId);
    }

    function viewAllListings() public view returns(Listing[] memory){
        return listingsArray;
    }

    function viewListingById(uint256 _id) public view returns(Listing memory){
        return idToListing[_id];
    }

    function viewStats() public view returns(Stats memory){
        return Stats(_volume,_tokenSold.current());
    }

    function withdrawFees() public onlyOwner nonReentrant{
        payable(msg.sender).transfer(address(this).balance);
    }
}