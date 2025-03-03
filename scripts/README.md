# Scripts

## `mig-workaround.tcl`

This is a workaround for faulty/buggy Xilinx MIG 7 Series IP netlist generation, which generates an unused `IDELAYCTRL` component leading to implementation failure. Apply this script before placement to resolve the error.
