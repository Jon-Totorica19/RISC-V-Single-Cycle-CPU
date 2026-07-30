# RISC-V Single-Cycle CPU

A single-cycle RV32I processor implemented in SystemVerilog. Each instruction completes in one clock cycle. Verified with cocotb testbenches using Verilator as the simulator.

---

## Architecture

### System Hierarchy

`riscv_core` is the CPU datapath and control logic only — it does not contain memory. Instruction and data memory are separate modules, instantiated alongside the core in `riscv_top`, connected via a real bus interface. This split matches how real CPU synthesis works: the core is synthesized as a standalone IP block with its memory interface as the boundary, while memory is handled entirely separately.

```
                              riscv_top

  ┌────────────┐  ┌────────────┐  ┌────────────┐
  │ instr_mem  │  │ riscv_core │  │  data_mem  │
  └────────────┘  └────────────┘  └────────────┘
```

| From | Signal(s) | To |
|------|-----------|-----|
| `riscv_core` | `instr_addr` | `instr_mem` |
| `instr_mem` | `instr` | `riscv_core` |
| `riscv_core` | `data_addr`, `writeData`, `MemRead`, `MemWrite` | `data_mem` |
| `data_mem` | `readData` | `riscv_core` |
| *(external)* | `clk`, `rst` | all three modules |

### Core Datapath

The diagram below shows the logical dataflow through `riscv_core`'s internal datapath: fetch, decode, execute, memory, and writeback all happen within a single clock cycle. **Note:** `instr_mem` and `data_mem` are drawn here for dataflow clarity only — they are not internal to `riscv_core`. They're separate modules connected via the `instr_addr`/`instr` and `data_addr`/`writeData`/`readData` ports shown in the System Hierarchy diagram above.

![Datapath](docs/datapath.svg)

```
         ┌─────┐    ┌──────────┐    ┌──────────────┐
clk ────►│ PC  │───►│ instr_mem│───►│ control_unit │
rst ────►│     │    └──────────┘    └──────┬───────┘
         └──┬──┘         │                 │ RegWrite, ALUSrc,
            │            │ instr           │ MemWrite, MemRead,
            │            ▼                 │ MemToReg, Branch,
            │     ┌─────────────┐          │ Jump, ALUOp
            │     │   imm_gen   │          │
            │     └──────┬──────┘          │
            │            │ imm             ▼
            │     ┌──────────────┐  ┌─────────────┐
            │     │   reg_file   │  │ alu_control  │
            │     └──┬───────┬───┘  └──────┬──────┘
            │      rd1│     │rd2           │alu_ctrl
            │         │  ALUSrc mux        │
            │         │  ┌──────┐          │
            │         └─►│ ALU  │◄─────────┘
            │            └──┬───┘
            │               │ alu_result
            │        ┌──────────────┐
            │        │   data_mem   │
            │        └──────┬───────┘
            │               │
            │         MemToReg mux
            │               │ write_back
            │        ┌──────────────┐
            └───────►│  reg_file WB │
                     └──────────────┘
```

### PC Next Selection
```
Jump & JALR  →  alu_result       (rs1 + imm)
Jump & JAL   →  pc + imm
Branch taken →  pc + imm
Default      →  pc + 4
```

---

## Modules

| Module | File | Description |
|--------|------|--------------|
| `riscv_top` | `rtl/core/riscv_top.sv` | Top-level system: instantiates the core and both memories, wired via a real bus interface |
| `riscv_core` | `rtl/core/riscv_core.sv` | CPU datapath and control — the synthesis boundary; exposes instruction/data memory access as bus ports rather than containing memory directly |
| `pc` | `rtl/core/pc.sv` | Program counter with synchronous reset |
| `instr_mem` | `rtl/core/instr_mem.sv` | 256-word instruction ROM (sibling of the core, not nested inside it) |
| `control_unit` | `rtl/core/control_unit.sv` | Main control signal decoder |
| `alu_control` | `rtl/core/alu_control.sv` | Two-stage ALU operation decoder |
| `reg_file` | `rtl/core/reg_file.sv` | 32×32 register file, x0 hardwired to 0 |
| `imm_gen` | `rtl/core/imm_gen.sv` | Immediate sign-extension for all formats |
| `alu` | `rtl/core/alu.sv` | 10-operation arithmetic logic unit |
| `data_mem` | `rtl/core/data_mem.sv` | 256-word data RAM (word-aligned), sibling of the core |
| `riscv_pkg` | `rtl/common/riscv_pkg.sv` | Shared constants and encodings |

---

## Supported Instructions

### R-Type
| Instruction | Operation |
|-------------|-----------|
| `add` | rd = rs1 + rs2 |
| `sub` | rd = rs1 - rs2 |
| `sll` | rd = rs1 << rs2[4:0] |
| `slt` | rd = (rs1 < rs2) signed |
| `sltu` | rd = (rs1 < rs2) unsigned |
| `xor` | rd = rs1 ^ rs2 |
| `srl` | rd = rs1 >> rs2[4:0] |
| `sra` | rd = rs1 >>> rs2[4:0] |
| `or` | rd = rs1 \| rs2 |
| `and` | rd = rs1 & rs2 |

### I-Type (ALU Immediate)
`addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`

### I-Type (Load)
| Instruction | Supported |
|-------------|-----------|
| `lw` | Yes |
| `lb`, `lh`, `lbu`, `lhu` | Not implemented |

