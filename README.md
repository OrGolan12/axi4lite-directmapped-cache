# AXI4-Lite Direct-Mapped Cache

## Description
SystemVerilog design of a parameterizable direct-mapped CPU cache with full AXI4-Lite read/write channel support, tag and valid-bit management, automatic hit/miss handling, and a verification testbench to measure AMAT improvements.

## Overview
This project implements a **Direct-Mapped Cache** that connects a CPU to memory through the **AXI4-Lite** protocol. It reduces memory access latency by storing frequently used data in a fast, small memory structure. The design is modular, synthesizable, and comes with a testbench for functional verification.

## Block Diagram
<img width="895" height="665" alt="image" src="https://github.com/user-attachments/assets/a3348a31-0975-47ff-bb26-afb631e539a7" />


## Features
- Fully parameterizable cache size and block size.
- AXI4-Lite compliant read and write channels.
- Tag array with valid-bit checking.
- Automatic hit/miss detection and data retrieval.
- Ready-to-run testbench for simulation.
- AMAT performance measurement.

## Inputs & Outputs
### CPU Side
| Name         | Bits | Dir | Description                 |
|--------------|------|-----|-----------------------------|
| cpu_ar_addr  | 32   | In  | Read address from CPU        |
| cpu_ar_valid | 1    | In  | Valid read address signal    |
| cpu_ar_ready | 1    | Out | Cache ready for read address |
| cpu_r_data   | 32   | Out | Data back to CPU             |
| cpu_r_resp   | 2    | Out | Read response                |
| cpu_r_valid  | 1    | Out | Data valid signal            |
| cpu_r_ready  | 1    | In  | CPU ready to accept data     |

### Memory Side
| Name         | Bits | Dir | Description                          |
|--------------|------|-----|--------------------------------------|
| axi_araddr   | 32   | Out | Read address to memory               |
| axi_arvalid  | 1    | Out | Valid read address signal            |
| axi_arready  | 1    | In  | Memory ready signal                  |
| axi_rdata    | 32   | In  | Data from memory                     |
| axi_rresp    | 2    | In  | Read response from memory            |
| axi_rvalid   | 1    | In  | Data valid signal from memory        |
| axi_rready   | 1    | Out | Cache ready to accept memory data    |
