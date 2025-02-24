create_pblock pblock_dram
add_cells_to_pblock [get_pblocks pblock_dram] [get_cells -quiet [list ddr_design_i/mig_7series_0]]
resize_pblock [get_pblocks pblock_dram] -add {CLOCKREGION_X1Y0:CLOCKREGION_X1Y2}

create_pblock pblock_core
add_cells_to_pblock [get_pblocks pblock_core] [get_cells -quiet [list ddr_design_i/cpu]]
resize_pblock [get_pblocks pblock_core] -add {SLICE_X36Y50:SLICE_X133Y174}
resize_pblock [get_pblocks pblock_core] -add {DSP48_X2Y20:DSP48_X7Y69}
resize_pblock [get_pblocks pblock_core] -add {RAMB18_X2Y20:RAMB18_X7Y69}
resize_pblock [get_pblocks pblock_core] -add {RAMB36_X2Y10:RAMB36_X7Y34}


