
# Asynchronous width-converting Async FIFO — EDA Playground

## Specification
- Write width: 12 bits
- Read width: 4 bits
- Depth: 16 complete 12-bit words
- Capacity: 192 stored bits = 48 output nibbles
- Independent write/read clocks (10 ns and 14 ns periods)
- Gray-coded word pointers and two-flop CDC synchronizers
- Read order is MSB-first: 12'hABC -> 4'hA, 4'hB, 4'hC

## EDA Playground setup
1. Select **SystemVerilog** as the language.
2. Select **Questa** (or another simulator with UVM 1.2 support).
3. Enable the simulator's **UVM 1.2** library option.
4. Add the files in this compile order:
   - `async_fifo.sv`
   - `fifo_if.sv`
   - `fifo_uvm_pkg.sv`
   - `tb_top.sv`
5. Set top-level entity to `tb_top`.
6. Run.



## Verification included
- Directed fill of all 16 words.
- Directed read of 48 nibbles.
- Concurrent randomized write/read activity.
- Scoreboard compares every accepted read against the three nibbles from each accepted write.
- Reads while empty and writes while full are naturally blocked by DUT flags.
- UVM reporting identifies data mismatches and leftover expected data.

## Important design interpretation
Depth=16 means 16 entries of 12 bits each, not 16 entries of 4 bits.
The DUT advances its read word pointer only after the third 4-bit chunk has been consumed.
