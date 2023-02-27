// SPDX-License-Identifier: MIT License
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "operator-filter-registry/src/DefaultOperatorFilterer.sol";

error Nonexistent();
error InvalidAmount();
error InvalidTime();
error InvalidPayment();

/**
 * @dev struct representing the configurations of a ERC1155 token
 * @param startMintTime when the token minting is enabled
 * @param endMintTime when the token minting is disabled
 * @param name name of the token
 * @param price price of the token; using BFF Coin as underlying
 * @param totalSupply total supply of the token
 * @param maxSupply maximum supply of the token
 * @param publicSupply supply that is mintable by the user
 * @param maxPerAddress maximum amount of token an address is able to mint
 */
struct TokenInfo {
    uint256 startMintTime;
    uint256 endMintTime;
    string name;
    uint256 price;
    uint256 totalSupply;
    uint256 maxSupply;
    uint256 publicSupply;
    uint256 maxPerAddress;
}

/**
 * @title   BFFMarketplace
 * @author  @ryanycw.eth
 * @dev     This contract serves as the ERC1155 marketplace inside the Galaxy Frens ecosystem
 */
contract BFFMarketplace is Ownable, ERC1155, ERC2981, DefaultOperatorFilterer {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                         State Variables V1
    //////////////////////////////////////////////////////////////*/

    /// @dev contract name
    string public constant name = "BFFMarketplace";
    /// @dev contract symbol
    string public constant symbol = "BFFM";

    /// @dev base uri of all the erc1155 tokens
    string public baseURI;

    /// @dev address of BFF Coin, the underlying erc20 used to mint items
    address public bffCoin;

    /// @dev last id used to represent the latest item
    uint256 public lastTokenId;

    /// @dev tokenId => token metadata
    mapping(uint256 => TokenInfo) public tokenMetadata;

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/
    constructor(string memory _baseURI, address _bffCoin) ERC1155("") {
        baseURI = _baseURI;
        bffCoin = _bffCoin;
    }

    /*///////////////////////////////////////////////////////////////
                        External Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev mint erc1155 token item with BFF Coin
     * @param _tokenId token id of the item
     * @param _quantity quantity of the item that user wants to mint
     * @param _bffQuantity quantity of the BFF Coin that user use to mint
     */
    function mintItem(
        uint256 _tokenId,
        uint256 _quantity,
        uint256 _bffQuantity
    ) external {
        TokenInfo memory token = tokenMetadata[_tokenId];

        /// BFF Coin quantity must be equal to the item price times quantity
        if (token.price * _quantity != _bffQuantity) {
            revert InvalidPayment();
        }

        IERC20(bffCoin).safeTransferFrom(
            msg.sender,
            address(this),
            _bffQuantity
        );

        /// can only mint between startMintTime and endMintTime
        if (
            block.timestamp < token.startMintTime ||
            block.timestamp > token.endMintTime
        ) {
            revert InvalidTime();
        }

        tokenMetadata[_tokenId].totalSupply += _quantity;

        /// can only mint less than publicSupply in mintItem function
        if (token.totalSupply + _quantity > token.publicSupply) {
            revert InvalidAmount();
        }

        /// can only mint less than maxPerAddress in one tx
        if (_quantity > token.maxPerAddress) {
            revert InvalidAmount();
        }

        _mint(msg.sender, _tokenId, _quantity, "");
    }

    /**
     * @dev returns the token uri according to _tokenId
     * @param _tokenId token id of corresponding token
     */
    function uri(
        uint256 _tokenId
    ) public view override returns (string memory) {
        /// every token has its name
        if (bytes(tokenMetadata[_tokenId].name).length == 0) {
            revert Nonexistent();
        }

        return string(abi.encodePacked(baseURI, Strings.toString(_tokenId)));
    }

    /**
     * @dev returns the current total supply according to _tokenId
     * @param _tokenId token id of corresponding token
     */
    function totalSupply(uint256 _tokenId) public view returns (uint256) {
        return tokenMetadata[_tokenId].totalSupply;
    }

    /*///////////////////////////////////////////////////////////////
                        Admin Operation Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev launch a new item in the marketplace
     *      See {struct TokenInfo} for more informations.
     */
    function launchItem(
        uint256 _startMintTime,
        uint256 _endMintTime,
        string memory _name,
        uint256 _price,
        uint256 _initialSupply,
        uint256 _publicSupply,
        uint256 _maxPerAddress
    ) external onlyOwner {
        tokenMetadata[lastTokenId] = TokenInfo(
            _startMintTime,
            _endMintTime,
            _name,
            _price,
            0,
            _initialSupply,
            _publicSupply,
            _maxPerAddress
        );
        lastTokenId++;
    }

    /**
     * @dev update an existing item in the marketplace
     *      See {struct TokenInfo} for more informations.
     */
    function updateItem(
        uint256 _tokenId,
        uint256 _startMintTime,
        uint256 _endMintTime,
        string memory _name,
        uint256 _price,
        uint256 _initialSupply,
        uint256 _publicSupply,
        uint256 _maxPerAddress
    ) external onlyOwner {
        uint256 _totalSupply = tokenMetadata[_tokenId].totalSupply;
        tokenMetadata[_tokenId] = TokenInfo(
            _startMintTime,
            _endMintTime,
            _name,
            _price,
            _totalSupply,
            _initialSupply,
            _publicSupply,
            _maxPerAddress
        );
    }

    /**
     * @dev owner giveaway item
     * @param _tokenId token id of the item
     * @param _to address to transfer the item
     * @param _quantity quantity of the item
     */
    function ownerMint(
        uint256 _tokenId,
        address _to,
        uint256 _quantity
    ) external onlyOwner {
        TokenInfo memory token = tokenMetadata[_tokenId];

        /// every token has its name
        if (bytes(token.name).length == 0) {
            revert Nonexistent();
        }

        tokenMetadata[_tokenId].totalSupply += _quantity;

        /// can only mint less than maximum supply
        if (token.totalSupply + _quantity > token.maxSupply) {
            revert InvalidAmount();
        }

        /// can only mint before or after the public mint
        if (
            block.timestamp >= token.startMintTime &&
            block.timestamp <= token.endMintTime
        ) {
            revert InvalidTime();
        }

        _mint(_to, _tokenId, _quantity, "");
    }

    /**
     * @dev withdraw BFF Coin in the marketplace
     * @param _quantity quantity of the withdrawing BFF Coin
     * @param _vault address to transfer the BFF Coin
     */
    function withdraw(uint256 _quantity, address _vault) external onlyOwner {
        IERC20(bffCoin).safeTransfer(_vault, _quantity);
    }

    /*///////////////////////////////////////////////////////////////
                        Admin Settings Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev set the baseURI of uri()
     * @param _baseURI the new base uri
     */
    function setURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    /**
     * @dev set the address of BFF Coin
     * @param _bffCoin the new address of BFF Coin
     */
    function setBFFCoin(address _bffCoin) external onlyOwner {
        bffCoin = _bffCoin;
    }

    /*///////////////////////////////////////////////////////////////
                Integrate ERC2981 Royalty Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev override same interface function in different inheritance.
     * @param _interfaceId id of an interface to check whether the contract support
     */
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /**
     * @dev Set the royalties information for platforms that support ERC2981, LooksRare & X2Y2
     * @param _receiver Address that should receive royalties
     * @param _feeNumerator Amount of royalties that collection creator wants to receive
     */
    function setDefaultRoyalty(
        address _receiver,
        uint96 _feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(_receiver, _feeNumerator);
    }

    /**
     * @dev Set the royalties information for platforms that support ERC2981, LooksRare & X2Y2
     * @param _receiver Address that should receive royalties
     * @param _feeNumerator Amount of royalties that collection creator wants to receive
     */
    function setTokenRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _feeNumerator
    ) external onlyOwner {
        _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
    }

    /*///////////////////////////////////////////////////////////////
                Override ClosedSea Royalty Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function setApprovalForAll(
        address _operator,
        bool _approved
    ) public override onlyAllowedOperatorApproval(_operator) {
        super.setApprovalForAll(_operator, _approved);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _amount,
        bytes memory _data
    ) public override onlyAllowedOperator(_from) {
        super.safeTransferFrom(_from, _to, _tokenId, _amount, _data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     *      In this example the added modifier ensures that the operator is allowed by the OperatorFilterRegistry.
     */
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) public virtual override onlyAllowedOperator(_from) {
        super.safeBatchTransferFrom(_from, _to, _ids, _amounts, _data);
    }
}
