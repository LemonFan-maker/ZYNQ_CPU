set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $repo_dir build vivado_hw]
set report_dir [file join $build_dir reports]
set old_ps7_xci /home/orionisli/Working/Zynq_GPGPU/Zynq_GPGPU_Core.srcs/sources_1/bd/gpu_system/ip/gpu_system_processing_system7_0_0/gpu_system_processing_system7_0_0.xci

file mkdir $build_dir
file mkdir $report_dir

proc load_user_ps7_props {xci_path} {
    set fp [open $xci_path r]
    set props [list]
    while {[gets $fp line] >= 0} {
        if {[regexp {^[ \t]*"(PCW_[^"]+)":[ \t]*\[ \{ "value": "([^"]*)"} $line -> key value]} {
            if {[string first {"value_src": "user"} $line] >= 0} {
                lappend props CONFIG.$key $value
            }
        }
    }
    close $fp
    return $props
}

create_project -force zynq_cpu_hw $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
set_property include_dirs [list [file join $repo_dir rtl core]] [current_fileset]

read_verilog -sv [file join $repo_dir rtl core cpu_defs.svh]
read_verilog -sv [file join $repo_dir rtl core alu.sv]
read_verilog -sv [file join $repo_dir rtl core regfile.sv]
read_verilog -sv [file join $repo_dir rtl core zx32_core.sv]
read_verilog -sv [file join $repo_dir rtl periph simple_ram.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_uart_tx.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_timer.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_irqctrl.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_gpu_fill.sv]
read_verilog -sv [file join $repo_dir rtl video video_timing.sv]
read_verilog -sv [file join $repo_dir rtl video tmds_encoder.sv]
read_verilog -sv [file join $repo_dir rtl video hdmi_test_pattern.sv]
read_verilog -sv [file join $repo_dir rtl video hdmi_test_pattern_core.sv]
read_verilog -sv [file join $repo_dir rtl video hdmi_console_ram.sv]
read_verilog -sv [file join $repo_dir rtl video hdmi_text_console_core.sv]
read_verilog -sv [file join $repo_dir rtl video mmio_display_ctrl.sv]
read_verilog -sv [file join $repo_dir rtl video hdmi_tmds_oserdes_xilinx.sv]
read_verilog [file join $repo_dir rtl video hdmi_test_pattern_top_xilinx.v]
read_verilog -sv [file join $repo_dir rtl periph axis_scratchpad.sv]
read_verilog -sv [file join $repo_dir rtl periph axi_lite_bringup_regs.sv]
read_verilog -sv [file join $repo_dir rtl bus datamover_ctrl.sv]
read_verilog -sv [file join $repo_dir rtl bus axi4_master_bridge.sv]
read_verilog -sv [file join $repo_dir rtl soc zx32_soc.sv]
read_verilog [file join $repo_dir rtl periph axi_lite_bringup_regs_bd.v]
read_verilog [file join $repo_dir rtl soc zx32_soc_bd.v]
update_compile_order -fileset sources_1

create_bd_design zynq_cpu_system

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set_property -dict [load_user_ps7_props $old_ps7_xci] [get_bd_cells processing_system7_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_75M

create_bd_cell -type module -reference zx32_soc_bd zx32_soc_0
create_bd_cell -type module -reference axi_lite_bringup_regs_bd bringup_regs_0
create_bd_cell -type module -reference hdmi_test_pattern_top_xilinx hdmi_test_0

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_datamover:5.1 axi_datamover_0
set_property -dict [list \
    CONFIG.c_enable_mm2s {1} \
    CONFIG.c_enable_s2mm {1} \
    CONFIG.c_include_mm2s {Full} \
    CONFIG.c_include_s2mm {Full} \
    CONFIG.c_single_interface {0} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
    CONFIG.c_m_axi_mm2s_addr_width {32} \
    CONFIG.c_m_axi_s2mm_addr_width {32} \
    CONFIG.c_addr_width {32} \
    CONFIG.c_mm2s_btt_used {23} \
    CONFIG.c_s2mm_btt_used {23} \
    CONFIG.c_include_mm2s_dre {false} \
    CONFIG.c_include_s2mm_dre {false} \
] [get_bd_cells axi_datamover_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_ctrl_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells axi_ctrl_smc]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_hp0_intercon
set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] [get_bd_cells axi_hp0_intercon]

