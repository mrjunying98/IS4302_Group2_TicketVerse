// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import Ownable from OpenZeppelin to restrict certain functions to the contract owner.
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ILoyaltySystem
 * @notice Interface for the LoyaltySystem contract.
 * This interface allows external contracts to interact with the LoyaltySystem
 * by calling the addPoints function.
 */
interface ILoyaltySystem {
    function addPoints(address user, uint256 points) external;
}

/**
 * @title LoyaltySystem
 * @notice This contract manages a loyalty points system for users.
 * Users accumulate points based on interactions with your system (e.g., ticket purchases).
 * Only authorized operators (or the owner) can modify points.
 */
contract LoyaltySystem is Ownable {
    // Mapping to store the loyalty points for each user.
    mapping(address => uint256) private points;

    // Mapping to track addresses that are authorized to modify points.
    // Authorized operators can add or deduct points on behalf of users.
    mapping(address => bool) public authorizedOperators;

    // ======================================================
    // EVENTS
    // ======================================================

    /// @notice Emitted when points are added to a user's account.
    event PointsAdded(address indexed user, uint256 amount);

    /// @notice Emitted when points are deducted from a user's account.
    event PointsDeducted(address indexed user, uint256 amount);

    /// @notice Emitted when an operator is authorized or deauthorized.
    event AuthorizedOperatorSet(address indexed operator, bool authorized);

    // ======================================================
    // MODIFIERS
    // ======================================================

    /**
     * @notice Restricts function calls to only authorized operators.
     * @dev The function will revert if msg.sender is not in the authorizedOperators mapping.
     */
    modifier onlyAuthorized() {
        require(authorizedOperators[msg.sender], "Not authorized to Add Points");
        _;
    }

    // ======================================================
    // ADMIN FUNCTIONS
    // ======================================================

    /**
     * @notice Sets or unsets an address as an authorized operator.
     * @param operator The address whose authorization status is to be updated.
     * @param authorized A boolean indicating whether the operator is authorized (true) or not (false).
     * @dev Only the owner of the contract can call this function.
     */
    function setAuthorizedOperator(address operator, bool authorized) external onlyOwner {
        require(operator != address(0), "Invalid operator address");
        authorizedOperators[operator] = authorized;
        emit AuthorizedOperatorSet(operator, authorized);
    }

    // ======================================================
    // LOYALTY POINT MANAGEMENT FUNCTIONS
    // ======================================================

    /**
     * @notice Adds loyalty points to a user's account.
     * @param user The address of the user who will receive the points.
     * @param amount The number of points to add.
     * @dev Only authorized operators can call this function.
     */
    function addPoints(address user, uint256 amount) external onlyAuthorized {
        require(user != address(0), "Invalid user address");
        points[user] += amount;
        emit PointsAdded(user, amount);
    }

    /**
     * @notice Deducts loyalty points from a user's account.
     * @param user The address of the user from whom points will be deducted.
     * @param amount The number of points to deduct.
     * @dev Only authorized operators can call this function.
     *      The function reverts if the user has insufficient points.
     */
    function deductPoints(address user, uint256 amount) external onlyAuthorized {
        require(user != address(0), "Invalid user address");
        require(points[user] >= amount, "Insufficient points");
        points[user] -= amount;
        emit PointsDeducted(user, amount);
    }

    /**
     * @notice Retrieves the loyalty points balance for a given user.
     * @param user The address of the user.
     * @return The current number of loyalty points for the user.
     */
    function getPoints(address user) external view returns (uint256) {
        return points[user];
    }
}