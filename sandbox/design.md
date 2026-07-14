# Trading Simulation Account Management System — Detailed Design

## 1. Goal

Build a simple account management system for a trading simulation platform that supports:

- Creating an account
- Depositing funds
- Withdrawing funds
- Recording stock buys and sells
- Calculating portfolio value
- Calculating profit/loss from initial deposit
- Reporting holdings at any point in time
- Reporting profit/loss at any point in time
- Listing all transactions over time
- Preventing invalid withdrawals, overspending on buys, and selling shares not owned

The system has access to:

```python
get_share_price(symbol)
```

which returns the current price for a symbol. A fixed-price test implementation exists for:

- `AAPL`
- `TSLA`
- `GOOGL`

All files live in the same directory; no packages/subdirectories.

---

## 2. Overall Architecture

Use a small, clean separation between:

1. **Backend domain/model logic**
2. **Frontend Gradio app**
3. **Backend unit tests**

The backend should be deterministic and testable without UI.

### Recommended files

- `backend.py` — core account/portfolio logic
- `app.py` — Gradio UI
- `test_backend.py` — unit tests
- `share_price_provider.py` — shared share-price function interface and test stub if needed
- `main.py` — optional entrypoint wrapper for Gradio launch

If the fixed `get_share_price(symbol)` implementation already exists in the sandbox, then use it directly. If not, define a local fallback in `share_price_provider.py` or `backend.py` with a clear interface so tests can stub it.

---

## 3. Core Domain Model

### 3.1 Entities

#### `Transaction`
Represents a user action over time.

Transaction types:

- `DEPOSIT`
- `WITHDRAW`
- `BUY`
- `SELL`

Fields:

- timestamp
- type
- symbol (optional, only for buy/sell)
- quantity (optional, only for buy/sell)
- amount (for deposit/withdraw; can also be derived for buy/sell as `price * quantity`)
- share_price at time of trade
- total_cash_change
- note / reason for failures if needed

---

#### `Holding`
Represents shares owned for one symbol.

Fields:

- symbol
- quantity

---

#### `Account`
Represents one user’s trading account.

Fields:

- account_id
- owner_name
- initial_deposit
- cash_balance
- holdings
- transactions

Derived values:

- portfolio value = cash balance + market value of holdings
- profit/loss = portfolio value - initial deposit

---

## 4. Backend Design

## 4.1 Backend responsibilities

The backend must:

- enforce all business rules
- maintain state of cash and holdings
- record transactions
- compute portfolio and P/L
- expose a simple API for the frontend and tests

---

## 4.2 Backend module: `backend.py`

### 4.2.1 Exceptions

Define specific exceptions for invalid operations so frontend/tests can distinguish failure causes.

#### `class AccountError(Exception)`
Base exception for account-related failures.

#### `class InsufficientFundsError(AccountError)`
Raised when:

- withdrawing would make balance negative
- buying exceeds available cash

#### `class InsufficientSharesError(AccountError)`
Raised when selling more shares than owned

#### `class InvalidSymbolError(AccountError)`
Raised when share price is unavailable or symbol is unsupported

#### `class InvalidQuantityError(AccountError)`
Raised when quantity is zero/negative or otherwise invalid

#### `class InvalidAmountError(AccountError)`
Raised when deposit/withdraw amount is invalid

---

### 4.2.2 Data structures

Use dataclasses if desired; keep state in memory.

#### `class TransactionRecord`
Suggested fields:

- `timestamp: datetime`
- `transaction_type: str`
- `symbol: str | None`
- `quantity: int | None`
- `unit_price: float | None`
- `cash_delta: float`
- `resulting_cash_balance: float`
- `resulting_holdings_snapshot: dict[str, int]`
- `description: str | None`

---

### 4.2.3 Main service class

#### `class TradingAccount`
Primary domain class.

##### Constructor

```python
def __init__(self, account_id: str, owner_name: str) -> None
```

Initial state:

- `initial_deposit = 0.0`
- `cash_balance = 0.0`
- empty holdings
- empty transaction list

---

### 4.2.4 Core methods

#### Account lifecycle

