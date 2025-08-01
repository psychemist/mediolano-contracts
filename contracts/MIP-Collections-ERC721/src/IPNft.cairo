#[starknet::contract]
pub mod IPNft {
    use starknet::storage::StorageMapWriteAccess;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::token::erc721::ERC721Component::InternalTrait;
    use openzeppelin::token::erc721::extensions::ERC721EnumerableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::{
        ClassHash, ContractAddress,
        storage::{Map, StorageMapReadAccess, StoragePointerReadAccess, StoragePointerWriteAccess},
    };
    use openzeppelin::token::erc721::interface::IERC721Metadata;

    use crate::interfaces::IIPNFT::IIPNft;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent,
    );
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnly = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721MetadataCamelOnly =
        ERC721Component::ERC721MetadataCamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    impl AccessControlMixinImpl = AccessControlComponent::AccessControlMixinImpl<ContractState>;

    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        collection_manager: ContractAddress,
        collection_id: u256,
        uris: Map<u256, ByteArray>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        owner: ContractAddress,
        collection_id: u256,
        collection_manager: ContractAddress,
    ) {
        self.erc721.initializer(name, symbol, base_uri);
        self.ownable.initializer(owner);
        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, collection_manager);

        self.erc721_enumerable.initializer();
        self.collection_id.write(collection_id);
        self.collection_manager.write(collection_manager);
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.erc721_enumerable.before_update(to, token_id);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl ERC721Metadata of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            self.uris.read(token_id)
        }
    }

    #[abi(embed_v0)]
    impl IPNftImpl of IIPNft<ContractState> {
        /// Mints a new ERC721 token to the specified recipient.
        /// Only callable by accounts with the DEFAULT_ADMIN_ROLE.
        ///
        /// # Arguments
        /// * `recipient` - The address to receive the minted token.
        /// * `token_id` - The unique identifier for the token to be minted.
        /// * `token_uri` - The URI metadata associated with the token.
        fn mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            token_uri: ByteArray,
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.erc721.mint(recipient, token_id);
            self.uris.write(token_id, token_uri);
        }

        /// Burns (removes) an ERC721 token.
        ///
        /// # Arguments
        /// * `token_id` - The unique identifier for the token to be burned.
        fn burn(ref self: ContractState, token_id: u256) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.erc721.burn(token_id);
        }

        /// Transfers an ERC721 token from one address to another.
        ///
        /// # Arguments
        /// * `from` - The address sending the token.
        /// * `to` - The address receiving the token.
        /// * `token_id` - The unique identifier for the token to be transferred.
        fn transfer(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256,
        ) {
            self.erc721.transfer_from(from, to, token_id);
        }

        /// Returns the collection ID associated with this contract.
        ///
        /// # Returns
        /// * `u256` - The collection ID.
        fn get_collection_id(self: @ContractState) -> u256 {
            self.collection_id.read()
        }

        /// Returns the address of the collection manager.
        ///
        /// # Returns
        /// * `ContractAddress` - The address of the collection manager.
        fn get_collection_manager(self: @ContractState) -> ContractAddress {
            self.collection_manager.read()
        }

        /// Retrieves all token IDs owned by a specific user.
        ///
        /// # Arguments
        /// * `user` - The address of the token owner.
        ///
        /// # Returns
        /// * `Span<u256>` - A span containing all token IDs owned by the user.
        fn get_all_user_tokens(self: @ContractState, user: ContractAddress) -> Span<u256> {
            self.erc721_enumerable.all_tokens_of_owner(user)
        }

        /// Returns the total supply of tokens in the collection.
        ///
        /// # Returns
        /// * `u256` - The total number of tokens.
        fn get_total_supply(self: @ContractState) -> u256 {
            self.erc721_enumerable.total_supply()
        }

        /// Returns the URI for a specific token.
        ///
        /// # Arguments
        /// * `token_id` - The unique identifier for the token.
        ///
        /// # Returns
        /// * `ByteArray` - The URI of the token.
        fn get_token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.token_uri(token_id)
        }

        /// Returns the owner address of a specific token.
        ///
        /// # Arguments
        /// * `token_id` - The unique identifier for the token.
        ///
        /// # Returns
        /// * `ContractAddress` - The address of the token owner.
        fn get_token_owner(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721.owner_of(token_id)
        }

        /// Checks if a given address is approved for a specific token.
        ///
        /// # Arguments
        /// * `token_id` - The unique identifier for the token.
        /// * `spender` - The address to check for approval.
        ///
        /// # Returns
        /// * `bool` - True if `spender` is approved for `token_id`, false otherwise.
        fn is_approved_for_token(
            self: @ContractState, token_id: u256, spender: ContractAddress,
        ) -> bool {
            let approved = self.erc721.get_approved(token_id);
            approved == spender
        }
    }
}

