# mm_sim (C++) - a market-making simulator with a live "trading screen"

A C++17 rebuild of the Python/Numba `mm_sim`. It replays Databento **MBO** (market-by-order) data, rebuilds the
exchange's order book message by message, puts our own simulated quotes in the queue, and shows the whole loop on a
live terminal screen, the way a real market-making desk runs it.

**Honest first line:** this is a *replay of recorded data*, not a live connection to CME, and the P&L is a simulation.
It reproduces the Python version exactly (see "How we know it is correct") - it does not create an edge.

```
FEED -> BOOK -> SIGNALS -> STRATEGY -> GATEWAY -> EXCH QUEUE -> FILLS
```

---------------------------------------------------------------------------------------------------------------------

## 1. Run it (Windows)

You do not need a compiler: `bin\mm_sim.exe` is already built (Windows 10/11, 64-bit, one file, no installer).
It was cross-compiled on Linux with MinGW-w64 and checked under Wine, but not on a real Windows machine, so if
Windows SmartScreen asks, choose "More info -> Run anyway" - or build it yourself from the source (section 2).

Open **Windows Terminal** or PowerShell, make the window big (**132 columns wide, 51 lines tall**; use `--ladder 4`
for 41 lines), and go to this folder.

```
:: 1) try it on the small synthetic sample (2 MB, fake data, 2 days)
bin\mm_sim.exe replay sample_data\sample_fake_nq.mbo.zst --from 14:00

:: 2) your real NQ data (the .dbn / .dbn.zst file, or the folder that holds it)
bin\mm_sim.exe replay "D:\tick data\NQ.c.0_mbo_20250510_20250522" --from 14:30 --speed 10

:: 3) the full backtest report (same text as the Python version) + CSV files
bin\mm_sim.exe "D:\tick data\NQ.c.0_mbo_20250510_20250522" --out results
python tools\plot_results.py results
```

Keys in the live screen: **SPACE** pause | **+ / -** slower / faster | **0** as fast as possible | **1** real time |
**S** next strategy | **F** skip 1 minute | **G** skip 10 minutes | **Q** quit.

If the box lines look like garbage, add `--ascii`. Starting at `--from` first runs through the earlier data at full speed
(a few seconds per day of NQ). Default quoting hours are 13:30-20:00 UTC; outside them the screen says "session closed"
and the strategies do not quote (use `--allday` to quote around the clock).

## 2. Build it yourself

| System | Needs | Command |
|---|---|---|
| Windows | CMake + **MinGW-w64 g++** (easiest: winlibs.com) **or** Visual Studio / Build Tools "Desktop development with C++" | `build.bat` |
| Linux / macOS | cmake, g++ or clang (C++17) | `./build.sh` |

The result is `bin\mm_sim.exe` (and `bin\mm_tests.exe`). Nothing else to install: the zstd decoder is included in
`third_party/` (BSD licence), so `.dbn.zst` files open directly.
The MinGW route is the one I tested. The Visual Studio route (`/O2`, `/fp:precise`) is set up but I could not run it here.
On a different compiler a rare last-digit difference in the results is possible (floating-point maths can differ
slightly); it is not a bug.

---------------------------------------------------------------------------------------------------------------------

## 3. What you see on the screen (and what it is in a real HFT stack)

A colour screenshot is in `docs/live_screen.png`. The same frame as text:

```
 MM-SIM replay   instrument 42005804   2025-05-12 14:03:01.000 UTC                                    RUNNING x1
+- PIPELINE: one market message travels left to right (replay of recorded data) ------------------------------+
| [FEED]----------->[BOOK]----------->[SIGNALS]-------->[STRATEGY]------->[GATEWAY]-------->[EXCH QUEUE]----->[FILLS]
| 3.59 M msg/s      13 orders         OFI z +0.0        A-S               latency 1.0 ms    bid ahead 0       132 fills
| 659 MB/s decoded  bid 20440.00      sigma 0.50        bid 20440.25      in flight 0       ask ahead 0       inventory -2
| file 100% read    ask 20440.75      k 0.76 A 0.3      ask 20441.00      rejects 0         queue model       net +$1,006
| reader thread     128 ns /2.0 us    128 ns /4.1 us    64 ns /512 ns     simulated         simulated
...
| 20441.00                  <- SELL 1 (0 ahead)    <- our ask, alone at a new price
| 20440.75  1      #                               <- the real best ask
| --- inside the spread ---
| 20440.25                  <- BUY 1 (0 ahead)     <- our bid, inside the spread
| 20440.00  9      ########                        <- the real best bid, 9 contracts
...
| 14:02:47.0993 > SEND BUY 20440.25    14:02:47.1003 + ACK BUY 20440.25 q0   14:02:38.4157 * FILL BUY 20440.50 x1
```