make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/DDR]
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/FIXED_IO]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_75M/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins zx32_soc_0/clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins hdmi_test_0/clk_75mhz]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins zx32_soc_0/S_AXI_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins bringup_regs_0/S_AXI_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_smc/aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S01_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S02_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/M00_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axis_mm2s_cmdsts_aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axis_s2mm_cmdsts_awclk]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_75M/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins zx32_soc_0/rst_n]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins hdmi_test_0/rst_n]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins zx32_soc_0/S_AXI_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins bringup_regs_0/S_AXI_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_ctrl_smc/aresetn]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S01_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S02_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/M00_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axi_mm2s_aresetn]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axi_s2mm_aresetn]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axis_mm2s_cmdsts_aresetn]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axis_s2mm_cmdsts_aresetn]

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_smc/M00_AXI] [get_bd_intf_pins bringup_regs_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_smc/M01_AXI] [get_bd_intf_pins zx32_soc_0/S_AXI]

connect_bd_intf_net [get_bd_intf_pins axi_datamover_0/M_AXI_MM2S] [get_bd_intf_pins axi_hp0_intercon/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_datamover_0/M_AXI_S2MM] [get_bd_intf_pins axi_hp0_intercon/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins zx32_soc_0/M_AXI_DDR] [get_bd_intf_pins axi_hp0_intercon/S02_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_hp0_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

connect_bd_net [get_bd_pins zx32_soc_0/dm_mm2s_cmd_valid] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tvalid]
connect_bd_net [get_bd_pins zx32_soc_0/dm_mm2s_cmd_ready] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tready]
connect_bd_net [get_bd_pins zx32_soc_0/dm_mm2s_cmd_data] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tdata]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s2mm_cmd_valid] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tvalid]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s2mm_cmd_ready] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tready]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s2mm_cmd_data] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tdata]

connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tvalid] [get_bd_pins zx32_soc_0/dm_mm2s_sts_valid]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tready] [get_bd_pins zx32_soc_0/dm_mm2s_sts_ready]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tdata] [get_bd_pins zx32_soc_0/dm_mm2s_sts_data]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tvalid] [get_bd_pins zx32_soc_0/dm_s2mm_sts_valid]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tready] [get_bd_pins zx32_soc_0/dm_s2mm_sts_ready]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tdata] [get_bd_pins zx32_soc_0/dm_s2mm_sts_data]

connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tdata] [get_bd_pins zx32_soc_0/dm_m_axis_mm2s_tdata]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tkeep] [get_bd_pins zx32_soc_0/dm_m_axis_mm2s_tkeep]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tlast] [get_bd_pins zx32_soc_0/dm_m_axis_mm2s_tlast]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tvalid] [get_bd_pins zx32_soc_0/dm_m_axis_mm2s_tvalid]
connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tready] [get_bd_pins zx32_soc_0/dm_m_axis_mm2s_tready]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s_axis_s2mm_tdata] [get_bd_pins axi_datamover_0/s_axis_s2mm_tdata]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s_axis_s2mm_tkeep] [get_bd_pins axi_datamover_0/s_axis_s2mm_tkeep]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s_axis_s2mm_tlast] [get_bd_pins axi_datamover_0/s_axis_s2mm_tlast]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s_axis_s2mm_tvalid] [get_bd_pins axi_datamover_0/s_axis_s2mm_tvalid]
connect_bd_net [get_bd_pins zx32_soc_0/dm_s_axis_s2mm_tready] [get_bd_pins axi_datamover_0/s_axis_s2mm_tready]