```python
def deposit(self, amount: float) -> TransactionRecord
```

Rules:

- amount must be positive
- cash balance increases by amount
- initial_deposit increases only on the first deposit?  
  **Recommended:** define `initial_deposit` as the total contributed cash from deposits, not only first deposit. This makes profit/loss based on total capital contributed.
- record transaction

```python
def withdraw(self, amount: float) -> TransactionRecord
```

Rules:

- amount must be positive
- cannot reduce cash balance below zero
- record transaction

---

#### Trading methods

```python
def buy_shares(self, symbol: str, quantity: int) -> TransactionRecord
```

Rules:

- quantity must be positive
- obtain current share price via `get_share_price(symbol)`
- total cost = price * quantity
- must have enough cash balance
- deduct cash
- increase holdings
- record transaction

```python
def sell_shares(self, symbol: str, quantity: int) -> TransactionRecord
```

Rules:

- quantity must be positive
- must own at least that many shares
- obtain current share price via `get_share_price(symbol)`
- total proceeds = price * quantity
- increase cash
- decrease holdings
- remove holding entry if quantity becomes zero
- record transaction

---

### 4.2.5 Reporting methods

#### Current state

```python
def get_cash_balance(self) -> float
```

```python
def get_holdings(self) -> dict[str, int]
```

Return a copy of current holdings.

```python
def list_transactions(self) -> list[TransactionRecord]
```

Return a copy of transaction history.

---

#### Portfolio calculations

```python
def get_portfolio_value(self) -> float
```

Definition:

- cash balance
- plus market value of all holdings using current prices from `get_share_price(symbol)`

```python
def get_profit_loss(self) -> float
```

Definition:

- `get_portfolio_value() - initial_deposit`

If the product requirement later interprets “initial deposit” as the first deposit only, this can be adjusted, but for a trading simulation platform, cumulative contributed capital is usually clearer. The backend should document this explicitly.

---

#### Historical/state reporting

The requirement says the system must report holdings and P/L “at any point in time.”

Recommended approach:

- store every transaction with a timestamp and resulting snapshot
- provide time-based query methods over transaction history

```python
def get_holdings_at(self, as_of: datetime) -> dict[str, int]
```

```python
def get_profit_loss_at(self, as_of: datetime) -> float
```

```python
def get_portfolio_value_at(self, as_of: datetime) -> float
```

Behavior:

- reconstruct state by replaying transactions up to `as_of`
- use the latest known share prices at query time for valuation unless a transaction snapshot stores valuation; for “at any point in time,” the state should be historical, but valuation is current-market-value unless a historical price service exists
- if no historical market price data exists, document that `get_portfolio_value_at` and `get_profit_loss_at` are based on current prices applied to historical holdings state

If you want simpler implementation, you may instead support:
- `get_holdings_at(as_of)` by replaying transactions
- `get_profit_loss_at(as_of)` as a computed value from reconstructed holdings and current prices

---

### 4.2.6 Internal helper methods

```python
def _get_share_price(self, symbol: str) -> float
```

Wrapper around the shared function. Useful for testing/mocking.

```python
def _validate_positive_amount(self, amount: float) -> None
```

```python
def _validate_positive_quantity(self, quantity: int) -> None
```

```python
def _apply_transaction(self, record: TransactionRecord) -> None
```

Internal state mutation and transaction append.

```python
def _snapshot_holdings(self) -> dict[str, int]
```

Return a deep copy of holdings for transaction records.

```python
def _reconstruct_state_as_of(self, as_of: datetime) -> tuple[float, dict[str, int]]
```

Rebuild cash and holdings from transaction history.

---

## 5. Share Price Provider

### 5.1 File: `share_price_provider.py`

If the environment already supplies `get_share_price(symbol)`, backend should import it from there.

If not, create a small provider module with the interface below.

```python
def get_share_price(symbol: str) -> float
```

Behavior:

- returns current fixed price for supported symbols
- raises `InvalidSymbolError` for unsupported symbols

Suggested fixed test values:

- `AAPL` → configurable fixed price
- `TSLA` → configurable fixed price
- `GOOGL` → configurable fixed price

