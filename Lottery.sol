// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/ERC721.sol)

pragma solidity ^0.8.0;

import "./NFT.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Lottery {
    using Counters for Counters.Counter;
    Counters.Counter private tids; 

    uint price; //ticket price in wei

    //Struct that represent a round of the lottery
    struct lotteryRound {
        uint256 number;
        uint8 state; // 1 = active, 2 = disactive, 3 = finished
        uint start_block; //block number from which the lottery starts
    }
    lotteryRound round;

    uint M; // duration of a round (n° blocks)
    uint256 K; //paramater for random number generator
    address lottery_operator;
    uint[5] standard_numbers; //from 1 to 69
    uint special_number; //Powerball, from 1 to 26

    LotteryGame item; //Lottery collection which contains NFTs

    //Struct that represent a NFT
    struct lotteryCollectible {
        uint256 tokenId;
        uint rank;
        string content;
    }
    lotteryCollectible[] collection;

    uint[] prizes; //temporary pool of prizes of a given rank

    modifier lotteryOperator {
        require (lottery_operator == msg.sender, "Error: not authorized");
        _;
    }

    //Struct to mantain players of a round
    struct Player {
        address player_address;
        uint[5] numbers;
        uint powerball;
    }
    Player[] lottery_players;
    
    //Struct to mantain winners of a round
    struct Winner {
        address winner;
        uint rank;
    }
    Winner[] lottery_winners;

    /* ------------------------------------------------------------ */

    //Function that reset the drawn numbers 
    function resetDraw() internal{
        for (uint i = 0; i < 5; i++) {
            standard_numbers[i] = 0;
        }

        special_number = 0;
    }

    //Function that check the range of the drawn numbers
    function convertDraws(uint n, bool isSpecial) internal pure returns (uint){
        uint num = 0;

        if(isSpecial){
            num = n % 26;
        } else {
            num = n % 69;
        }

        if(num == 0){
            num = 1;
        }

        return num;

    }

    //Function that assign the rank basing on the standard numbers and the powerball
    function assignRanks(uint numbers, bool is_powerball) internal pure returns(uint){

        uint rank = 0;

        if(numbers == 5 && is_powerball) rank = 1;

        if(numbers == 5 && !is_powerball) rank = 2;

        if(numbers == 4 && is_powerball) rank = 3;

        if((numbers == 4 && !is_powerball) || (numbers == 3 && is_powerball)) rank = 4;

        if((numbers == 3 && !is_powerball) || (numbers == 2 && is_powerball)) rank = 5;

        if((numbers == 2 && !is_powerball) || (numbers == 1 && is_powerball)) rank = 6;

        if(numbers == 1 && !is_powerball) rank = 7;

        if(numbers == 0 && is_powerball) rank = 8;

        return rank;

    }

    //Function that takes a seed and generates a random number leveraging on a source of randomness from the blockchain 
    function generateRandomNumber(uint seed) internal view returns(uint){

        uint end_lottery_block = round.start_block + M;

        bytes32 rand = keccak256(abi.encode(end_lottery_block, seed, K));
        uint random_number = uint(rand);

        return random_number;
    }

    //Function that clean up the data structures
    function delete_() internal{

        for(uint i = 0; i < 5; i++){
            standard_numbers[i] = 0;
        } 

        special_number = 0;

        delete prizes;
        delete lottery_players;
        delete lottery_winners;
    }

    event Collectible(string str, uint id, uint rank, string content);

    //Function that mint n NFTs of rank r, if necessary
    function mintOnDemand(uint n, uint r) internal lotteryOperator { 
        require(n > 0, "Error: n must be positive!");
        require(r >= 1 && r <= 8, "Error: rank must be between 1 and 8!");

        for(uint j = 0; j < n; j++){
            lotteryCollectible memory new_item;
            tids.increment();
            new_item.tokenId = tids.current();
            new_item.rank = r;
            string memory str = string(abi.encodePacked("Content of Token ", Strings.toString(tids.current()), " of rank ", Strings.toString(new_item.rank)));
            new_item.content = str;
            collection.push(new_item);
            emit Collectible("Minted NFT", new_item.tokenId, new_item.rank, new_item.content);
            item.mint(lottery_operator, new_item.tokenId, new_item.content);
        }
    }

    /* ----------------------------------------------------------------------- */

    constructor(uint price_, uint M_, uint256 K_, address lottery_address) {

        if(price_ <= 0) {
            price = 10 wei;
        } else {
            price = price_;
        }

        if (M_ <= 0) {
            M = 10;
        } else {
            M = M_;
        }

        if (K_ < 6) {
            K = 123;
        } else {
            K = K_;
        }

        round = lotteryRound(0, 0, 0);
        lottery_operator = msg.sender;

        resetDraw();

        item = LotteryGame(lottery_address);

    }

    event Round(string str, uint round_number, uint round_state, uint round_start);

    //Function that start a new lottery round
    function startNewRound() public lotteryOperator returns (bool){ 
        require(((round.number == 0) || ((block.number - round.start_block) >= M && round.state == 3)), "Error: impossible to start a new lottery round!");
        
        round.number = round.number + 1;
        round.state = 1;
        round.start_block = block.number;

        emit Round("New Round", round.number, round.state, round.start_block);

        resetDraw();

        return true;

    }

    event Player_(string str, address player, uint number1, uint number2, uint number3, uint number4, uint number5, uint powerball);

    //Function used by a player to select the numbers and buy a ticket
    function buy (uint n1, uint n2, uint n3, uint n4, uint n5, uint n6) public payable returns (bool){

        require((n1 >= 1 && n1 <= 69) || (n2 >= 1 && n2 <= 69) || (n3 >= 1 && n3 <= 69) || (n4 >= 1 && n4 <= 69) || (n5 >= 1 && n5 <= 69) || (n6 >= 1 && n6 <= 26), 
                "Error: invalid lottery numbers. The first five numbers must be between 1 and 69 while the powerball must be between 1 and 26!");
        require(n1 != n2 && n1 != n3 && n1 != n4 && n1 != n5 && n2 != n3 && n2 != n4 && n2 != n5 && n3 != n4 && n3 != n5 && n4 != n5, "Error: numbers must be different from each other!");
        require(round.state == 1, "Error: lottery round is not active, impossible to buy tickets!");
        require(msg.value >= price, "Error: insufficient funds!");

        Player memory player;
        player.player_address = msg.sender;
        player.numbers[0] = n1;
        player.numbers[1] = n2;
        player.numbers[2] = n3;
        player.numbers[3] = n4;
        player.numbers[4] = n5;
        player.powerball = n6;

        emit Player_("Ticket bought", msg.sender, n1, n2, n3, n4, n5, n6);

        lottery_players.push(player);

        if(msg.value > price){
            uint change = msg.value - price;
            payable(msg.sender).transfer(change);
        }

        return true;
        
    }

    event WinningTicket(string str, uint n1, uint n2, uint n3, uint n4, uint n5, uint n6);

    //Function that draw the winning ticket using a RNG
    function drawNumbers() public lotteryOperator returns (bool){

        require(round.state == 1 && (block.number - round.start_block) >= M, "Error: invalid lottery state, impossible to draw numbers!");

        uint seed = 0;
        uint num = 0;

        for(uint i = 0; i < 6; i++){
            seed = block.number + i;
            uint rand = generateRandomNumber(seed);
            if(i == 5){
                num = convertDraws(rand, true);
                special_number = num;
            } else {
                num = convertDraws(rand, false);
                standard_numbers[i] = num;
            }
        }

        emit WinningTicket("Winning ticket", standard_numbers[0], standard_numbers[1], standard_numbers[2], standard_numbers[3], standard_numbers[4], special_number);

        round.state = 2; //disactive round (draw has been performed)

        return true;
    }


    event Prize(string str, uint id_);

    //Function that check if there are winners and assign appropriate prizes to them
    function givePrizes() public lotteryOperator returns(bool){

        require(round.state == 2, "Error: wrong round state, impossible to assign prizes!");

        //Loop that compare the numbers picked by the users with the numbers drawn by the lottery
        for(uint i = 0; i < lottery_players.length; i++){
            uint winner_numbers = 0;
            bool winner_powerball = false;

            for(uint j = 0; j < 5; j++){
                for(uint m = 0; m < 5; m++){
                    if(lottery_players[i].numbers[j] == standard_numbers[m]){
                        winner_numbers = winner_numbers + 1;
                        break;
                    }
                }
            }

            if(lottery_players[i].powerball == special_number){
                winner_powerball = true;
            }

            //Pick the winners of the lottery round and add them in a winners' list
            if(winner_numbers > 0 || winner_powerball == true){
                uint prize_rank = assignRanks(winner_numbers, winner_powerball);
                Winner memory winner = Winner(lottery_players[i].player_address, prize_rank);
                lottery_winners.push(winner);
            }
        }

        
        //Check if there is a number of winners of a certain class which is greater than the number of prizes of that class
        uint[8] memory num_winners_rank; //array which mantain the number of winners for each rank

        for(uint j = 0; j < 8; j++){
            num_winners_rank[j] = 0;
        }

        for(uint i = 0; i < lottery_winners.length; i++){
            uint winner_rank = lottery_winners[i].rank;
            num_winners_rank[winner_rank - 1]++;
        }

        //Mint an amount of prizes of a certain rank (only if the number of winners of a certain class is greater than the prizes of that class)
        for(uint j = 0; j < 8; j++){
            uint rank_ = j + 1;
            uint prizes_to_mint = num_winners_rank[j];

            if(prizes_to_mint > 0){
                mintOnDemand(prizes_to_mint, rank_);
            }
        }

    
        //Select appropriate prizes and assign to the winners according to their ranks
        for(uint k = 0; k < lottery_winners.length; k++){
            uint winner_rank = lottery_winners[k].rank;

            //Get all prizes of a given rank
            for(uint n = 0; n < collection.length; n++){
                if(collection[n].rank == winner_rank){
                    prizes.push(collection[n].tokenId);
                }
            }

            //Select a random prize of a certain rank 
            uint seed = block.number + k;
            uint random = generateRandomNumber(seed);
            uint prize_id = random % (prizes.length);
            uint prize = prizes[prize_id];

            emit Prize("Assigned prize", prize);

            item.safeTransferFrom(lottery_operator, lottery_winners[k].winner, prize); //send the prize to the winner

            //Remove the prize from the collection of all available prizes
            for(uint t = 0; t < collection.length; t++){
                if(collection[t].tokenId == prize){
                    collection[t] = collection[collection.length - 1];
                    collection.pop(); 
                }
            }

            delete prizes; //clean the temporary pool of prizes of a given rank

        }

        round.state = 3; //round finished

        return true;
    }

    //Function that mint n NFTs for each class 
    function mint(uint n) public lotteryOperator { 
        require(n > 0, "Error: n must be positive!");

        for(uint i = 0; i < 8; i++){
            for(uint j = 0; j < n; j++){
                lotteryCollectible memory new_item;
                tids.increment();
                new_item.tokenId = tids.current();
                new_item.rank = i + 1;
                string memory str = string(abi.encodePacked("Content of Token ", Strings.toString(tids.current()), " of rank ", Strings.toString(new_item.rank)));
                new_item.content = str;
                
                collection.push(new_item);

                emit Collectible("Minted NFT", new_item.tokenId, new_item.rank, new_item.content);

                item.mint(lottery_operator, new_item.tokenId, new_item.content);
            }
        }
    }

    event Balance(string str, uint tot);
    //Function that close the lottery round and manage all the following operations
    function closeLottery() public lotteryOperator {

        uint total_balance = 0;

        emit Round("Round before closing the lottery", round.number, round.state, round.start_block);

        if(round.state == 1){
            emit Balance("Balance of the smart contract", address(this).balance);
            emit Balance("Balance of the lottery operator", lottery_operator.balance);

            for(uint i = 0; i < lottery_players.length; i++){
                emit Balance("Balance of the player before the refund", lottery_players[i].player_address.balance);
                payable(lottery_players[i].player_address).transfer(price);
                emit Balance("Balance of the player after the refund", lottery_players[i].player_address.balance);
            }

            delete_();
            round.state = 3;
            emit Round("Round after closing the lottery",round.number, round.state, round.start_block);

            return;
        }

        if(round.state == 2){
            givePrizes();
            total_balance = price * lottery_players.length;
            emit Balance("Balance of the smart contract before the end of the lottery", address(this).balance);
            emit Balance("Balance of the lottery operator before the end of the lottery", lottery_operator.balance);
            payable(lottery_operator).transfer(total_balance);
            emit Balance("Balance of the smart contract after the end of the lottery", address(this).balance);
            emit Balance("Balance of the lottery operator after the end of the lottery", lottery_operator.balance);
            delete_();
            round.state = 3;
            emit Round("Round after closing the lottery", round.number, round.state, round.start_block);
        
            return;
        }

        emit Balance("Balance of the smart contract before the end of the lottery", address(this).balance);
        emit Balance("Balance of the lottery operator before the end of the lottery", lottery_operator.balance);

        total_balance = price * lottery_players.length;
        payable(lottery_operator).transfer(total_balance);
        delete_();

        round.state = 3; //lottery finished
        emit Round("Round after closing the lottery", round.number, round.state, round.start_block);
        emit Balance("Balance of the smart contract after the end of the lottery", address(this).balance);
        emit Balance("Balance of the lottery operator after the end of the lottery", lottery_operator.balance);
    
    }
}

