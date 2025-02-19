set_property PACKAGE_PIN AB25 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

set_property IOSTANDARD LVCMOS33 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
set_property PACKAGE_PIN T23 [get_ports rx]
set_property PACKAGE_PIN T22 [get_ports tx]


set_property IOSTANDARD LVCMOS33 [get_ports dbg_led0]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_led1]
set_property PACKAGE_PIN R24 [get_ports dbg_led0]
set_property PACKAGE_PIN R23 [get_ports dbg_led1]

set_property PACKAGE_PIN AE10 [get_ports clk_pair_clk_p]
set_property PACKAGE_PIN AF10 [get_ports clk_pair_clk_n]
set_property IOSTANDARD DIFF_SSTL15_DCI [get_ports clk_pair_clk_p]
set_property IOSTANDARD DIFF_SSTL15_DCI [get_ports clk_pair_clk_n]


