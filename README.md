# 🔄 Asynchronous FIFO — Verilog Implementation

[![Language](https://img.shields.io/badge/Language-Verilog-blue)](https://en.wikipedia.org/wiki/Verilog)
[![Tool](https://img.shields.io/badge/Tool-Xilinx%20Vivado%202025.1-orange)](https://www.xilinx.com/products/design-tools/vivado.html)
[![FPGA](https://img.shields.io/badge/Target-xc7vx485tffg1157--1-green)](https://www.xilinx.com)
[![License](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

---

## 📌 Overview

An **Asynchronous FIFO (First-In First-Out)** is a memory buffer used to safely transfer data between two clock domains operating at **different frequencies**. This is one of the most fundamental and critical designs in digital SoC and FPGA design — used in USB controllers, DDR interfaces, NoC fabrics, and more.

This implementation uses the classic **Gray code pointer synchronization** technique to safely cross the clock domain boundary without metastability errors.

---

## 🏗️ Architecture

```
                    Write Domain                       Read Domain
                  ┌─────────────┐                  ┌─────────────┐
  wclk  ──────►  │             │                  │             │  ◄────── rclk
  wrst_n ─────►  │  wptr_h     │                  │  rptr_h     │  ◄────── rrst_n
  w_en  ──────►  │  (Write     │                  │  (Read      │  ◄────── r_en
  data_in ────►  │   Pointer   │                  │   Pointer   │
                 │   Handler)  │                  │   Handler)  │  ──────► data_out
                 └──────┬──────┘                  └──────┬──────┘
                        │ g_wptr (Gray)                  │ g_rptr (Gray)
                        ▼                                ▼
                 ┌──────────────┐              ┌──────────────┐
                 │  sync_rptr   │              │  sync_wptr   │
                 │ (2FF sync in │              │ (2FF sync in │
                 │  wclk domain)│              │  rclk domain)│
                 └──────────────┘              └──────────────┘
                        │                                │
                        └──────────┬─────────────────────┘
                                   ▼
                          ┌─────────────────┐
                          │    fifom         │
                          │  (Dual-Port      │
                          │   FIFO Memory)   │
                          │                  │
                          │  fifo[0:7][7:0]  │
                          └─────────────────┘
                                   │
                            full / empty flags
```

---

## 📐 Module Hierarchy

| Module | Description |
|--------|-------------|
| `asynchronous_fifo` | Top-level module — instantiates all sub-modules |
| `wptr_h` | Write pointer handler — generates Gray-coded write pointer, detects **FULL** |
| `rptr_h` | Read pointer handler — generates Gray-coded read pointer, detects **EMPTY** |
| `sync_wptr` | 2-FF synchronizer — synchronizes `g_wptr` into the **read clock domain** |
| `sync_rptr` | 2-FF synchronizer — synchronizes `g_rptr` into the **write clock domain** |
| `fifom` | Dual-port FIFO memory — 8 deep × 8-bit wide |
| `tb_async_fifo` | Testbench — drives all test cases |

---

## ⚙️ Parameters & Port Description

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 8 | Width of each data word in bits |
| `DEPTH` | 8 | Number of entries in the FIFO |
| `PTR_WIDTH` | 3 | Pointer width = log₂(DEPTH) |

### Ports

| Port | Direction | Width | Clock Domain | Description |
|------|-----------|-------|--------------|-------------|
| `wclk` | Input | 1 | Write | Write clock |
| `rclk` | Input | 1 | Read | Read clock (independent frequency) |
| `wrst_n` | Input | 1 | Write | Active-low write reset |
| `rrst_n` | Input | 1 | Read | Active-low read reset |
| `w_en` | Input | 1 | Write | Write enable |
| `r_en` | Input | 1 | Read | Read enable |
| `data_in` | Input | 8 | Write | Data to write |
| `data_out` | Output | 8 | Read | Data read out |
| `full` | Output | 1 | Write | FIFO full flag |
| `empty` | Output | 1 | Read | FIFO empty flag |

---

## 🔑 Key Design Concepts

### 1. Gray Code Pointer Synchronization
Binary pointers are converted to **Gray code** before crossing the clock domain. Gray code ensures only **1 bit changes per increment**, making it metastability-safe when sampled by the other clock domain.

```
Binary:  000 → 001 → 010 → 011 → 100
Gray:    000 → 001 → 011 → 010 → 110
              ↑1bit change each time↑
```

### 2. Full Flag Detection (Write Domain)
```
FULL when: g_wptr_next == {~g_rptr_sync[PTR_WIDTH:PTR_WIDTH-1], g_rptr_sync[PTR_WIDTH-2:0]}
```
The MSB and second-MSB are **inverted** and compared to detect wrap-around.

### 3. Empty Flag Detection (Read Domain)
```
EMPTY when: g_rptr_next == g_wptr_sync
```
Pointers match exactly when FIFO is empty.

### 4. Two-Flip-Flop Synchronizer
Each pointer crossing uses a **2-stage FF synchronizer** (`q1` → `q2`) to reduce MTBF (Mean Time Between Failures) due to metastability.

---

## 🧪 Testbench & Test Cases

The testbench `tb_async_fifo` covers **4 simulation scenarios**, each captured as a separate waveform configuration (`.wcfg`):

---

### Test Case 1 — Full System Overview (`tb_async_fifo_behav.wcfg`)
**Signals Observed:** `wclk`, `rclk`, `wrst_n`, `rrst_n`, `w_en`, `r_en`, `data_in[7:0]`, `data_out[7:0]`, `full`, `empty`, `b_wptr[3:0]`, `b_rptr[3:0]`, `g_wptr`, `g_rptr`, internal FIFO memory `fifo[0:7][7:0]`

**What this tests:**
- Complete write-then-read cycle across different clock frequencies
- Binary pointer (`b_wptr`, `b_rptr`) and Gray-code pointer (`g_wptr`, `g_rptr`) progression
- `full` flag assertion when all 8 slots are written
- `empty` flag assertion after all data is read out
- Internal FIFO memory state at each write

**Simulation Time Window:** 0 ns → 4,228 ns

> 📸 Add your waveform screenshot here:
> `![TC1 - Full System Overview](images/tc1_full_overview.png)`

---

### Test Case 2 — Read Pointer Synchronizer (`tb_async_fifo_behav1.wcfg`)
**Signals Observed:** `sync_rptr/in[3:0]`, `sync_rptr/q1[3:0]`, `sync_rptr/q2[3:0]`, `sync_rptr/clk`, `sync_rptr/rstn`

**What this tests:**
- The **2-FF synchronizer** for the read pointer crossing into the write clock domain
- `in` → `q1` (1st FF stage, 1 wclk cycle delay)
- `q1` → `q2` (2nd FF stage, 2nd wclk cycle delay)
- The synchronized Gray pointer `q2` is used by `wptr_h` for FULL detection

**Simulation Time Window:** 0 ns → 1,405 ns

> 📸 Add your waveform screenshot here:
> `![TC2 - Read Pointer Sync](images/tc2_sync_rptr.png)`

---

### Test Case 3 — Write Pointer Handler (`tb_async_fifo_behav2.wcfg`)
**Signals Observed:** `wptr_h/wclk`, `wptr_h/w_rstn`, `wptr_h/w_enable`, `wptr_h/g_rptr_sync[3:0]`, `wptr_h/b_wptr[3:0]`, `wptr_h/g_wptr[3:0]`, `wptr_h/full`, `wptr_h/b_wptr_next`, `wptr_h/g_wptr_next`, `wptr_h/wfull`

**What this tests:**
- Write pointer binary-to-Gray conversion at each write cycle
- `b_wptr_next` and `g_wptr_next` look-ahead pointer logic
- **FULL flag** generation: comparison of `g_wptr_next` vs `g_rptr_sync`
- Correct pointer wrap-around behavior

**Simulation Time Window:** 0 ns → 2,943 ns

> 📸 Add your waveform screenshot here:
> `![TC3 - Write Pointer Handler](images/tc3_wptr_handler.png)`

---

### Test Case 4 — Read Pointer Handler (`tb_async_fifo_behav3.wcfg`)
**Signals Observed:** `rptr_h/rclk`, `rptr_h/r_rstn`, `rptr_h/r_enable`, `rptr_h/g_wptr_sync[3:0]`, `rptr_h/b_rptr[3:0]`, `rptr_h/g_rptr[3:0]`, `rptr_h/empty`, `rptr_h/b_rptr_next`, `rptr_h/g_rptr_next`, `rptr_h/r_empty`, `fifom/wclk`, `fifom/rclk`, `fifom/w_en`, `fifom/r_en`, `fifom/b_wptr`, `fifom/b_rptr`, `fifom/data_in`, `fifom/data_out`, `fifom/full`, `fifom/empty`, `fifom/fifo[0:7][7:0]`

**What this tests:**
- Read pointer binary-to-Gray conversion
- **EMPTY flag** generation: `g_rptr_next == g_wptr_sync`
- FIFO memory read/write with both clocks simultaneously visible
- Cross-domain memory access correctness

**Simulation Time Window:** 530 ns → 598 ns (zoomed into the critical data transfer window)

> 📸 Add your waveform screenshot here:
> `![TC4 - Read Pointer Handler](images/tc4_rptr_handler.png)`

---

## 📁 Repository Structure

```
Asynchronous-FIFO/
├── README.md                  ← This file
├── src/
│   └── async_fifo.v           ← Top module + all sub-modules
├── testbench/
│   └── tb_async_fifo.v        ← Testbench with all 4 test cases
├── images/
│   ├── tc1_full_overview.png  ← Waveform: Full system simulation
│   ├── tc2_sync_rptr.png      ← Waveform: Read pointer synchronizer
│   ├── tc3_wptr_handler.png   ← Waveform: Write pointer handler
│   └── tc4_rptr_handler.png   ← Waveform: Read pointer + memory
└── docs/
    └── architecture.md        ← Detailed design notes
```

---

## 🚀 How to Simulate (Xilinx Vivado)

1. Open **Vivado 2025.1**
2. Create a new project → Add `src/async_fifo.v` as design source
3. Add `testbench/tb_async_fifo.v` as simulation source
4. Set `tb_async_fifo` as the top simulation module
5. Click **Run Simulation → Run Behavioral Simulation**
6. In the waveform window, load `.wcfg` files from the project root to view each test case

---

## 📚 References

- Cummings, C. E. (2002). *Simulation and Synthesis Techniques for Asynchronous FIFO Design*. SNUG 2002.
- Xilinx UG901 — Vivado Design Suite User Guide: Synthesis
- Patterson & Hennessy — *Computer Organization and Design*

---

## 👤 Author

**Nimmana Shashank Krishna**  
B.E / B.Tech — VLSI / ECE / EEE  
📧 nimmana.shashank@example.com  
🔗 [LinkedIn](https://www.linkedin.com/in/nimmana-shashank-krishna-423516258) | [GitHub](https://github.com/NimmanaShashankKrishna)

---

*This project was designed and simulated using Xilinx Vivado 2025.1 on xc7vx485tffg1157-1 FPGA target.*
