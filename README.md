# Simple RISCV CPU Design

This is the source code for my own simple RISCV CPU design. It's primarily built for my own educational/learning purposes. No documentation are available by now, refer to the comments in the code.

## CPU Features

- **Instruction Set**: `rv32im_zicond_zicsr_zifencei`, M-mode only
- **Execution**: In-order execution, pipelined
- **Pipeline**: 8-stage pipeline
  - PC
  - Icache Tag Fetch
  - Icache Instruction Fetch
  - Instruction Decode
  - Register Fetch
  - ALU Execution / Dcache Tag Fetch
  - Dcache Data Fetch
  - Register Writeback
- **Bypass/Forwarding**: Supported. Carries data from ALU stage, Data Fetch stage and Writeback stage to Register Fetch stage
- **Branch Prediction**: Two-stage prediction using PHT.
- **Interrupt/Exception**: Implemented, partially tested. Edge cases may exist.
- **Divider**: Base-4 divider, completes 32bit division in 4~18 cycles
- **Multiplier**: using Multiplier IP from Xilinx, in order to utilize built-in DSPs.

### Timing, Utilization, Performance

The following data are measured on Xilinx's FPGA chip `xc7k410t-ffg900-2` using Vivado 2020.1, with a 64-bit DDR controller IP from Xilinx (MIG 7 Series) attached. Customized synthesis and implementation options are also applied to achieve the best results possible.

- **Maximum Tested Freq.**: 200MHz (T=5ns)
- **IPC**: somewhere around 0.6 to 0.7, depending on the workload
- **Utilization**
  - Core: ~6000 LUTs, ~4100 FFs
    - L1d: ~1400 LUTs, ~400 FFs
    - L1i: ~800 LUTs, ~400 FFs

Some test results, for reference:

- **JPEG Encoding**: Using `libjpeg` with `-O3`, encodes an `1024*1024px` JPEG image with 60% quality in 1.2s
- **h.264 Decoding**: Using `ffmpeg` with `-O3`, decodes 240p (320x240) video stream at 40~48FPS, decodes 1080p video stream at ~1.38FPS
  
  > [!note]
  > Video decoding is typically a memory-bound task. Currently without L2, the result highly depends on the AXI infra configuration, as it influences latency between CPU core and DDR memory. The best results are achieved by using a manually-configured AXI IP topology. If SmartConnect IP or Interconnect IP by Xilinx is used, the performance is degraded, but at the same time provides a better developing experience and reduces time spent on manual configuration.

## Content of the Repo

### CPU Core

Located under folder `./core`

- ALU
- Instruction Decode Unit
- Branch Unit
- Interface unit to L1d
- L1 Icache & L1 Dcache

### Peripheral

Located under folder `./peripheral`

- UART transmitter/receiver with runtime variable config
- Timer peripheral (interrupt not implemented yet)
- Fast SPI communication peripheral

## L1 Cache

The two L1 caches are both deeply embedded into the CPU pipeline, hiding the latency.

- **Data Size**: 16KiB each, total 32KiB
- **Associativity**: 4-way associative
- **Bus**: 128 bits wide, with AXI4-Full protocol
- **Cache Line**: each cache line contains 32 Words, 128 Bytes, with 8 *sublines* of 16 Bytes each to match the bus width. Total 128 cache lines.
- **LRU Implementation**: 4x4 age matrix, precomputes the next swap-target

## TODOs

### Short-term

Doable with in a short period of time, with designs that are ready and can be implemented.

- I2C communication peripheral (for RTC)
- L2 cache
- `Zicbom` extension

### Long-term

Not doable in short-term:

- `C` extension (architecture not yet suitable)
- `F` extension (timing issue)
- DMA (coherency issue)
- Priviledged architecture (bad timing, not enough for MMU)
- HDMI peripheral (lacking DMA, memory bandwidth not sufficient)
- SATA peripheral (lack knowledge)
- USB HID interface (lack required hardware and knowledge)
- Ethernet (lacking required knowledge, no OS software environment)