| Panel | What it shows | What a real firm has in that place |
|---|---|---|
| **FEED** | messages per second, MB/s decoded, how much of the file is read | A network card (often with kernel bypass or an FPGA) receiving the exchange's **UDP multicast** market data (CME **MDP 3.0**; Databento's `GLBX.MDP3` data is a recording of it), in a data centre next to the exchange (CME Aurora), with hardware timestamps |
| **BOOK** | the live order book (L3: every order is tracked), best bid/ask, orders alive, our quotes with "(N ahead)" | The order-book builder that applies each incremental update. Same idea, same data structure problem |
| **SIGNALS** | order-flow imbalance (OFI) z-score, volatility sigma, A and k (how fast trades arrive at each distance) | Short-term signals recomputed on every update (OFI, micro-price, volatility, queue size) |
| **STRATEGY** | the bid and ask the strategy wants right now (Join / Avellaneda-Stoikov / GLFT, with or without the OFI defence) | The quoting logic; usually the smallest piece of the code |
| **GATEWAY** | our order actions "in flight" for the latency we set (default 1 ms) | The order-entry connection (CME **iLink 3**, binary), plus **pre-trade risk checks** and a **kill switch** before every order |
| **EXCH QUEUE** | how many orders are ahead of ours at our price | The exchange's matching engine: CME index futures match **first-in, first-out** at one price, so queue position is what you trade |
| **FILLS** | fills, inventory, P&L after fees | Execution reports coming back, updating position and risk |
| **OUR ORDERS** | the life of every order: `> SEND` -> `+ ACK` (queue position `q`) -> `* FILL` or `x CANCEL` / `! REJECT` | The order and execution log every desk keeps |
| **OUR CODE: TIME/MSG** | how long our own code takes per message (histogram) | The "tick-to-trade" latency every firm measures; in real systems it is end-to-end, from the wire in to the wire out |

Same habits as a real low-latency system, on a small scale: the hot path (`Engine::on_msg`) **never allocates memory**;
the book is flat arrays (a 1,048,576-tick price grid plus block counters, so finding the best price is fast);
orders live in an open-addressing hash table; reading/decoding the file runs on **its own thread** and hands batches to the
engine thread through a bounded queue (like a feed handler thread and a strategy thread on separate cores).

What is *not* the same, so you do not over-claim: no network, no exchange, no real order acknowledgements; the latency is a
number we choose, and the "time per message" figures are this program's own compute time on this computer.

---------------------------------------------------------------------------------------------------------------------

## 4. Options

Everything can be a command-line option (`--tick 0.01`) or a line in `mm_settings.txt` (`tick = 0.01`; start from
`mm_settings.example.txt`). The command line wins. `--config other.txt` loads another file.

| Option | Default | Meaning |
|---|---|---|
| `--tick` / `--tick-value` | 0.25 / 5 | price step and dollars per tick per unit. NQ: 0.25 / 5. MNQ: 0.25 / 0.5. A stock: 0.01 / 0.01 |
| `--fee` | 2 | dollars per unit per fill |
| `--hours 13.5,20` / `--allday` | 13.5,20 | UTC hours to quote / quote around the clock |
| `--size`, `--qmax` | 1, 5 | units per quote, inventory limit (long or short) |
| `--latency-ms`, `--decision-ms` | 1, 100 | delay to the exchange; how often a strategy may change its quotes |
| `--skew`, `--horizon-s`, `--ofi-z` | 0.5, 10, 2 | A-S/GLFT ticks of shift per unit of inventory; A-S horizon; OFI pull threshold |
| `--no-sweeps` | off | skip the extra re-quote-speed and latency runs (faster) |
| `--max N` | all | quick trial: only the first N records |
| `--out DIR`, `--dump-fills f.csv` | `.` | where `mm_summary.csv`, `mm_daily.csv`, `mm_equity.csv` go; every fill of every strategy (for checks) |
| replay: `--show`, `--from`, `--speed`, `--ladder` | A-S, start, 1, 9 | strategy drawn on the book; start at `14:00` or `2025-05-13 13:25` (UTC); 0 = max speed; book levels per side |
| replay: `--ascii`, `--no-color`, `--plain --frames N --frame-every S` | off | plain frames for old consoles / logs |

The strategies, in the order of the report: Join (sit at the touch), Avellaneda-Stoikov (A-S), GLFT - each alone and
with the OFI defence; then Join/A-S that re-quote every 10 ms and 1 ms; then A-S with 5, 20 and 50 ms latency.

---------------------------------------------------------------------------------------------------------------------