The test engineer should be able to monkeypatch this function or substitute a fixed stub.

---

## 6. Frontend Design

## 6.1 Frontend responsibilities

The Gradio app should allow a user to:

- create account
- deposit
- withdraw
- buy shares
- sell shares
- view current holdings
- view current portfolio value
- view P/L
- list transactions

The frontend should call backend methods only.

---

## 6.2 File: `app.py`

### Main app entry

```python
def build_app() -> gr.Blocks
```

This function creates and returns the Gradio interface.

```python
def launch_app() -> None
```

Optional convenience wrapper to launch the app.

---

## 6.3 UI state handling

Use `gr.State` to persist the active `TradingAccount` object across interactions.

State object:

- `account_state = gr.State(value=None)`

The app should prevent operations until an account is created.

---

## 6.4 Suggested UI layout

### Tab 1: Account Setup

Components:

- owner name input
- account id input
- create account button
- status/output textbox or markdown
- current account summary area

### Tab 2: Cash Management

Components:

- deposit amount input
- withdraw amount input
- buttons for deposit/withdraw
- output area for updated balance/status

### Tab 3: Trading

Components:

- symbol input
- quantity input
- buy button
- sell button
- output area for trade result

### Tab 4: Reports

Components:

- holdings display
- portfolio value display
- profit/loss display
- transaction list display
- refresh button

### Optional Tab 5: Historical Query

Components:

- datetime input or text input parseable to datetime
- holdings at time
- P/L at time
- portfolio value at time

If datetime UI is too cumbersome, use a text input and parse via backend helper.

---

## 6.5 Frontend callback functions

These should be thin wrappers around backend methods.

```python
def ui_create_account(account_id: str, owner_name: str) -> tuple[str, TradingAccount]
```

```python
def ui_deposit(account: TradingAccount | None, amount: float) -> tuple[str, TradingAccount | None]
```

```python
def ui_withdraw(account: TradingAccount | None, amount: float) -> tuple[str, TradingAccount | None]
```

```python
def ui_buy(account: TradingAccount | None, symbol: str, quantity: int) -> tuple[str, TradingAccount | None]
```

```python
def ui_sell(account: TradingAccount | None, symbol: str, quantity: int) -> tuple[str, TradingAccount | None]
```

```python
def ui_refresh_summary(account: TradingAccount | None) -> tuple[str, str, str, str]
```

Suggested return values:

- status message
- holdings text
- portfolio value text
- profit/loss text
- transaction list text

```python
def ui_get_holdings_at(account: TradingAccount | None, as_of_text: str) -> str
```

```python
def ui_get_profit_loss_at(account: TradingAccount | None, as_of_text: str) -> str
```

```python
def ui_get_portfolio_value_at(account: TradingAccount | None, as_of_text: str) -> str
```

---

## 6.6 Gradio 6 API guidance for frontend engineer

Use current Gradio 6 style. Key guidance:

### Preferred app structure
- Use `gr.Blocks()` as the root container.
- Use `with gr.Blocks() as demo:` rather than older interface styles for multi-section apps.
- Use `gr.Tab(...)` for sections if you want clean organization.
- Use `gr.State` for holding Python objects like the account.

### Common component patterns
- `gr.Textbox(label=..., value=..., placeholder=...)`
- `gr.Number(label=..., precision=2)` for money inputs
- `gr.Button(value="...")`
- `gr.Markdown(...)` for read-only formatted outputs
- `gr.Dataframe(...)` only if you choose to render transactions in table form; otherwise use Markdown/Textbox for simplicity

### Event binding
Use the standard event chaining:

```python
button.click(fn=..., inputs=[...], outputs=[...])
```

This is still the safest pattern in Gradio 6.

### Updates
Prefer returning plain values for outputs when possible. Avoid older `.update()` patterns unless necessary.

### State handling
- `gr.State(None)` or `gr.State(value=None)` is appropriate.
- Callback functions should accept the current state as the first/last input as needed and return the updated state.

### Avoid
- depending on old `gr.inputs` / `gr.outputs` style patterns
- assuming deprecated keyword names from older versions
- using subdirectories or imports that require packaging

