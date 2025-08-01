use starknet::{ContractAddress, contract_address_const, get_block_timestamp};
use snforge_std::{
    start_cheat_caller_address, stop_cheat_caller_address, start_cheat_block_timestamp,
    stop_cheat_block_timestamp,
};
use ip_collective_agreement::interface::{
    IOwnershipRegistryDispatcher, IOwnershipRegistryDispatcherTrait, IIPAssetManagerDispatcher,
    IIPAssetManagerDispatcherTrait, IRevenueDistributionDispatcher,
    IRevenueDistributionDispatcherTrait,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use core::num::traits::Bounded;

use super::test_utils::{
    USER, SPENDER, MARKETPLACE, setup, register_test_asset, deploy_mock_erc20,
    deploy_erc1155_receiver,
};

#[test]
fn test_receive_revenue_success() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();

    // Register test asset
    let (asset_id, _, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );

    // Receive revenue
    let revenue_amount = 1000_u256;

    start_cheat_caller_address(contract_address, licensee);
    let success = revenue_dispatcher
        .receive_revenue(asset_id, erc20_dispatcher.contract_address, revenue_amount);
    stop_cheat_caller_address(contract_address);

    assert!(success == true, "Revenue receiving should succeed");

    // Verify accumulated revenue
    let accumulated = revenue_dispatcher
        .get_accumulated_revenue(asset_id, erc20_dispatcher.contract_address);
    assert!(accumulated == revenue_amount, "Wrong accumulated revenue");
}

#[test]
fn test_multiple_revenue_receipts() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let marketplace = MARKETPLACE();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset
    let (asset_id, _, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );

    // Multiple revenue receipts from different sources
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 500_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, marketplace);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 300_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 200_u256);
    stop_cheat_caller_address(contract_address);

    // Verify total accumulated revenue
    let accumulated = revenue_dispatcher.get_accumulated_revenue(asset_id, erc20);
    assert!(accumulated == 1000, "Should accumulate all revenue");
}

#[test]
fn test_distribute_revenue_success() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset and receive revenue
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );

    let creator1: ContractAddress = *creators[0];
    let creator2: ContractAddress = *creators[1];
    let creator3: ContractAddress = *creators[2];

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Distribute revenue as CREATOR1
    start_cheat_caller_address(contract_address, creator1);
    let success = revenue_dispatcher.distribute_revenue(asset_id, erc20, 800_u256);
    stop_cheat_caller_address(contract_address);

    assert!(success == true, "Revenue distribution should succeed");

    // Verify pending revenue for each owner
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    let creator2_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator2, erc20);
    let creator3_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator3, erc20);

    assert!(creator1_pending == 400, "CREATOR1 should have 400 pending"); // 50% of 800
    assert!(creator2_pending == 240, "CREATOR2 should have 240 pending"); // 30% of 800
    assert!(creator3_pending == 160, "CREATOR3 should have 160 pending"); // 20% of 800

    // Verify remaining accumulated revenue
    let remaining_accumulated = revenue_dispatcher.get_accumulated_revenue(asset_id, erc20);
    assert!(remaining_accumulated == 200, "Should have 200 remaining"); // 1000 - 800

    // Verify total distributed
    let total_distributed = revenue_dispatcher.get_total_revenue_distributed(asset_id, erc20);
    assert!(total_distributed == 800, "Total distributed should be 800");
}

#[test]
fn test_distribute_all_revenue() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset and receive revenue
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];
    let creator2: ContractAddress = *creators[1];

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1500_u256);
    stop_cheat_caller_address(contract_address);

    // Distribute all accumulated revenue
    start_cheat_caller_address(contract_address, creator2);
    let success = revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    assert!(success == true, "Distribute all should succeed");

    // Verify all revenue was distributed
    let remaining_accumulated = revenue_dispatcher.get_accumulated_revenue(asset_id, erc20);
    assert!(remaining_accumulated == 0, "Should have no remaining revenue");

    // Verify pending amounts
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    assert!(creator1_pending == 750, "CREATOR1 should have 750 pending"); // 50% of 1500
}

#[test]
fn test_withdraw_pending_revenue() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset, receive and distribute revenue
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Withdraw as CREATOR1
    start_cheat_caller_address(contract_address, creator1);
    let withdrawn_amount = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    assert(withdrawn_amount == 500, 'Should withdraw 500'); // 50% of 1000

    // Verify pending revenue is now zero
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    assert!(creator1_pending == 0, "Pending should be zero after withdrawal");

    // Verify total earned tracking
    let creator1_total_earned = revenue_dispatcher
        .get_owner_total_earned(asset_id, creator1, erc20);
    assert!(creator1_total_earned == 500, "Total earned should be 500");
}