connect_bd_net [get_bd_pins zx32_soc_0/display_enable] [get_bd_pins hdmi_test_0/display_enable]
connect_bd_net [get_bd_pins zx32_soc_0/display_test_pattern_enable] [get_bd_pins hdmi_test_0/test_pattern_enable]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_enable] [get_bd_pins hdmi_test_0/text_enable]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_clear] [get_bd_pins hdmi_test_0/text_clear]
connect_bd_net [get_bd_pins zx32_soc_0/display_mode] [get_bd_pins hdmi_test_0/mode]
connect_bd_net [get_bd_pins zx32_soc_0/display_bg_color] [get_bd_pins hdmi_test_0/bg_color]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_we] [get_bd_pins hdmi_test_0/text_we]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_word_addr] [get_bd_pins hdmi_test_0/text_word_addr]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_wdata] [get_bd_pins hdmi_test_0/text_wdata]
connect_bd_net [get_bd_pins zx32_soc_0/display_text_wstrb] [get_bd_pins hdmi_test_0/text_wstrb]
connect_bd_net [get_bd_pins zx32_soc_0/display_attr_we] [get_bd_pins hdmi_test_0/attr_we]
connect_bd_net [get_bd_pins zx32_soc_0/display_attr_word_addr] [get_bd_pins hdmi_test_0/attr_word_addr]
connect_bd_net [get_bd_pins zx32_soc_0/display_attr_wdata] [get_bd_pins hdmi_test_0/attr_wdata]
connect_bd_net [get_bd_pins zx32_soc_0/display_attr_wstrb] [get_bd_pins hdmi_test_0/attr_wstrb]
connect_bd_net [get_bd_pins zx32_soc_0/display_font_we] [get_bd_pins hdmi_test_0/font_we]
connect_bd_net [get_bd_pins zx32_soc_0/display_font_word_addr] [get_bd_pins hdmi_test_0/font_word_addr]
connect_bd_net [get_bd_pins zx32_soc_0/display_font_wdata] [get_bd_pins hdmi_test_0/font_wdata]
connect_bd_net [get_bd_pins zx32_soc_0/display_font_wstrb] [get_bd_pins hdmi_test_0/font_wstrb]

make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_CLK_P]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_CLK_N]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D0_P]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D0_N]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D1_P]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D1_N]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D2_P]
make_bd_pins_external [get_bd_pins hdmi_test_0/HDMI_D2_N]

set_property name HDMI_CLK_P [get_bd_ports HDMI_CLK_P_0]
set_property name HDMI_CLK_N [get_bd_ports HDMI_CLK_N_0]
set_property name HDMI_D0_P [get_bd_ports HDMI_D0_P_0]
set_property name HDMI_D0_N [get_bd_ports HDMI_D0_N_0]
set_property name HDMI_D1_P [get_bd_ports HDMI_D1_P_0]
set_property name HDMI_D1_N [get_bd_ports HDMI_D1_N_0]
set_property name HDMI_D2_P [get_bd_ports HDMI_D2_P_0]
set_property name HDMI_D2_N [get_bd_ports HDMI_D2_N_0]

assign_bd_address
set_property offset 0x43C00000 [get_bd_addr_segs {processing_system7_0/Data/SEG_bringup_regs_0_reg0}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_bringup_regs_0_reg0}]
set_property offset 0x43C10000 [get_bd_addr_segs {processing_system7_0/Data/SEG_zx32_soc_0_reg0}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_zx32_soc_0_reg0}]

validate_bd_design
save_bd_design

if {[info exists ::env(ZYNQ_CPU_VALIDATE_ONLY)] && $::env(ZYNQ_CPU_VALIDATE_ONLY) == "1"} {
    puts "ZYNQ_CPU_VALIDATE_ONLY=1: stopping after validate_bd_design"
    close_project
    return
}

set wrapper_path [make_wrapper -files [get_files [file join $build_dir zynq_cpu_hw.srcs sources_1 bd zynq_cpu_system zynq_cpu_system.bd]] -top]
add_files -norecurse $wrapper_path
set_property top zynq_cpu_system_wrapper [current_fileset]
read_xdc [file join $repo_dir constraints ax7020_hdmi.xdc]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 did not complete"
}
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "synth_1 failed: [get_property STATUS [get_runs synth_1]]"
}

set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 did not complete"
}
if {![string match "*Complete!*" [get_property STATUS [get_runs impl_1]]]} {
    error "impl_1 failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_utilization -file [file join $report_dir zynq_cpu_system_utilization.rpt]
report_timing_summary -file [file join $report_dir zynq_cpu_system_timing_summary.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $build_dir zynq_cpu_system_wrapper.xsa]
