create_pblock pblock_dram
add_cells_to_pblock [get_pblocks pblock_dram] [get_cells -quiet [list ddr_design_i/mig_7series_0]]
resize_pblock [get_pblocks pblock_dram] -add {CLOCKREGION_X1Y0:CLOCKREGION_X1Y2}
set_property IS_SOFT TRUE [get_pblocks pblock_dram]

create_pblock pblock_core
add_cells_to_pblock [get_pblocks pblock_core] [get_cells -quiet [list ddr_design_i/cpu]]
resize_pblock [get_pblocks pblock_core] -add {SLICE_X36Y100:SLICE_X99Y174}
resize_pblock [get_pblocks pblock_core] -add {DSP48_X2Y40:DSP48_X5Y69}
resize_pblock [get_pblocks pblock_core] -add {RAMB18_X2Y40:RAMB18_X5Y69}
resize_pblock [get_pblocks pblock_core] -add {RAMB36_X2Y20:RAMB36_X5Y34}
set_property IS_SOFT TRUE [get_pblocks pblock_core]

create_pblock pblock_dcache
add_cells_to_pblock [get_pblocks pblock_dcache] [get_cells -quiet [list ddr_design_i/cpu/Data_cache_w32_addr32_0]]
resize_pblock [get_pblocks pblock_dcache] -add {SLICE_X74Y100:SLICE_X97Y129}
resize_pblock [get_pblocks pblock_dcache] -add {DSP48_X4Y40:DSP48_X5Y51}
resize_pblock [get_pblocks pblock_dcache] -add {RAMB18_X4Y40:RAMB18_X4Y51}
resize_pblock [get_pblocks pblock_dcache] -add {RAMB36_X4Y20:RAMB36_X4Y25}
set_property IS_SOFT FALSE [get_pblocks pblock_dcache]

create_pblock pblock_icache
add_cells_to_pblock [get_pblocks pblock_icache] [get_cells -quiet [list ddr_design_i/cpu/Inst_cache_w32_addr32_0]]
resize_pblock [get_pblocks pblock_icache] -add {SLICE_X54Y100:SLICE_X73Y129}
resize_pblock [get_pblocks pblock_icache] -add {DSP48_X3Y40:DSP48_X3Y51}
resize_pblock [get_pblocks pblock_icache] -add {RAMB18_X3Y40:RAMB18_X3Y51}
resize_pblock [get_pblocks pblock_icache] -add {RAMB36_X3Y20:RAMB36_X3Y25}
set_property IS_SOFT FALSE [get_pblocks pblock_icache]

create_pblock pblock_interconnect
resize_pblock [get_pblocks pblock_interconnect] -add {SLICE_X36Y50:SLICE_X107Y99}
resize_pblock [get_pblocks pblock_interconnect] -add {DSP48_X2Y20:DSP48_X6Y39}
resize_pblock [get_pblocks pblock_interconnect] -add {RAMB18_X2Y20:RAMB18_X5Y39}
resize_pblock [get_pblocks pblock_interconnect] -add {RAMB36_X2Y10:RAMB36_X5Y19}
set_property IS_SOFT TRUE [get_pblocks pblock_interconnect]
add_cells_to_pblock [get_pblocks pblock_interconnect] [get_cells -quiet [list ddr_design_i/axi_interconnect_0 ddr_design_i/axi_interconnect_1]]

set_property PARENT pblock_core [get_pblocks pblock_dcache]
set_property PARENT pblock_core [get_pblocks pblock_icache]

create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 6 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list ddr_design_i/clocking_unit/clk_wiz_0/inst/cpu_clk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {ddr_design_i/uart_module/inst/rx_fifo_dout[0]} {ddr_design_i/uart_module/inst/rx_fifo_dout[1]} {ddr_design_i/uart_module/inst/rx_fifo_dout[2]} {ddr_design_i/uart_module/inst/rx_fifo_dout[3]} {ddr_design_i/uart_module/inst/rx_fifo_dout[4]} {ddr_design_i/uart_module/inst/rx_fifo_dout[5]} {ddr_design_i/uart_module/inst/rx_fifo_dout[6]} {ddr_design_i/uart_module/inst/rx_fifo_dout[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 8 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {ddr_design_i/uart_module/inst/rx_fifo_din[0]} {ddr_design_i/uart_module/inst/rx_fifo_din[1]} {ddr_design_i/uart_module/inst/rx_fifo_din[2]} {ddr_design_i/uart_module/inst/rx_fifo_din[3]} {ddr_design_i/uart_module/inst/rx_fifo_din[4]} {ddr_design_i/uart_module/inst/rx_fifo_din[5]} {ddr_design_i/uart_module/inst/rx_fifo_din[6]} {ddr_design_i/uart_module/inst/rx_fifo_din[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list ddr_design_i/uart_module/inst/parity_error]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list ddr_design_i/uart_module/inst/rx_fifo_empty]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list ddr_design_i/uart_module/inst/rx_fifo_full]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list ddr_design_i/uart_module/inst/rx_fifo_rd_en]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list ddr_design_i/uart_module/inst/rx_fifo_wr_en]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets u_ila_0_cpu_clk]
