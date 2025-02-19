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