### S-Type (Store)
| Instruction | Supported |
|-------------|-----------|
| `sw` | Yes |
| `sb`, `sh` | Not implemented |

### B-Type (Branch)
`beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu`

### U-Type
`lui`, `auipc`

### J-Type
`jal`, `jalr`

> Byte and halfword memory operations (lb, lh, lbu, lhu, sb, sh) are not implemented. The data memory supports 32-bit word-aligned accesses only.

---

## Two-Stage ALU Decode

ALU operation is determined in two stages:

1. **`control_unit`** outputs a 2-bit `ALUOp` based on the instruction opcode:
   - `00` — force ADD (load/store address calculation)
   - `01` — decode from funct3 (branch comparisons)
   - `10` — decode from funct3 + funct7[5] (R-type and I-ALU)

2. **`alu_control`** uses `ALUOp`, `funct3`, and `funct7[5]` to select the final 4-bit ALU operation.

---

## Project Structure

```
.
├── rtl/
│   ├── common/
│   │   └── riscv_pkg.sv        # Shared package: opcodes, funct3/7, ALU codes
│   └── core/
│       ├── riscv_top.sv        # Top-level system: core + instruction/data memory
│       ├── riscv_core.sv       # CPU datapath and control (synthesis boundary)
│       ├── pc.sv
│       ├── instr_mem.sv
│       ├── control_unit.sv
│       ├── alu_control.sv
│       ├── reg_file.sv
│       ├── imm_gen.sv
│       ├── alu.sv
│       └── data_mem.sv
└── tb/
    ├── alu/                    # ALU unit test
    ├── alu_control/            # ALU control unit test
    ├── control_unit/           # Control unit test
    ├── data_mem/               # Data memory unit test
    ├── imm_gen/                # Immediate generator unit test
    ├── pc/                     # Program counter unit test
    ├── reg_file/               # Register file unit test
    └── core/                   # Integration tests
        ├── test_riscv_core.py
        ├── Makefile
        └── programs/
            ├── asm/            # RISC-V assembly source files
            └── hex/            # Assembled hex files loaded by testbench
```

---

## Running Tests

### Dependencies
- [Verilator](https://verilator.org) — SystemVerilog simulator
- [cocotb](https://www.cocotb.org) — Python-based HDL verification framework
- `riscv64-unknown-elf` toolchain — for assembling test programs

### Unit Tests
Each module has its own testbench under `tb/<module>/`:
```bash
cd tb/alu
make
```

### Integration Tests
```bash
cd tb/core
make
```

### Assembling Test Programs
Test programs are written in RISC-V assembly and assembled using the included script:
```bash
cd tb/core/programs
./assemble.sh <program_name>
# e.g. ./assemble.sh r_type
```
This produces `.o`, `.elf`, and `.hex` files. Only `.hex` files are loaded by the testbench.

---

## Tools

| Tool | Purpose |
|------|---------|
| SystemVerilog | RTL implementation language |
| Verilator | Linting and simulation |
| cocotb | Python testbench framework |
| GTKWave | Waveform viewer |
| riscv64-unknown-elf | RISC-V assembler and linker |

## Synthesis & Static Timing Analysis
Synthesized with Yosys 0.67 targeting the SkyWater SKY130 (sky130_fd_sc_hd, typical corner) standard cell library; timing analyzed with OpenSTA 3.1.0.

**Netlist**: 4,176 standard cells total across the core and its 6 submodules (alu, alu_control, control_unit, imm_gen, pc, reg_file). reg_file dominates at ~2,500 cells (31 writable 32-bit registers plus read/write mux logic — x0 is correctly optimized away since it's never written), followed by the ALU at ~1,000 cells.

**Critical path**: register file read → ALUSrc mux → ALU (signed SLT comparison) → register file write-back. Data arrival time: 12.65ns.

**Max frequency**: ≈76.3MHz (12.65ns critical path + 0.45ns setup margin). Confirmed violating at a 100MHz (10ns) test constraint (slack -3.10ns).

**Why this is the critical path**: this is the datapath for an SLT-class instruction (or an equivalent BLT/BGE branch comparison) — the longest logic chain in the design, because a signed comparison requires a full 32-bit subtraction (same carry-propagation cost as addition) plus extra logic to correctly handle the signed-overflow edge case. This is the textbook single-cycle bottleneck, and the direct point of comparison against the pipelined core, where this computation gets split across multiple stages instead of forced into one cycle.

**Note on run-to-run variance**: exact cell counts and path delays vary slightly (observed in the 12–14ns range) across separate synthesis runs of identical RTL, due to non-deterministic heuristics in ABC's technology-mapping passes. The critical path itself — the ALU's signed-comparison logic — is consistent across runs; only the precise gate count and nanosecond figure shift.

**Known limitation**: this analysis treats readData (from data_mem) as an idealized, zero-delay input, since data_mem is synthesized separately from the core (standard practice — a CPU core's synthesis boundary is its bus interface, not the memory behind it). A full-system synthesis was attempted to capture this, but instr_mem's contents (populated only via testbench force during simulation, not synthesizable RTL) get constant-folded by the optimizer, which collapses the branch/jump decode logic to a fixed case and invalidates the resulting timing, which is why this analysis is scoped to the core in isolation.
