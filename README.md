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

- **Instruction Set**: `rv32im_zicond_zifencei`, only supports M-mode
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
- **Interrupt/Exception**: Not yet... XwX
- **Divider**: independently implemented Base-4 divider, completes 32bit division in 4~18 cycles
- **Multiplier**: using Multiplier IP from Xilinx for now

### Timing, Utilization, Performance

The following data are measured on Xilinx's FPGA chip `xc7k410t-ffg900-2` using Vivado 2020.1, with a 64-bit DDR controller IP from Xilinx (MIG 7 Series) attached. Customized synthesis and implementation options are also applied to achieve the best results possible.

- **Maximum Tested Freq.**: 200MHz (T=5ns)
- **IPC**: somewhere around 0.6 to 0.7, depending on the workload
- **Utilization**
  - Full design (including AXI infra. and DDR controllers): ~34000 LUTs, ~35000 FFs
  - Core: ~6500 LUTs, ~9500 FFs
  - L1d: ~2000 LUTs, ~3500 FFs
  - L1i: ~1500 LUTs, ~3500 FFs

Some test results, for reference:

- **JPEG Encoding**: Using `libjpeg` with `-O3`, encodes an `1024*1024px` JPEG image with 60% quality in 1.2s

## L1 Cache

The two L1 caches are both deeply embedded into the CPU pipeline, hiding the latency.

- **Data Size**: 16KiB each, total 32KiB
- **Associativity**: 4-way associative
- **Bus**: 128 bits wide, with AXI4-Full protocol
- **Cache Line**: each cache line contains 32 Words, 128 Bytes, with 8 *sublines* of 16 Bytes each to match the bus width. Total 128 cache lines.
- **LRU Implementation**: age matrix

## TODOs

### Short-term

Doable with in a short period of time, with designs that are ready and can be implemented.

#### Peripherals

- I2C communication peripheral (for RTC)

#### Components

- L2 cache

#### Code quality

- Control signals cleanup and clarification

### Long-term

Not doable in short-term:

- Lack certain required knowledge
- Engineering difficulties not yet addressed or approach not clear
- Missing information on offical specification where document are not yet done reading
- Missing prerequisites (eg. instruction set extension)

#### Architecture-level

- `Zicsr` extension along with extendable and modular CSR design (specification not yet finished reading, need to make a designing sheet for CSRs)
- Interrupt/Exception (`Zicsr` required)
- `F` extension (`Zicsr` required)
- `C` extension (CPU architecture not yet suitable, needs some cleanup and refactoring to the architecture; would cause absolute mess if implement it now)
- DMA (coherency issue)
- Priviledged architecture (`Zicsr` required, lacking OS knowledge)

#### Peripheral

- HDMI peripheral (lacking requried knowledge)
- SATA peripheral
- USB HID interface
- Ethernet (lacking required knowledge, no OS software environment)