### If using Dataframe
If displaying transactions as a table, keep it simple:
- build a list of rows in the backend or frontend
- pass it to `gr.Dataframe(value=...)`

If uncertain, use `gr.Markdown` and format a bullet list/table in plain text.

---

## 7. Backend Function Signatures Summary

Below is the backend API that should exist.

### Exceptions

```python
class AccountError(Exception): ...
class InsufficientFundsError(AccountError): ...
class InsufficientSharesError(AccountError): ...
class InvalidSymbolError(AccountError): ...
class InvalidQuantityError(AccountError): ...
class InvalidAmountError(AccountError): ...
```

### Data record

```python
@dataclass
class TransactionRecord:
    timestamp: datetime
    transaction_type: str
    symbol: str | None
    quantity: int | None
    unit_price: float | None
    cash_delta: float
    resulting_cash_balance: float
    resulting_holdings_snapshot: dict[str, int]
    description: str | None = None
```

### Main class

```python
class TradingAccount:
    def __init__(self, account_id: str, owner_name: str) -> None: ...
    def deposit(self, amount: float) -> TransactionRecord: ...
    def withdraw(self, amount: float) -> TransactionRecord: ...
    def buy_shares(self, symbol: str, quantity: int) -> TransactionRecord: ...
    def sell_shares(self, symbol: str, quantity: int) -> TransactionRecord: ...
    def get_cash_balance(self) -> float: ...
    def get_holdings(self) -> dict[str, int]: ...
    def list_transactions(self) -> list[TransactionRecord]: ...
    def get_portfolio_value(self) -> float: ...
    def get_profit_loss(self) -> float: ...
    def get_holdings_at(self, as_of: datetime) -> dict[str, int]: ...
    def get_portfolio_value_at(self, as_of: datetime) -> float: ...
    def get_profit_loss_at(self, as_of: datetime) -> float: ...
```

### Helpers

```python
def get_share_price(symbol: str) -> float: ...
```

```python
def build_app() -> gr.Blocks: ...
def launch_app() -> None: ...
```

---

## 8. Business Rules

The backend must enforce:

### Deposits
- amount > 0
- updates cash balance
- records transaction

### Withdrawals
- amount > 0
- cannot cause negative cash balance
- records transaction

### Buys
- quantity > 0
- symbol must be valid
- price lookup must succeed
- total cost <= cash balance
- cash decreases
- holdings increase
- records transaction

### Sells
- quantity > 0
- symbol must be valid in current holdings
- quantity sold <= quantity owned
- cash increases
- holdings decrease
- records transaction

### Holdings
- store only positive quantities
- remove symbol when quantity reaches zero

### Reporting
- holdings should be available for current time and historical time
- P/L should use market value of holdings + cash - total deposited capital

---

## 9. Suggested Implementation Notes for Backend Engineer

### 9.1 State representation
Use:

- `self._cash_balance: float`
- `self._initial_deposit: float`
- `self._holdings: dict[str, int]`
- `self._transactions: list[TransactionRecord]`

### 9.2 Historical reconstruction
Since no database exists, historical methods should reconstruct state by replaying transaction history up to `as_of`.

### 9.3 Precision
Money should be handled carefully:
- use floats if simplicity is prioritized
- round user-facing outputs to 2 decimals
- avoid negative zero formatting

### 9.4 Symbol validation
If `get_share_price(symbol)` fails, wrap as `InvalidSymbolError`.

---

## 10. Test Plan

## 10.1 File: `test_backend.py`

The test engineer should write unit tests for backend behavior only.

### Required test categories

#### Account creation
- creates empty account
- initial balances zero
- no holdings, no transactions

#### Deposit
- valid deposit updates balance and records transaction
- invalid zero/negative deposit raises error

#### Withdraw
- valid withdrawal reduces balance
- withdrawal exceeding balance raises `InsufficientFundsError`
- invalid zero/negative withdrawal raises error

#### Buy shares
- valid buy reduces cash and increases holdings
- buy with insufficient funds raises `InsufficientFundsError`
- invalid quantity raises `InvalidQuantityError`
- invalid symbol raises `InvalidSymbolError`

