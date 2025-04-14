// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import upgradeable OpenZeppelin contracts for ERC721 and Ownable functionality.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title ConcertTicket
 * @notice This contract implements an upgradeable ERC721 token for concert tickets.
 * It manages seating details (availability and pricing), mints tickets,
 * tracks ticket ownership, and restricts transfers so that only the marketplace
 * can perform token transfers. The contract is upgradeable and uses OpenZeppelin's
 * Initializable, ERC721Upgradeable, and OwnableUpgradeable modules.
 */
contract ConcertTicket is Initializable, ERC721Upgradeable, OwnableUpgradeable {

    // Enumeration representing seating categories.
    enum CAT { A, B, C, D, E }

    /**
     * @dev Structure representing details for an individual ticket.
     * @param row The row number for the ticket (computed sequentially).
     * @param seatNumber The seat number in that row (computed sequentially).
     * @param category The seating category (one of A, B, C, D, or E).
     * @param used Boolean flag indicating whether the ticket has been used.
     * @param originalOwner The address that own the ticket
     */
    struct Ticket {
        uint256 row;
        uint256 seatNumber;
        CAT category;
        bool used;
        address originalOwner;  
    }

    /**
     * @dev Structure representing seating details for a particular category.
     * @param available The number of tickets available in this seating category.
     * @param price The price per ticket (in wei) for this seating category.
     */
    struct SeatingDetails {
        uint256 available;
        uint256 price;
    }

    // Mapping from tokenId to its Ticket details.
    mapping(uint256 => Ticket) public tickets;

    // Mapping for seating details per category.
    mapping(CAT => SeatingDetails) public seatingDetails;

    // Mapping to track sequential seat counters for each category.
    mapping(CAT => uint256) public seatCounters;

    // Mapping to track all token IDs owned by a given address.
    mapping(address => uint256[]) public ticketOwnedByAddress;

    // Constant representing the number of seats per row (can be adjusted if needed).
    uint256 public constant SEATS_PER_ROW = 10;

    // Concert start timestamp.
    uint256 public _concertStartDate;
    
    // Counter for generating new token IDs.
    uint256 public ticketIdCounter = 0;

    // Addresses for authorized marketplace and ticket sale contract.
    address public marketplace;
    address public ticketSaleContract;

    // Address of the event organiser.
    address public eventOrganiser; 

    // -------------------------------
    // EVENTS
    // -------------------------------
    event TicketMinted(address indexed to, uint256 indexed tokenId, uint256 row, uint256 seatNumber, CAT category);
    event TicketUsed(uint256 indexed tokenId);
    event MarketplaceUpdated(address indexed oldMarketplace, address indexed newMarketplace);
    event TicketSaleContractUpdated(address indexed oldTicketSale, address indexed newTicketSale);
    event EventDetailsUpdated(uint256 indexed tokenId, string oldEventDetails, string newEventDetails);
    event SeatingDetailsUpdated(CAT category, uint256 available, uint256 price);

    // -------------------------------
    // INITIALIZER
    // -------------------------------

    /**
     * @notice Initializes the ConcertTicket contract.
     * @param name The name of the ERC721 token.
     * @param symbol The symbol for the ERC721 token.
     * @param _marketplace The address of the marketplace allowed to transfer tokens.
     * @param _concertStartDateTimeStamp The start date timestamp of the concert.
     * @param _eventOrganiser The address of the event organiser.
     *
     * This function acts as the constructor for upgradeable contracts.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address _marketplace,
        uint256 _concertStartDateTimeStamp,
        address _eventOrganiser
    ) external initializer {
        __ERC721_init(name, symbol);
        __Ownable_init();
        marketplace = _marketplace;
        _concertStartDate = _concertStartDateTimeStamp;
        eventOrganiser = _eventOrganiser;
    }

    // -------------------------------
    // MODIFIERS
    // -------------------------------

    /**
     * @dev Restricts function calls to only the authorized TicketSaleContract.
     */
    modifier onlyAuthorizedMinter() {
        require(msg.sender == ticketSaleContract, "Not authorized to mint");
        _;
    }

    /**
     * @dev Restricts function calls to only the marketplace address.
     */
    modifier onlyMarketPlace() {
        require(msg.sender == marketplace, "Not authorized");
        _;
    }

    /**
     * @dev Restricts function calls to only the event organiser.
     */
    modifier onlyEventOrg() { 
        require(msg.sender == eventOrganiser, "Only Event Organiser Authorised");
        _;
    }

    /**
     * @dev Validates that the provided category is within the defined range.
     */
    modifier validCategory(CAT _cat) {
        require(uint8(_cat) <= uint8(CAT.E), "Invalid category");
        _;
    }

    // -------------------------------
    // SETTERS / UPDATERS
    // -------------------------------

    /**
     * @notice Sets the address of the authorized TicketSaleContract.
     * @param _ticketSaleContract The address of the TicketSaleContract.
     */
    function setTicketSaleContract(address _ticketSaleContract) external onlyOwner {
        require(_ticketSaleContract != address(0), "Invalid address");
        address old = ticketSaleContract;
        ticketSaleContract = _ticketSaleContract;
        emit TicketSaleContractUpdated(old, _ticketSaleContract);
    }

    /**
     * @notice Updates the marketplace address.
     * @param _newMarketplace The new marketplace address.
     */
    function updateMarketplace(address _newMarketplace) external onlyOwner {
        require(_newMarketplace != address(0), "Invalid marketplace address");
        address old = marketplace;
        marketplace = _newMarketplace;
        emit MarketplaceUpdated(old, _newMarketplace);
    }

    /**
     * @notice Sets or updates seating details for a given category.
     * @param category The seating category (A, B, C, D, E).
     * @param available Number of tickets available.
     * @param price Price per ticket (in wei) for the category.
     */
    function setSeatingDetails  (
        CAT category,
        uint256 available,
        uint256 price
    ) external onlyEventOrg {
        seatingDetails[category] = SeatingDetails(available, price);
        emit SeatingDetailsUpdated(category, available, price);
    }

    // -------------------------------
    // MINTING AND TICKET MANAGEMENT
    // -------------------------------

    /**
     * @notice Mints a new concert ticket NFT.
     * @dev This function can only be called by the authorized TicketSaleContract.
     * @param to The address of the ticket buyer.
     * @param category The seating category (A, B, C, D, or E) provided as a uint256.
     *
     * The function increments the internal ticketIdCounter, checks that the token does not already exist,
     * retrieves seating details, calculates seat position, mints the NFT, and records the ticket ownership.
     */
    function mint(
        address to,
        uint256 category
    ) external onlyAuthorizedMinter validCategory(CAT(category)) {
        // Increment the token counter to generate a new tokenId.
        ticketIdCounter++;
        uint256 newTokenID = ticketIdCounter;

        // Ensure the tokenId is unique (i.e. not already minted).
        require(_exists(newTokenID) == false, "Token ID already exists");

        // Retrieve the seating details for the given category.
        SeatingDetails storage details = seatingDetails[CAT(category)];
        require(details.available > 0, "No tickets available for this category");
        
        // Calculate seat position:
        // Here we use the remaining available count as the seat number (counting down).
        uint256 seatNumber = details.available;
        uint256 row = (seatNumber - 1) / SEATS_PER_ROW + 1;
        uint256 seatInRow = (seatNumber - 1) % SEATS_PER_ROW + 1;

        // Mint the NFT to the marketplace (temporary holder).
        _mint(address(marketplace), newTokenID);

        // Increase the counter for the seating category.
        seatCounters[CAT(category)]++;

        // Create a new Ticket struct for this token.
        Ticket memory newTicket = Ticket(
            row,
            seatInRow,
            CAT(category),
            false, // Not used
            to     // The buyer's address (original owner)
        );

        // Record the new ticket in the mapping and update owner's ticket array.
        addNewTicket(newTokenID, newTicket);

        // Emit an event indicating that a new ticket was minted.
        emit TicketMinted(to, newTokenID, row, seatNumber, CAT(category));
    }

    /**
     * @dev Internal function to store the new ticket details.
     * It also records the ticket in the owner's list.
     * @param tokenId The new token ID.
     * @param ticket The Ticket struct containing ticket details.
     */
    function addNewTicket(uint256 tokenId, Ticket memory ticket) internal {
        require(_exists(tokenId) == true, "Should have already minted");
        tickets[tokenId] = ticket;
        address buyer = ticket.originalOwner;
        ticketOwnedByAddress[buyer].push(tokenId);
    }

    /**
     * @notice Marks a ticket as used (e.g. during check-in).
     * @dev Only the event organiser is allowed to call this function.
     * @param tokenId The token ID of the ticket to mark as used.
     */
    function markAsUsed(uint256 tokenId) external onlyEventOrg {
        require(_exists(tokenId), "Ticket does not exist");
        tickets[tokenId].used = true;
        emit TicketUsed(tokenId);
    }

    /**
     * @notice Updates ticket availability for a specific seating category.
     * @dev This function can only be called by the authorized TicketSaleContract.
     * @param category The seating category.
     * @param available The new available ticket count.
     */
    function updateTicketAvailability(CAT category, uint256 available) external onlyAuthorizedMinter {
        seatingDetails[category].available = available;
    }

    /**
     * @notice Returns the available tickets for a given seating category.
     * @param category The seating category.
     * @return The number of available tickets.
     */
    function getTicketAvailability(CAT category) external view returns (uint256) {
        return seatingDetails[category].available;
    }

    // -------------------------------
    // TRANSFER OVERRIDE & OWNERSHIP CHANGE
    // -------------------------------

    /**
     * @dev Overrides the _beforeTokenTransfer hook from ERC721.
     * Restricts transfers so that only the marketplace can initiate transfers (after minting).
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        // If the token is not being minted (from != address(0)), only allow transfer if initiated by the marketplace.
        if (from != address(0)) {
            require(msg.sender == marketplace, "Transfers allowed only via marketplace");
        }
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @notice Changes the original owner of a ticket.
     * @dev Only the marketplace is allowed to perform this change.
     * This function updates both the ticket mapping and the owner's array of ticket IDs.
     * @param tokenId The token ID of the ticket.
     * @param newOwner The new owner address.
     */
    function changeOriginalOwner(uint256 tokenId, address newOwner) public onlyMarketPlace {
        // Remove tokenId from the old owner's list.
        address originalOwner = tickets[tokenId].originalOwner;
        uint256 length = ticketOwnedByAddress[originalOwner].length;
        for (uint256 i = 0; i < length; i++) {
            if (ticketOwnedByAddress[originalOwner][i] == tokenId) {
                // Swap with last element and remove to maintain array compactness.
                ticketOwnedByAddress[originalOwner][i] = ticketOwnedByAddress[originalOwner][length - 1];
                ticketOwnedByAddress[originalOwner].pop();
                break;
            }
        }
        // Update ticket's originalOwner and record it for the new owner.
        tickets[tokenId].originalOwner = newOwner;
        ticketOwnedByAddress[newOwner].push(tokenId);
    }

    // -------------------------------
    // GETTER FUNCTIONS
    // -------------------------------

    /**
     * @notice Retrieves detailed information about a given ticket.
     * @param tokenId The token ID of the ticket.
     * @return row The row number of the ticket.
     * @return seatNumber The seat number in that row.
     * @return category The seating category.
     * @return used Whether the ticket has been used.
     * @return originalOwner The original owner (buyer) of the ticket.
     */
    function getTicket(uint256 tokenId) external view returns (
        uint256 row,
        uint256 seatNumber,
        CAT category,
        bool used,
        address originalOwner
    ) {
        require(_exists(tokenId), "Ticket does not exist");
        Ticket memory t = tickets[tokenId];
        return (t.row, t.seatNumber, t.category, t.used, t.originalOwner);
    }

    /**
     * @notice Returns the current owner of a given ticket.
     * @param tokenId The token ID.
     * @return The address of the original owner.
     */
    function getTicketOwner(uint256 tokenId) external view returns (address) {
        return tickets[tokenId].originalOwner;
    }

    /**
     * @notice Returns the concert start date.
     * @return The timestamp when the concert starts.
     */
    function concertStartDate() external view returns (uint256) { 
        return _concertStartDate;
    }

    /**
     * @notice Returns the current ticket ID counter.
     * @return The last used ticket ID.
     */
    function getTicketIdCounter() external view returns (uint256) { 
        return ticketIdCounter;
    }

    /**
     * @notice Returns the list of ticket IDs owned by an address.
     * @param owner The address to query.
     * @return An array of token IDs owned by the address.
     */
    function getTicketsOwnedByAddress(address owner) external view returns (uint256[] memory) {
        return ticketOwnedByAddress[owner];
    }
}