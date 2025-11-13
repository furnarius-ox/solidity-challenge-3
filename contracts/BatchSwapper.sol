// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;


// Los {} fueron sugeridos por Cursor
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

contract BatchSwapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // estado del batch
    enum Phase { Collecting, Swapped }
    Phase public phase;

    //  Tokens 
    IERC20 public immutable fromToken;
    IERC20 public immutable toToken;

    //Sugerencia de Cursor
    uint8  private immutable decimalsFrom;
    uint8  private immutable decimalsTo;
    //

    // Contabilidad. Struct para tener un solo mapping
    struct Account {
        uint256 fromDeposited; // cuánto A depositó el usuario (fromToken)
        uint256 toClaimed;     // cuánto B ya cobró (toToken)
    }

    mapping(address => Account) public accounts; //Un mapping de structs 
    uint256 public totalFrom;                  
    uint256 public exchangeRate = 1e18;    // lo sugirió cursor             

    // events
    event Provided(address indexed user, uint256 amountFrom);
    event WithdrawnFrom(address indexed user, uint256 amountFrom);
    event Swapped(uint256 totalFrom, uint256 expectedTo, uint256 exchangeRate);
    event WithdrawnTo(address indexed user, uint256 amountTo);
    event PrefundedToToken(address indexed user, uint256 amount);

    // modifiers
    modifier onlyCollecting() {
        require(phase == Phase.Collecting, "No collecting");
        _;
    }

    modifier onlySwapped() {
        require(phase == Phase.Swapped, "No swapping");
        _;
    }

    // constructor
    constructor(address fromToken_, address toToken_) Ownable(msg.sender) { //dirección del contrato de los tokens (DAI y USDC x ej). 
                                                                            // Volver a buscar Ownable
        require(fromToken_ != address(0) && toToken_ != address(0));
        fromToken = IERC20(fromToken_); // convierte la dirección en una referencia a un contrato ERC20,
                                        // para poder usar sus funciones (transfer, transferFrom, etc.).
        toToken   = IERC20(toToken_); // convierte la dirección en una referencia a un contrato ERC20,
          
                                      //para poder usar sus funciones (transfer, transferFrom, etc.).
       //cursor
        decimalsFrom = IERC20Metadata(fromToken_).decimals(); // obtiene el número de decimales del token A
        decimalsTo   = IERC20Metadata(toToken_).decimals(); // obtiene el número de decimales del token B
        //

        phase = Phase.Collecting; // inicializa la fase en Collecting
    }

    //funciones mutativas
    //Es la función para proveer liquidez. El non reentrant es necesario si es onlyOwner?
    function prefundToToken(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0);
        toToken.safeTransferFrom(msg.sender, address(this), amount);
        emit PrefundedToToken(msg.sender, amount);
    }

    // Depósito al batch
    function provide(uint256 amount) external onlyCollecting nonReentrant { //Sale de la llamada a la función provide del contrato  
        require(amount > 0);
        fromToken.safeTransferFrom(msg.sender, address(this), amount); // Safe Transfer viene de SafeERC20 
                                                                       //y transfiere el token A desde la dirección del usuario al contrato
        accounts[msg.sender].fromDeposited += amount; // eL CAMPO DEL struct Account del usuario
        totalFrom += amount; // actualiza el total de tokens A depositados
        emit Provided(msg.sender, amount); // emite el evento Provided con la dirección del usuario y la cantidad de tokens A depositados
    }

    // SWAP
    // El owner debe haber provisto liquidez de toToken antes
    // 1 a 1
    function swap() external onlyOwner onlyCollecting nonReentrant {
        require(totalFrom > 0);
        // A cuanto B equivale lo juntado. Pero es 1 a 1 ajustando por decimales (1:1 humano)
        // De nuevo, esto me lo sugiere cursor, tengo que ver mejor lo de los decimales
        uint256 expectedTo = _scaleFromTo(totalFrom);

        // Este pedacito es para exigir prefondeo suficiente de B en el contrato
        require(toToken.balanceOf(address(this)) >= expectedTo);
        
        // Pasamos a fase de reparto
        phase = Phase.Swapped;
        emit Swapped(totalFrom, expectedTo, exchangeRate);
    }

    // - Si estamos en Collecting: "withdraw(amount)" reembolsa fromToken (A) por ese monto.
    // - Si estamos en Swapped:   "withdraw(ignored)" paga el toToken (B) pendiente completo.
    function withdraw(uint256 amount) external nonReentrant { //Acá juego con el struct Account 
        if (phase == Phase.Collecting) {
            //CASO A: Reembolsar A
            require(amount > 0);
            uint256 balance = accounts[msg.sender].fromDeposited;
            require(balance >= amount, "No tenes dinero suficiente, RIP ");
            // Actualizo el saldo del usuario en el mapping accounts
            accounts[msg.sender].fromDeposited = balance - amount;
            totalFrom -= amount; // Actualizo el total de tokens A depositados

            fromToken.safeTransfer(msg.sender, amount); // Transfiero el token A desde el contrato al usuario
            emit WithdrawnFrom(msg.sender, amount);

        } else if (phase == Phase.Swapped) {
            //CASO B: Pagar B. Acá no podría poner un booleano como true si ya cobró todo?
            uint256 deposited = accounts[msg.sender].fromDeposited;
            require(deposited > 0, "Nada que reclamar");
            require(accounts[msg.sender].toClaimed == 0, "Ya reclamaste todo");
            uint256 grossTo = _scaleFromTo(deposited);
            accounts[msg.sender].toClaimed = grossTo;
            toToken.safeTransfer(msg.sender, grossTo);
            emit WithdrawnTo(msg.sender, grossTo);
        }
    }

  
    // Esto me lo tira cursor.
    //Helper: conversión de unidades (1:1 con decimales)
    // Convierte un monto en A (fromToken) al monto equivalente en B (toToken) a paridad 1:1 humana
    function _scaleFromTo(uint256 amountFrom) internal view returns (uint256) {
        if (decimalsFrom == decimalsTo) return amountFrom;
        if (decimalsFrom < decimalsTo) {
            return amountFrom * (10 ** (decimalsTo - decimalsFrom));
        } else {
            return amountFrom / (10 ** (decimalsFrom - decimalsTo));
        }
    }
}
