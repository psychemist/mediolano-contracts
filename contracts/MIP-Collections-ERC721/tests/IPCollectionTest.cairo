use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, cheat_caller_address,
    start_cheat_caller_address, CheatSpan, stop_cheat_caller_address,
};
use core::result::ResultTrait;
use ip_collection_erc_721::interfaces::{
    IIPCollection::{IIPCollectionDispatcher, IIPCollectionDispatcherTrait},
};

use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};

// Test constants
fn OWNER() -> ContractAddress {
    contract_address_const::<0x123>()
}
fn USER1() -> ContractAddress {
    contract_address_const::<0x456>()
}
fn USER2() -> ContractAddress {
    contract_address_const::<0x789>()
}
const COLLECTION_ID: u256 = 1;
const TOKEN_ID: u256 = 1;

// // Deploy the IPCollection contract
fn deploy_contract() -> (IIPCollectionDispatcher, ContractAddress) {
    let owner = OWNER();
    let ip_nft_class_hash = declare("IPNft").unwrap().contract_class();
    let mut calldata = array![];

    owner.serialize(ref calldata);
    ip_nft_class_hash.serialize(ref calldata);

    let declare_result = declare("IPCollection").expect('Failed to declare contract');
    let contract_class = declare_result.contract_class();
    let (contract_address, _) = contract_class
        .deploy(@calldata)
        .expect('Failed to deploy contract');

    let dispatcher = IIPCollectionDispatcher { contract_address };
    (dispatcher, contract_address)
}


// Helper function to create a test collection
fn setup_collection(dispatcher: IIPCollectionDispatcher, ip_address: ContractAddress) -> u256 {
    let owner = OWNER();
    let name: ByteArray = "Test Collection";
    let symbol: ByteArray = "TST";
    let base_uri: ByteArray = "ipfs://QmCollectionBaseUri/";
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let collection_id = dispatcher.create_collection(name, symbol, base_uri);
    collection_id
}

#[test]
fn test_create_collection() {
    let (ip_dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));

    let name: ByteArray = "My Collection";
    let symbol: ByteArray = "MC";
    let base_uri: ByteArray = "ipfs://QmMyCollection";
    let collection_id = ip_dispatcher
        .create_collection(name.clone(), symbol.clone(), base_uri.clone());

    assert(collection_id == 1, 'Collection ID should be 1');
    let collection = ip_dispatcher.get_collection(collection_id);
    assert(collection.name == name, 'Collection name mismatch');
    assert(collection.symbol == symbol, 'Collection symbol mismatch');
    assert(collection.base_uri == base_uri, 'Collection base_uri mismatch');
    assert(collection.owner == owner, 'Collection owner mismatch');
    assert(collection.is_active, 'Collection should be active');
}

#[test]
fn test_create_multiple_collections() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    start_cheat_caller_address(ip_address, owner);

    let name1: ByteArray = "Collection 1";
    let symbol1: ByteArray = "C1";
    let base_uri1: ByteArray = "ipfs://QmCollection1";
    let collection_id1 = dispatcher.create_collection(name1, symbol1, base_uri1);
    assert(collection_id1 == 1, 'First collection ID should be 1');

    let name2: ByteArray = "Collection 2";
    let symbol2: ByteArray = "C2";
    let base_uri2: ByteArray = "ipfs://QmCollection2";
    let collection_id2 = dispatcher.create_collection(name2, symbol2, base_uri2);
    assert(collection_id2 == 2, 'Second ID should be 2');

    stop_cheat_caller_address(ip_address);
}

#[test]
fn test_mint_token() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, token_uri);
    assert(token_id == 0, 'Token ID should be 0');

    let token_id_arr = format!("{}:{}", collection_id, token_id);

    let token = dispatcher.get_token(token_id_arr);
    assert(token.collection_id == collection_id, 'Token collection ID mismatch');
    assert(token.token_id == token_id, 'Token ID mismatch');
    assert(token.owner == recipient, 'Token owner mismatch');
    assert(token.metadata_uri == "ipfs://QmCollectionBaseUri/0", 'Token metadata URI mismatch');
}

