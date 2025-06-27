# Simple RISCV CPU Design

This is the source code for my own simple RISCV CPU design. It's primarily built for my own educational/learning purposes. No documentation are available by now, refer to the comments in the code.

## Content of the Repo

### CPU Core

Located under folder `./core`

- ALU
- Instruction Decode Unit
- Branch Unit
- Interface unit to L1d
- L1 Icache & L1 Dcache
  - `cache-w32-addr32.v`: the latest version with 128bits design and way better timing performance. 32bit interface, 32bit physical address, no virtual address translation.

### Peripheral

Located under folder `./peripheral`

- UART transmitter/receiver with runtime variable config
- Timer peripheral (interrupt not implemented yet)
- Fast SPI communication peripheral

## CPU Features

- **Instruction Set**: `rv32im_zicond_zicsr_zifencei`, only supports M-mode
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
- **Bypass/Forwarding**: Supported ^_^
- **Branch Prediction**: Supported ^_^
- **Cache Prefetching**: Not yet... XwX
- **Interrupt/Exception**: Implemented, not fully tested
- **Divider**: independently implemented Base-4 divider, completes 32bit division in 4~18 cycles
- **Multiplier**: using Multiplier IP from Xilinx for now

### Timing, Utilization, Performance

The following data are measured on Xilinx's FPGA chip `xc7k410t-ffg900-2` using Vivado 2020.1, with a 64-bit DDR controller IP from Xilinx (MIG 7 Series) attached. Customized synthesis and implementation options are also applied to achieve the best results possible.

- **Maximum Tested Freq.**: 200MHz (T=5ns)
- **IPC**: somewhere around 0.6 to 0.7, depending on the workload
- **Utilization**
  - Full design (including AXI infra. and DDR controllers): ~25000 LUTs, ~28000 FFs
  - Core: ~6500 LUTs, ~9500 FFs
  - L1d: ~2000 LUTs, ~3500 FFs
  - L1i: ~1500 LUTs, ~3500 FFs

Some test results, for reference:

- **JPEG Encoding**: Using `libjpeg` with `-O3`, encodes an `1024*1024px` JPEG image with 60% quality in 1.2s
- **h.264 Decoding**: Using `ffmpeg` with `-O3`, decodes 240p (320x240) video stream at 48FPS, decodes 1080p video stream at 1.38FPS

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
- `F` extension
- `Zicbom` extension

### Long-term

Not doable in short-term:

- `C` extension (architecture not yet suitable)
- DMA (coherency issue)
- Priviledged architecture (bad timing, not enough for MMU)
- HDMI peripheral (lacking DMA, memory bandwidth not sufficient)
- SATA peripheral (lack knowledge)
- USB HID interface (lack required hardware and knowledge)
- Ethernet (lacking required knowledge, no OS software environment)