#[test]
#[should_panic(expected: ('Invalid asset ID',))]
fn test_receive_revenue_invalid_asset() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(999_u256, erc20, 1000_u256); // Non-existent asset
}

#[test]
#[should_panic(expected: "Amount must be greater than zero")]
fn test_receive_revenue_zero_amount() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    let (asset_id, _, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 0_u256);
}

#[test]
#[should_panic(expected: "Only owners can distribute revenue")]
fn test_distribute_revenue_not_owner() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;
    let non_owner = contract_address_const::<0x888>();

    // Register test asset and receive revenue
    let (asset_id, _, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Try to distribute as non-owner
    start_cheat_caller_address(contract_address, non_owner);
    revenue_dispatcher.distribute_revenue(asset_id, erc20, 500_u256);
}

#[test]
#[should_panic(expected: "Insufficient accumulated revenue")]
fn test_distribute_revenue_insufficient_accumulated() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset and receive small amount
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 500_u256);
    stop_cheat_caller_address(contract_address);

    // Try to distribute more than accumulated
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_revenue(asset_id, erc20, 1000_u256);
}

#[test]
#[should_panic(expected: ('Not an asset owner',))]
fn test_withdraw_not_owner() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;
    let non_owner = contract_address_const::<0x888>();

    // Register test asset, receive and distribute revenue
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Try to withdraw as non-owner
    start_cheat_caller_address(contract_address, non_owner);
    revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
}

#[test]
#[should_panic(expected: "No pending revenue")]
fn test_withdraw_no_pending_revenue() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();

    // Register test asset (no revenue received/distributed)
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    let erc20 = erc20_dispatcher.contract_address;
    // Try to withdraw without any pending revenue
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
}

#[test]
fn test_minimum_distribution() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    // Set minimum distribution
    start_cheat_caller_address(contract_address, creator1);
    let success = revenue_dispatcher.set_minimum_distribution(asset_id, 100_u256, erc20);
    stop_cheat_caller_address(contract_address);

    assert!(success == true, "Should set minimum distribution");

    // Verify minimum was set
    let min_amount = revenue_dispatcher.get_minimum_distribution(asset_id, erc20);
    assert!(min_amount == 100, "Wrong minimum distribution");

    // Receive revenue
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Try to distribute amount equal to minimum (should succeed)
    start_cheat_caller_address(contract_address, creator1);
    let distribute_success = revenue_dispatcher.distribute_revenue(asset_id, erc20, 100_u256);
    stop_cheat_caller_address(contract_address);

    assert!(distribute_success == true, "Should distribute minimum amount");
}

#[test]
#[should_panic(expected: "Amount below minimum distribution")]
fn test_distribute_below_minimum() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset and set minimum
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.set_minimum_distribution(asset_id, 500_u256, erc20);
    stop_cheat_caller_address(contract_address);

    // Receive revenue
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Try to distribute below minimum
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_revenue(asset_id, erc20, 300_u256); // Below 500
}

#[test]
fn test_revenue_flow_with_ownership_transfer() {
    let (
        contract_address,
        ownership_dispatcher,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;
    let new_owner = USER();

    // Register test asset
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];

    // Initial revenue receipt and distribution
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // CREATOR1 transfers 20% to new_owner
    start_cheat_caller_address(contract_address, creator1);
    ownership_dispatcher.transfer_ownership_share(asset_id, creator1, new_owner, 20_u256);
    stop_cheat_caller_address(contract_address);

    // New revenue after ownership change
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 2000_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Verify pending revenue reflects new ownership structure
    // CREATOR1 now has 30% (was 50%, transferred 20%)
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    // Should be 500 (from first distribution) + 600 (30% of 2000) = 1100
    assert!(creator1_pending == 1100, "CREATOR1 should have 1100 pending");

    // new_owner should have 20% of second distribution = 400
    let new_owner_pending = revenue_dispatcher.get_pending_revenue(asset_id, new_owner, erc20);

    assert!(new_owner_pending == 400, "New owner should have 400 pending");
}