#[test]
#[should_panic(expected: ('Only collection owner can mint',))]
fn test_mint_not_owner() {
    let (dispatcher, address) = deploy_contract();
    let non_owner = USER1();
    let recipient = USER2();
    let collection_id = setup_collection(dispatcher, address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    start_cheat_caller_address(address, non_owner);
    dispatcher.mint(collection_id, recipient, token_uri);
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_mint_to_zero_address() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    start_cheat_caller_address(address, owner);
    dispatcher.mint(collection_id, contract_address_const::<0>(), token_uri);
}

#[test]
#[should_panic(expected: ('Only collection owner can mint',))]
fn test_mint_zero_caller() {
    let (dispatcher, address) = deploy_contract();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    start_cheat_caller_address(address, contract_address_const::<0>());
    dispatcher.mint(collection_id, recipient, token_uri);
}

#[test]
fn test_batch_mint_tokens() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient1 = USER1();
    let recipient2 = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uris = array!["ipfs://QmCollectionBaseUri/0", "ipfs://QmCollectionBaseUri/1"];

    let recipients = array![recipient1, recipient2];

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher.batch_mint(collection_id, recipients.clone(), token_uris.clone());

    assert(token_ids.len() == 2, 'Should mint 2 tokens in batch');
    let token0 = dispatcher.get_token(format!("{}:{}", collection_id, *token_ids.at(0)));
    let token1 = dispatcher.get_token(format!("{}:{}", collection_id, *token_ids.at(1)));
    assert(token0.owner == recipient1, 'First token owner mismatch');
    assert(token1.owner == recipient2, 'Second token owner mismatch');
    assert(token0.token_id == 0, 'First token ID should be 0');
    assert(token1.token_id == 1, 'Second token ID should be 1');
    assert(token0.metadata_uri == "ipfs://QmCollectionBaseUri/0", 'First token URI mismatch');
    assert(token1.metadata_uri == "ipfs://QmCollectionBaseUri/1", 'Second token URI mismatch');
}

#[test]
#[should_panic(expected: ('Recipients array is empty',))]
fn test_batch_mint_empty_recipients() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);

    let recipients = array![];
    let token_uris = array![];

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.batch_mint(collection_id, recipients, token_uris);
}

#[test]
#[should_panic(expected: ('Recipient is zero address',))]
fn test_batch_mint_zero_recipient() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uris = array!["ipfs://QmCollectionBaseUri/0"];
    let recipients = array![contract_address_const::<0>()];

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    dispatcher.batch_mint(collection_id, recipients, token_uris);
}

#[test]
fn test_burn_token() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, token_uri);

    let token = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, recipient, CheatSpan::TargetCalls(1));
    dispatcher.burn(token);
}

#[test]
#[should_panic(expected: ('Caller not token owner',))]
fn test_burn_not_owner() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let recipient = USER1();
    let non_owner = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, recipient, token_uri);

    let token = format!("{}:{}", collection_id, token_id);
    cheat_caller_address(ip_address, non_owner, CheatSpan::TargetCalls(1));
    dispatcher.burn(token);
}

#[test]
fn test_transfer_token_success() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    // Mint token to from_user
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, token_uri);

    let collection_data = dispatcher.get_collection(collection_id);

    let erc721_dispatcher = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(1));
    erc721_dispatcher.approve(ip_address, token_id);

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    let token = format!("{}:{}", collection_id, token_id);
    dispatcher.transfer_token(from_user, to_user, token);
}