## 5. How we know it is correct

1. **Same answer as the Python version, exactly.** `tools/parity.py` runs one file through both engines and compares every fill
   of every strategy (time, price, size, side) and 14 summary numbers.
   Result: **all 13 strategies, fill logs identical**, on the small file (194k records) and on a 453 MB / 8.1M-record
   file (about 600,000 fills per strategy), with and without trading hours. The Windows build under Wine gives
   byte-identical files except for Windows line endings.
2. **Unit tests** (`bin\mm_tests.exe`, 73-76 checks): queue rules step by step (a trade at our price fills us only after
   the queue ahead is used up; a modify down keeps priority, up loses it; a trade through our price fills us first;
   a post-only order that would cross is rejected; the OFI defence pulls the right side), the hash table against
   `std::unordered_map`, the order book against a slow brute-force rebuild at 104,071 book states (0 mismatches), cash and
   inventory against the fill list, inventory never above the limit, **no look-ahead** (the first 55% of a file gives
   the same fills with or without the rest), and plain DBN = zstd DBN. I also planted two bugs on purpose to make sure the
   tests catch them (they did).
   Run: `bin\mm_tests.exe` (hand-made cases only) or `bin\mm_tests.exe --file sample_data\sample_fake_nq.mbo.zst` (adds the data-file checks).
3. **Speed** on 2 cores, 13 strategies: **2.9 M records/s** (the Numba version: 1.5 M/s). A full NQ file of ~125 M
   records should take roughly a minute or two; real data has deeper books than my fake file, so I have not promised a number.
   Memory: ~380 MB for the 8.1M-record file.

To repeat the parity check you need Python with numpy, pandas, numba and databento
(`pip install -r reference_python/requirements.txt`):

```
python tools\parity.py sample_data\sample_fake_nq.mbo.zst bin\mm_sim.exe
python tools\parity.py sample_data\sample_fake_nq.mbo.zst bin\mm_sim.exe --hours     (also tests the flatten-at-close path)
```
It prints one line per strategy and ends with `PARITY: OK`. To make a bigger synthetic file:
`python reference_python\tests\make_fake_mbo.py big.mbo 0.4 2500000 2`.

---------------------------------------------------------------------------------------------------------------------

## 6. Honest limits - read before putting numbers on a CV

* **The sample file is synthetic.** Strategies earn money on it because I generated it that way (prices keep moving the
  right way after our fills). That is a test file, not a result.
* **On your real NQ data the earlier Python run was negative for every strategy**: after each fill the price tends to move
  against us ("adverse selection"; the markout table in the report shows it). This C++ version reproduces the same
  simulation; I have not run it on your real files myself. Cheaper fees (the report has a fee what-if) or a real signal are
  the open research questions, not a missing line of code.
* The queue model is a standard simulation assumption: we join the back of the queue, and our order never changes the market.
  Real fills depend on how your orders affect others - this cannot be measured on historical data.
* Latency is one fixed number. Real latency varies and spikes.
* Only 1 instrument at a time (the one with the most trades in the first records); other instruments in the file are ignored.

## 7. Files

| Path | What |
|---|---|
| `src/engine.hpp` | the simulator core (book, queue model, strategies, calibration) - port of `mm_engine.py` |
| `src/dbn.hpp`, `third_party/zstd` | DBN reader (plain or zstd) |
| `src/order_map.hpp` | order-id hash table |
| `src/feed.hpp`, `src/backtest.hpp` | reader thread + engine thread, instrument pick, the full run |
| `src/report.hpp` | per-day P&L, markouts, the printed report, CSV files |
| `src/dashboard.cpp` | the live screen |
| `src/settings.hpp`, `src/main.cpp` | options and commands |
| `tests/test_main.cpp` | the unit tests |
| `tools/parity.py`, `tools/plot_results.py` | Python-vs-C++ check; charts from the CSV files |
| `reference_python/` | the Python/Numba version this was ported from |
| `sample_data/` | a small synthetic MBO file to try things on |

## 8. Troubleshooting

* *"Window is NNxNN; this screen needs 132 columns..."* - enlarge the window or use `--ladder 4`.
* *Boxes look broken* - use Windows Terminal, or add `--ascii`.
* *"This needs MBO data"* - the file is another schema (trades, mbp-1, ...). Download **MBO**.
* *"No day has a minute of usable market data inside the trading hours"* - the data does not cover 13:30-20:00 UTC; check
  `--hours` or use `--allday`.
* *Path with spaces* - put it in quotes. The path can be a folder: the largest data file in it is used.
* *Different prices (stocks, MNQ)* - set `--tick` and `--tick-value` (and `--fee`).