#[test]
fn test_partial_distributions_and_withdrawals() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let licensee = SPENDER();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];
    let creator2: ContractAddress = *creators[1];

    // Receive revenue in chunks
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 500_u256);
    stop_cheat_caller_address(contract_address);

    // Partial distribution
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_revenue(asset_id, erc20, 800_u256);
    stop_cheat_caller_address(contract_address);

    // CREATOR1 withdraws
    start_cheat_caller_address(contract_address, creator1);
    let first_withdrawal = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    assert!(first_withdrawal == 400, "First withdrawal should be 400"); // 50% of 800

    // Distribute remaining revenue
    start_cheat_caller_address(contract_address, creator2);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20); // Distribute remaining 700
    stop_cheat_caller_address(contract_address);

    // CREATOR1 withdraws again
    start_cheat_caller_address(contract_address, creator1);
    let second_withdrawal = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    assert!(second_withdrawal == 350, "Second withdrawal should be 350"); // 50% of 700

    // Verify total earned
    let creator1_total_earned = revenue_dispatcher
        .get_owner_total_earned(asset_id, creator1, erc20);
    assert!(creator1_total_earned == 750, "Total earned should be 750"); // 400 + 350
}

#[test]
fn test_complete_revenue_cycle() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    setup();
    let licensee = SPENDER();
    let marketplace = MARKETPLACE();
    let erc20 = erc20_dispatcher.contract_address;

    // Register test asset
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1: ContractAddress = *creators[0];
    let creator2: ContractAddress = *creators[1];
    let creator3: ContractAddress = *creators[2];

    // Step 1: Multiple revenue sources
    start_cheat_caller_address(contract_address, licensee);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 600_u256);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, marketplace);
    revenue_dispatcher.receive_revenue(asset_id, erc20, 400_u256);
    stop_cheat_caller_address(contract_address);

    // Step 2: Owner-controlled distribution
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Step 3: All owners withdraw
    start_cheat_caller_address(contract_address, creator1);
    let creator1_withdrawn = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator2);
    let creator2_withdrawn = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, creator3);
    let creator3_withdrawn = revenue_dispatcher.withdraw_pending_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Verify complete cycle
    assert!(creator1_withdrawn == 500, "CREATOR1 should withdraw 500"); // 50% of 1000
    assert!(creator2_withdrawn == 300, "CREATOR2 should withdraw 300"); // 30% of 1000
    assert!(creator3_withdrawn == 200, "CREATOR3 should withdraw 200"); // 20% of 1000

    // Verify no pending revenue remains
    let total_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20)
        + revenue_dispatcher.get_pending_revenue(asset_id, creator2, erc20)
        + revenue_dispatcher.get_pending_revenue(asset_id, creator3, erc20);
    assert!(total_pending == 0, "Should have no pending revenue");

    // Verify total distributed
    let total_distributed = revenue_dispatcher.get_total_revenue_distributed(asset_id, erc20);
    assert!(total_distributed == 1000, "Total distributed should be 1000");
}

#[test]
fn test_revenue_distribution_with_fractional_percentages() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();

    // Create asset with percentages that might cause rounding issues
    let creators = array![
        deploy_erc1155_receiver(), deploy_erc1155_receiver(), deploy_erc1155_receiver(),
    ]
        .span();
    let ownership_percentages = array![33_u256, 33_u256, 34_u256].span(); // 33%, 33%, 34%
    let governance_weights = array![33_u256, 33_u256, 34_u256].span();

    start_cheat_caller_address(contract_address, owner_address);
    let asset_id = asset_dispatcher
        .register_ip_asset(
            'MUSIC', "ipfs://fractional-test", creators, ownership_percentages, governance_weights,
        );
    stop_cheat_caller_address(contract_address);

    let creator1 = *creators[0];
    let creator2 = *creators[1];
    let creator3 = *creators[2];
    let erc20 = erc20_dispatcher.contract_address;

    // Receive revenue that's hard to divide evenly
    start_cheat_caller_address(contract_address, SPENDER());
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256); // $10.00
    stop_cheat_caller_address(contract_address);

    // Distribute all revenue
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Check distribution (33% of 1000 = 330, 34% of 1000 = 340)
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    let creator2_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator2, erc20);
    let creator3_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator3, erc20);

    assert!(creator1_pending == 330, "Creator1 should get 330 (33%)");
    assert!(creator2_pending == 330, "Creator2 should get 330 (33%)");
    assert!(creator3_pending == 340, "Creator3 should get 340 (34%)");

    // Verify total adds up exactly
    let total_distributed = creator1_pending + creator2_pending + creator3_pending;
    assert!(total_distributed == 1000, "Total should equal original amount");
}