#[test]
#[should_panic(expected: ('Contract not approved',))]
fn test_transfer_token_not_approved() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    start_cheat_caller_address(address, owner);
    let token_id = dispatcher.mint(collection_id, from_user, token_uri);
    stop_cheat_caller_address(address);

    start_cheat_caller_address(address, from_user);
    let token = format!("{}:{}", collection_id, token_id);
    dispatcher.transfer_token(from_user, to_user, token);
}
#[test]
#[should_panic(expected: ('Collection is not active',))]
fn test_transfer_token_inactive_collection() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uri: ByteArray = "ipfs://QmCollectionBaseUri/0";

    // Mint token to from_user
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_id = dispatcher.mint(collection_id, from_user, token_uri);

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    let token = format!("{}:{}", collection_id + 1, token_id);

    dispatcher.transfer_token(from_user, to_user, token);
}

#[test]
fn test_list_user_collections_empty() {
    let (dispatcher, _) = deploy_contract();
    let random_user = USER2();
    let collections = dispatcher.list_user_collections(random_user);
    assert(collections.len() == 0, 'Should have no collections');
}

#[test]
fn test_batch_transfer_tokens_success() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);

    // Mint two tokens to from_user
    let recipients = array![from_user, from_user];
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_uris = array!["ipfs://QmCollectionBaseUri/0", "ipfs://QmCollectionBaseUri/1"];
    let token_ids = dispatcher.batch_mint(collection_id, recipients.clone(), token_uris);

    let collection_data = dispatcher.get_collection(collection_id);
    let erc721_dispatcher = IERC721Dispatcher { contract_address: collection_data.ip_nft };

    // Approve contract for both tokens
    cheat_caller_address(collection_data.ip_nft, from_user, CheatSpan::TargetCalls(2));
    erc721_dispatcher.approve(ip_address, *token_ids.at(0));
    erc721_dispatcher.approve(ip_address, *token_ids.at(1));

    // Prepare tokens as ByteArray
    let token0 = format!("{}:{}", collection_id, *token_ids.at(0));
    let token1 = format!("{}:{}", collection_id, *token_ids.at(1));
    let tokens = array![token0, token1];

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, tokens.clone());

    // Check new owners
    let token_data0 = dispatcher.get_token(tokens.at(0).clone());
    let token_data1 = dispatcher.get_token(tokens.at(1).clone());
    assert(token_data0.owner == to_user, 'Token0 should be transferred');
    assert(token_data1.owner == to_user, 'Token1 should be transferred');
}

#[test]
#[should_panic(expected: ('Collection is not active',))]
fn test_batch_transfer_inactive_collection() {
    let (dispatcher, ip_address) = deploy_contract();
    let owner = OWNER();
    let from_user = USER1();
    let to_user = USER2();
    let collection_id = setup_collection(dispatcher, ip_address);
    let token_uris = array!["ipfs://QmCollectionBaseUri/0"];
    // Mint token to from_user
    cheat_caller_address(ip_address, owner, CheatSpan::TargetCalls(1));
    let token_ids = dispatcher.batch_mint(collection_id, array![from_user], token_uris);

    // Use wrong collection_id (inactive)
    let token = format!("{}:{}", collection_id + 1, *token_ids.at(0));
    let tokens = array![token];

    cheat_caller_address(ip_address, from_user, CheatSpan::TargetCalls(1));
    dispatcher.batch_transfer(from_user, to_user, tokens);
}

#[test]
fn test_verification_functions() {
    let (dispatcher, address) = deploy_contract();
    let owner = OWNER();
    let collection_id = setup_collection(dispatcher, address);
    let token_uri = "ipfs://QmCollectionBaseUri/0";

    start_cheat_caller_address(address, owner);
    let token_id = dispatcher.mint(collection_id, USER1(), token_uri);
    let token = format!("{}:{}", collection_id, token_id);
    assert(dispatcher.is_valid_collection(collection_id), 'Collection should be valid');
    assert(dispatcher.is_valid_token(token), 'Token should be valid');
    assert(dispatcher.is_collection_owner(collection_id, owner), 'Owner should be correct');
    stop_cheat_caller_address(address);
}

