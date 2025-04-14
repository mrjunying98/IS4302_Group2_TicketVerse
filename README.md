# IS4302 - Group 2 -TicketVerse

TicketVerse is a decentralized ticketing platform that leverages blockchain technology to deliver secure, transparent, and efficient ticket sales and resales. The platform addresses common issues in the traditional ticketing industry—such as counterfeit tickets, unfair allocation, and fraudulent secondary sales—by using NFT-based tickets, a lottery-based sales mechanism, and a secure marketplace.

## Team
Lim Jun Ying - A0235191J

## Overview

TicketVerse consists of a suite of smart contracts designed to cover every aspect of the ticketing process:

- **ConcertTicket:** An ERC721 smart contract that mints unique concert tickets and manages seating details.
- **TicketSalesFactory:** A factory contract that uses a cloning mechanism to quickly deploy new event-specific ticketing ecosystems.
- **TicketLotterySale:** Manages a lottery-based ticket sales process by leveraging Chainlink VRF for verifiable randomness, ensuring fair distribution.
- **TicketMarketPlace:** Provides a controlled resale marketplace where tickets are sold at regulated prices to prevent fraudulent practices.
- **LoyaltySystem:** A loyalty program that rewards users with points for interacting with the platform, encouraging repeat usage and engagement.

## Key Features

- **NFT Ticketing:** Every ticket is represented as a unique ERC721 token, ensuring authenticity and transparency.
- **Fair Distribution:** Lottery-based sales ensure a fair allocation of high-demand tickets, reducing the risks of bot manipulation and unfair practices.
- **Secure Resale:** A controlled marketplace with price caps enables secure and reliable secondary ticket sales.
- **Loyalty Rewards:** Users earn loyalty points for various platform actions, which can eventually lead to rewards and exclusive benefits.
- **Easy Deployment:** By cloning standardized smart contract templates, TicketVerse significantly lowers the barriers to entry for event organizers.

## System Architecture

TicketVerse features a modular design where each component interacts seamlessly:
- **TicketSalesFactory** deploys new event-specific contracts (ConcertTicket, TicketLotterySale, TicketMarketPlace) via a cloning mechanism.
- **ConcertTicket** manages the issuance and transfer of NFT tickets.
- **TicketLotterySale** handles user pre-registrations, executes the lottery using Chainlink VRF, and facilitates ticket claims.
- **TicketMarketPlace** oversees the listing and resale of tickets, ensuring transactions occur at regulated prices.
- **LoyaltySystem** tracks and rewards user interactions, fostering a community-driven ecosystem.

## Getting Started

### Prerequisites
- Node.js
- npm 
- Hardhat 