#[test]
fn test_revenue_distribution_after_ownership_transfer_edge_case() {
    let (
        contract_address,
        ownership_dispatcher,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1 = *creators[0]; // Initially 50%
    let creator2 = *creators[1]; // Initially 30%
    let new_owner = USER();
    let erc20 = erc20_dispatcher.contract_address;

    // Transfer ALL of creator1's ownership to new_owner
    start_cheat_caller_address(contract_address, creator1);
    ownership_dispatcher.transfer_ownership_share(asset_id, creator1, new_owner, 50_u256);
    stop_cheat_caller_address(contract_address);

    // Verify creator1 now has 0% ownership
    let creator1_percentage = ownership_dispatcher.get_owner_percentage(asset_id, creator1);
    assert!(creator1_percentage == 0, "Creator1 should have 0% after transferring all");

    // Receive and distribute revenue
    start_cheat_caller_address(contract_address, SPENDER());
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Only creator2 can now distribute (creator1 has no ownership)
    start_cheat_caller_address(contract_address, creator2);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20);
    stop_cheat_caller_address(contract_address);

    // Check pending amounts
    let creator1_pending = revenue_dispatcher.get_pending_revenue(asset_id, creator1, erc20);
    let new_owner_pending = revenue_dispatcher.get_pending_revenue(asset_id, new_owner, erc20);

    assert!(
        creator1_pending == 0, "Creator1 should get no revenue after transferring all ownership",
    );
    assert!(new_owner_pending == 500, "New owner should get 50% of revenue");
}

#[test]
#[should_panic(expected: "Only owners can distribute revenue")]
fn test_distribute_revenue_after_losing_all_ownership() {
    let (
        contract_address,
        ownership_dispatcher,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1 = *creators[0];
    let new_owner = USER();
    let erc20 = erc20_dispatcher.contract_address;

    // Transfer all ownership away
    start_cheat_caller_address(contract_address, creator1);
    ownership_dispatcher.transfer_ownership_share(asset_id, creator1, new_owner, 50_u256);
    stop_cheat_caller_address(contract_address);

    // Receive revenue
    start_cheat_caller_address(contract_address, SPENDER());
    revenue_dispatcher.receive_revenue(asset_id, erc20, 1000_u256);
    stop_cheat_caller_address(contract_address);

    // Try to distribute as former owner (should panic)
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_revenue(asset_id, erc20, 500_u256);
}

#[test]
fn test_multiple_revenue_tokens_distribution() {
    let (
        contract_address,
        _,
        asset_dispatcher,
        _,
        revenue_dispatcher,
        _,
        erc20_dispatcher,
        owner_address,
    ) =
        setup();
    let (asset_id, creators, _, _) = register_test_asset(
        contract_address, asset_dispatcher, owner_address,
    );
    let creator1 = *creators[0];
    let erc20_1 = erc20_dispatcher.contract_address;
    let erc20_2 = deploy_mock_erc20("SecondToken", "ST2", 1000000_u256, SPENDER());
    let erc20_2_dispatcher = IERC20Dispatcher { contract_address: erc20_2 };

    // Setup approvals for second token
    start_cheat_caller_address(erc20_2, SPENDER());
    erc20_2_dispatcher.approve(contract_address, Bounded::<u256>::MAX);
    stop_cheat_caller_address(erc20_2);

    // Receive revenue in both tokens
    start_cheat_caller_address(contract_address, SPENDER());
    revenue_dispatcher.receive_revenue(asset_id, erc20_1, 1000_u256);
    revenue_dispatcher.receive_revenue(asset_id, erc20_2, 2000_u256);
    stop_cheat_caller_address(contract_address);

    // Distribute both tokens
    start_cheat_caller_address(contract_address, creator1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20_1);
    revenue_dispatcher.distribute_all_revenue(asset_id, erc20_2);
    stop_cheat_caller_address(contract_address);

    // Check distributions are independent
    let creator1_pending_token1 = revenue_dispatcher
        .get_pending_revenue(asset_id, creator1, erc20_1);
    let creator1_pending_token2 = revenue_dispatcher
        .get_pending_revenue(asset_id, creator1, erc20_2);

    assert!(creator1_pending_token1 == 500, "Creator1 should get 50% of token1");
    assert!(creator1_pending_token2 == 1000, "Creator1 should get 50% of token2");
}
