# DDR3 controller

A compact DDR3 controller targeting the Xilinx 7-series MIG controller interface.
The design retains the MIG user interface and PHY and processes one request at
a time, in arrival order. Every user access follows ACT → READ/WRITE → PRE.

## Supported configuration

- 4:1 fabric-to-memory clock ratio
- Rank 0, BL8 bursts
- ECC disabled
- No self-refresh

The port list follows the MIG controller interface, but not all MIG parameters
are implemented. Integration with the generated MIG UI/PHY must be verified
for the chosen FPGA and memory configuration before hardware use.

## RTL

| Module | Purpose |
|---|---|
| `ddr3_ctrl` | Top-level wiring and timing constants |
| `ddr3_req` | Request capture and acceptance handshake |
| `ddr3_fsm` | Command sequencing and recovery waits |
| `ddr3_flow` | PHY readiness checks |
| `ddr3_maint` | Refresh, ZQCS, and periodic reads |
| `ddr3_cmd_out` | Registered PHY command outputs |
| `ddr3_rd_tag` | Read response tags |
| `ddr3_wr_data` | Write-data requests and timing |

## Tests

Install Icarus Verilog, then run:

```sh
sh unit/run_all.sh
```

The script runs seven module tests and compiles the controller top level.
These tests do not include a DDR3 device model or generated MIG UI/PHY.
