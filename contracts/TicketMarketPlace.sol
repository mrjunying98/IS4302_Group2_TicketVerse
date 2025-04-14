// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ConcertTicket.sol";
import {ILoyaltySystem} from "./LoyaltySystem.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title TicketMarketPlace
 * @notice This contract manages the resale of ConcertTicket NFTs on a secondary marketplace.
 * Ticket owners can list their tickets for resale, and buyers can purchase listed tickets.
 * The sale price is restricted to a maximum of 1.5x the original ticket price.
 * In addition, the contract integrates with a LoyaltySystem to award points to buyers and sellers.
 * Ticket sales (i.e., resale) are allowed only before the concert starts.
 */
contract TicketMarketPlace is Initializable, OwnableUpgradeable {
    // -------------------------------
    // STATE VARIABLES
    // -------------------------------

    /// @notice Instance of the ConcertTicket contract.
    ConcertTicket public concertTicket;
    /// @notice Instance of the LoyaltySystem interface.
    ILoyaltySystem public loyaltySystem;

    /// @notice Maximum resale price multiplier numerator (1.5x).
    uint256 public constant MAX_RESALE_MULTIPLIER_NUMERATOR = 15;
    /// @notice Maximum resale price multiplier denominator.
    uint256 public constant MAX_RESALE_MULTIPLIER_DENOMINATOR = 10;

    /**
     * @dev Struct representing a ticket listing.
     * @param ticketId The ID of the listed ticket.
     * @param seller The address of the ticket owner.
     * @param salePrice The sale price in wei.
     * @param active Boolean flag indicating whether the listing is active.
     */
    struct Listing {
        uint256 ticketId;
        address seller;
        uint256 salePrice;
        bool active;
    }

    /// @notice Mapping from ticketId to its Listing details.
    mapping(uint256 => Listing) public listings;
    /// @notice Array to track ticket IDs with active listings.
    uint256[] private listedTicketIds;

    // -------------------------------
    // EVENTS
    // -------------------------------


    event TicketListed(uint256 indexed ticketId, address indexed seller, uint256 salePrice);
    event ListingCancelled(uint256 indexed ticketId, address indexed seller);
    event TicketSold(uint256 indexed ticketId, address indexed seller, address indexed buyer, uint256 salePrice);
    event ActiveListingsUpdated(uint256 totalActive);
    event OriginalOwnerUpdated(uint256 indexed ticketId, address indexed newOwner);

    // -------------------------------
    // INITIALIZER FUNCTION
    // -------------------------------

    /**
     * @notice Initializes the TicketMarketPlace contract.
     * @param _concertTicket Address of the deployed ConcertTicket contract.
     * @param _loyaltySystem Address of the deployed LoyaltySystem contract.
     *
     * This function acts as the constructor for upgradeable contracts.
     */
    function initialize(address _concertTicket, address _loyaltySystem) external initializer {
        require(_concertTicket != address(0), "Invalid ConcertTicket address");
        require(_loyaltySystem != address(0), "Invalid LoyaltySystem address");
        concertTicket = ConcertTicket(_concertTicket);
        loyaltySystem = ILoyaltySystem(_loyaltySystem);
        __Ownable_init();
    }

    // -------------------------------
    // LISTING FUNCTIONS
    // -------------------------------

    /**
     * @notice Lists a ticket for resale.
     * @dev Requirements:
     * - Must be called before the concert starts.
     * - Caller must be the owner of the ticket.
     * - The ticket must not already be listed.
     * - The sale price must not exceed 1.5x the original ticket price.
     * @param ticketId The ID of the ticket to list.
     * @param salePrice The desired sale price in wei.
     */
    function listTicketForSale(uint256 ticketId, uint256 salePrice) external {
        require(block.timestamp < concertTicket.concertStartDate(), "Ticket sales closed");
        require(concertTicket.getTicketOwner(ticketId) == msg.sender, "Not the ticket owner");
        require(!listings[ticketId].active, "Ticket already listed");

        // Get the ticket details (ignoring row and seat as they are not used here).
        ( , , ConcertTicket.CAT ticketCategory, bool used, ) = concertTicket.tickets(ticketId);
        // Retrieve the original price for this category.
        ( , uint256 originalPrice) = concertTicket.seatingDetails(ticketCategory);
        require(originalPrice > 0, "Original price not set");
        require(used != true, "Ticket already used");

        // Calculate maximum allowed sale price (1.5x original price).
        uint256 maxSalePrice = (originalPrice * MAX_RESALE_MULTIPLIER_NUMERATOR) / MAX_RESALE_MULTIPLIER_DENOMINATOR;
        require(salePrice <= maxSalePrice, "Sale price exceeds maximum allowed");

        // Create a new listing.
        listings[ticketId] = Listing({
            ticketId: ticketId,
            seller: msg.sender,
            salePrice: salePrice,
            active: true
        });
        // Add ticketId to the active listings array.
        listedTicketIds.push(ticketId);

        emit TicketListed(ticketId, msg.sender, salePrice);
        emit ActiveListingsUpdated(listedTicketIds.length);
    }

    /**
     * @notice Cancels an active ticket listing.
     * @dev Requirements:
     * - Caller must be the seller who listed the ticket.
     * @param ticketId The ID of the ticket whose listing is to be cancelled.
     */
    function cancelListing(uint256 ticketId) external {
        Listing storage listing = listings[ticketId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Not the seller");

        // Mark the listing as inactive and remove it from active listings.
        listing.active = false;
        _removeListing(ticketId);

        emit ListingCancelled(ticketId, msg.sender);
    }

    /**
     * @notice Buys a ticket that is listed for resale.
     * @dev Requirements:
     * - Sale must occur before the concert starts.
     * - The listing must be active.
     * - The buyer must send exactly the sale price in ETH.
     * @param ticketId The ID of the ticket to purchase.
     */
    function buyTicket(uint256 ticketId) external payable {
        require(block.timestamp < concertTicket.concertStartDate(), "Ticket sales closed");

        Listing storage listing = listings[ticketId];
        require(listing.active, "Ticket not listed for sale");
        require(msg.value == listing.salePrice, "Incorrect ETH sent");

        // Mark the listing as inactive and remove it from the active listings array.
        listing.active = false;
        _removeListing(ticketId);

        // Transfer the ticket to the buyer by updating the original owner.
        concertTicket.changeOriginalOwner(ticketId, msg.sender);
        emit OriginalOwnerUpdated(ticketId, msg.sender);

        // Transfer sale proceeds to the seller.
        payable(listing.seller).transfer(msg.value);

        // Award loyalty points: buyer receives 100 points, seller receives 50 points.
        loyaltySystem.addPoints(msg.sender, 100);
        loyaltySystem.addPoints(listing.seller, 50);

        emit TicketSold(ticketId, listing.seller, msg.sender, msg.value);
    }

    // -------------------------------
    // INTERNAL FUNCTIONS
    // -------------------------------

    /**
     * @dev Removes a ticket ID from the active listings array using swap-and-pop.
     * @param ticketId The ID of the ticket to remove.
     */
    function _removeListing(uint256 ticketId) internal {
        uint256 length = listedTicketIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (listedTicketIds[i] == ticketId) {
                listedTicketIds[i] = listedTicketIds[length - 1];
                listedTicketIds.pop();
                break;
            }
        }
    }

    // -------------------------------
    // GETTER FUNCTIONS
    // -------------------------------

    /**
     * @notice Returns an array of active ticket listings.
     * @return An array of Listing structs.
     */
    function getActiveListings() external view returns (Listing[] memory) {
        uint256 count = listedTicketIds.length;
        Listing[] memory activeListings = new Listing[](count);
        for (uint256 i = 0; i < count; i++) {
            activeListings[i] = listings[listedTicketIds[i]];
        }
        return activeListings;
    }

    /**
     * @notice Returns the active listing for a given ticket ID.
     * @param ticketId The ID of the ticket.
     * @return The Listing struct for the ticket.
     */
    function getListing(uint256 ticketId) external view returns (Listing memory) {
        require(listings[ticketId].active, "Listing not active");
        return listings[ticketId];
    }
}