#### Sell shares
- valid sell increases cash and decreases holdings
- selling more than owned raises `InsufficientSharesError`
- invalid quantity raises `InvalidQuantityError`
- invalid symbol handling as appropriate

#### Reporting
- holdings return expected data
- portfolio value computed correctly
- profit/loss computed correctly
- transaction list includes correct records

#### Historical queries
- holdings at time before a trade are correct
- holdings at time after a trade are correct
- historical profit/loss methods return expected values

---

## 10.2 Testing strategy

### Stub share prices
The test engineer should monkeypatch `get_share_price` or replace it with a deterministic stub.

Suggested deterministic mapping:

- `AAPL = 100.0`
- `TSLA = 200.0`
- `GOOGL = 300.0`

### Focus on business rules
Tests should verify that invalid operations are rejected before state changes.

### Suggested helper fixtures
- fresh account per test
- fixed price provider
- account with some deposits and trades for historical queries

---

## 11. Engineer Assignments

## 11.1 backend_engineer

### Scope
Implement the domain logic in `backend.py` and any small supporting module for price lookup if needed.

### Deliverables
- `TradingAccount`
- transaction record model
- custom exceptions
- historical reconstruction helpers
- share price integration wrapper

### Key responsibilities
- enforce business rules
- maintain accurate balances/holdings/transactions
- support current and time-based reporting
- expose clean methods for frontend and tests

---

## 11.2 frontend_engineer

### Scope
Implement the Gradio UI in `app.py`.

### Deliverables
- `build_app()`
- `launch_app()`
- callback functions for deposit/withdraw/buy/sell/reporting
- clear, simple interface with state persistence

### Key responsibilities
- use Gradio 6 `Blocks`
- use `gr.State` for account persistence
- connect buttons to backend methods
- present readable outputs and errors to users
- do not implement business logic in the UI

### Gradio 6 reminders
- Prefer `gr.Blocks`
- Use `button.click(fn=..., inputs=..., outputs=...)`
- Return plain values when possible
- Keep the UI simple and robust

---

## 11.3 test_engineer

### Scope
Write backend unit tests in `test_backend.py`.

### Deliverables
- tests for all business rules
- tests for transaction recording
- tests for portfolio/value/P&L calculations
- tests for historical queries

### Key responsibilities
- ensure deterministic share prices in tests
- verify errors are raised correctly
- ensure state does not change on invalid actions

---

## 12. Recommended File Responsibilities

### `backend.py`
Contains:
- exceptions
- `TransactionRecord`
- `TradingAccount`
- import/use of `get_share_price`

### `app.py`
Contains:
- Gradio UI
- state management
- callback functions
- app builder

### `test_backend.py`
Contains:
- unit tests for backend methods
- price stubbing/mocking

### `share_price_provider.py` or environment-provided module
Contains:
- `get_share_price(symbol)`

### `main.py` optional
Contains:
- app launch entrypoint

---

## 13. Acceptance Criteria

The system is complete when:

- A user can create an account in the Gradio UI
- A user can deposit and withdraw cash
- A user can buy/sell supported shares
- Invalid operations are blocked with clear errors
- Current holdings can be displayed
- Portfolio value can be displayed
- Profit/loss can be displayed
- Transaction history can be listed
- Historical holdings and P/L queries work
- Backend unit tests pass with deterministic share prices

---

## 14. Suggested Minimum API Contract for the Backend Engineer

To keep frontend and tests straightforward, the backend should guarantee:

- all methods raise domain-specific exceptions on invalid operations
- all reporting methods return plain Python types
- transaction records contain enough data for frontend display and historical reconstruction
- holdings are returned as a copy, not a live reference
- money values are returned as floats and formatted to 2 decimals in the frontend

---

## 15. Final Implementation Notes

- Keep the backend pure and testable
- Keep the frontend thin and presentation-only
- Keep tests deterministic by stubbing share prices
- Since there is no directory structure, use clear filenames and simple imports
- If the historical time query is constrained by lack of historical market prices, document that holdings are historical while valuation uses current prices

This design is intentionally minimal, clean, and fully implementable within a single sandbox directory using only standard library + Gradio.