set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $repo_dir build vivado_hw]
if {[info exists ::env(ZYNQ_CPU_VIVADO_BUILD_DIR)] && $::env(ZYNQ_CPU_VIVADO_BUILD_DIR) ne ""} {
    set build_dir [file normalize $::env(ZYNQ_CPU_VIVADO_BUILD_DIR)]
}
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

proc read_sv {repo_dir rel_path} {
    read_verilog -sv [file join $repo_dir $rel_path]
}

proc read_v {repo_dir rel_path} {
    read_verilog [file join $repo_dir $rel_path]
}

proc require_file {path msg} {
    if {![file exists $path]} {
        error $msg
    }
}

proc create_const_net {name width value sink_pins} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* $name
    set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL $value] [get_bd_cells $name]
    foreach sink_pin $sink_pins {
        connect_bd_net [get_bd_pins $name/dout] [get_bd_pins $sink_pin]
    }
}

proc create_const_net_if_present {name width value sink_pins} {
    set existing_pins [list]
    foreach sink_pin $sink_pins {
        set pin [get_bd_pins -quiet $sink_pin]
        if {[llength $pin] != 0} {
            lappend existing_pins $sink_pin
        }
    }
    if {[llength $existing_pins] != 0} {
        create_const_net $name $width $value $existing_pins
    }
}

set soc_env "rv32"
if {[info exists ::env(ZYNQ_CPU_SOC)]} {
    set soc_env [string tolower $::env(ZYNQ_CPU_SOC)]
}

switch -- $soc_env {
    "" -
    "rv32" -
    "zx32" -
    "32" {
        set soc_kind "rv32"
        set soc_ref "zx32_soc_bd"
        set soc_cell "zx32_soc_0"
        set soc_bd_file [file join $repo_dir rtl soc zx32_soc_bd.v]
        set use_datamover 1
        set soc_has_display_ports 1
    }
    "rv64" -
    "zx64" -
    "64" {
        set soc_kind "rv64"
        set soc_ref "zx64_soc_bd"
        set soc_cell "zx64_soc_0"
        set soc_bd_file [file join $repo_dir rtl soc zx64_soc_bd.v]
        set use_datamover 0
        set soc_has_display_ports 0
    }
    default {
        error "Unsupported ZYNQ_CPU_SOC='$soc_env' (expected rv32 or rv64)"
    }
}

puts "ZYNQ_CPU_SOC=$soc_kind: building $soc_ref"
require_file $soc_bd_file "ZYNQ_CPU_SOC=$soc_kind requires missing wrapper: $soc_bd_file"

set rv64_enable_fpu 1
if {$soc_kind eq "rv64"} {
    if {[info exists ::env(ZYNQ_CPU_RV64_ENABLE_FPU)] && $::env(ZYNQ_CPU_RV64_ENABLE_FPU) ne ""} {
        set rv64_enable_fpu $::env(ZYNQ_CPU_RV64_ENABLE_FPU)
    }
    puts "ZYNQ_CPU_RV64_ENABLE_FPU=$rv64_enable_fpu"
}

create_project -force zynq_cpu_hw $build_dir -part xc7z020clg400-2
set_property target_language Verilog [current_project]
if {$soc_kind eq "rv64"} {
    set_property include_dirs [list [file join $repo_dir rtl core64] [file join $repo_dir rtl core]] [current_fileset]
} else {
    set_property include_dirs [list [file join $repo_dir rtl core]] [current_fileset]
}

if {$soc_kind eq "rv64"} {
    read_sv $repo_dir rtl/core/cpu_defs.svh
    read_sv $repo_dir rtl/core64/cpu64_defs.svh
    read_sv $repo_dir rtl/core64/alu64.sv
    read_sv $repo_dir rtl/core64/regfile64.sv
    read_sv $repo_dir rtl/core64/fregfile64.sv
    read_sv $repo_dir rtl/core64/zx64_muldiv_unit.sv
    read_sv $repo_dir rtl/core64/zx64_core.sv
    read_sv $repo_dir rtl/core64/zx64_core5.sv
    read_sv $repo_dir rtl/periph/simple_ram64.sv
    read_sv $repo_dir rtl/periph/mmio_uart_tx.sv
    read_sv $repo_dir rtl/periph/mmio_timer.sv
    read_sv $repo_dir rtl/periph/mmio_virtio_blk_regs.sv
    read_sv $repo_dir rtl/periph/mmio_virtio_input_regs.sv
    read_sv $repo_dir rtl/periph/mmio_plic_min.sv
    read_sv $repo_dir rtl/bus/axi4_master_bridge.sv
    read_sv $repo_dir rtl/soc/zx64_soc.sv
    read_v  $repo_dir rtl/soc/zx64_soc_bd.v
} else {
    read_sv $repo_dir rtl/core/cpu_defs.svh
    read_sv $repo_dir rtl/core/alu.sv
    read_sv $repo_dir rtl/core/regfile.sv
    read_sv $repo_dir rtl/core/zx32_core.sv
    read_sv $repo_dir rtl/periph/simple_ram.sv
    read_sv $repo_dir rtl/periph/mmio_uart_tx.sv
    read_sv $repo_dir rtl/periph/mmio_timer.sv
    read_sv $repo_dir rtl/periph/mmio_irqctrl.sv
    read_sv $repo_dir rtl/periph/mmio_gpu_fill.sv
    read_sv $repo_dir rtl/periph/axis_scratchpad.sv
    read_sv $repo_dir rtl/bus/datamover_ctrl.sv
    read_sv $repo_dir rtl/bus/axi4_master_bridge.sv
    read_sv $repo_dir rtl/soc/zx32_soc.sv
    read_v  $repo_dir rtl/soc/zx32_soc_bd.v
}

read_sv $repo_dir rtl/video/video_timing.sv
read_sv $repo_dir rtl/video/tmds_encoder.sv
read_sv $repo_dir rtl/video/hdmi_test_pattern.sv
read_sv $repo_dir rtl/video/hdmi_test_pattern_core.sv
read_sv $repo_dir rtl/video/hdmi_console_ram.sv
read_sv $repo_dir rtl/video/hdmi_text_console_core.sv
read_sv $repo_dir rtl/video/mmio_display_ctrl.sv
read_sv $repo_dir rtl/video/mmio_lcd_display_ctrl.sv
read_sv $repo_dir rtl/video/lcd_text_console_core.sv
read_sv $repo_dir rtl/video/hdmi_tmds_oserdes_xilinx.sv
read_v  $repo_dir rtl/video/hdmi_test_pattern_top_xilinx.v
read_v  $repo_dir rtl/video/lcd_console_top_xilinx.v
read_sv $repo_dir rtl/periph/axi_lite_bringup_regs.sv
read_v  $repo_dir rtl/periph/axi_lite_bringup_regs_bd.v
update_compile_order -fileset sources_1

create_bd_design zynq_cpu_system

create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set_property -dict [load_user_ps7_props $old_ps7_xci] [get_bd_cells processing_system7_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_75M

create_bd_cell -type module -reference $soc_ref $soc_cell
if {$soc_kind eq "rv64"} {
    set_property -dict [list CONFIG.ENABLE_FPU $rv64_enable_fpu] [get_bd_cells $soc_cell]
}
create_bd_cell -type module -reference axi_lite_bringup_regs_bd bringup_regs_0
create_bd_cell -type module -reference hdmi_test_pattern_top_xilinx hdmi_test_0
create_bd_cell -type module -reference lcd_console_top_xilinx lcd_console_0

if {$use_datamover} {
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
}

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* axi_ctrl_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells axi_ctrl_smc]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_hp0_intercon
if {$use_datamover} {
    set_property -dict [list CONFIG.NUM_SI {3} CONFIG.NUM_MI {1}] [get_bd_cells axi_hp0_intercon]
} else {
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_hp0_intercon]
}

make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/DDR]
make_bd_intf_pins_external [get_bd_intf_pins processing_system7_0/FIXED_IO]

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/S_AXI_HP0_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins rst_ps7_0_75M/slowest_sync_clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins $soc_cell/clk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins hdmi_test_0/clk_75mhz]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins lcd_console_0/clk_75mhz]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins $soc_cell/S_AXI_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins bringup_regs_0/S_AXI_ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_ctrl_smc/aclk]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/ACLK]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S00_ACLK]
if {$use_datamover} {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S01_ACLK]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/S02_ACLK]
}
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_hp0_intercon/M00_ACLK]
if {$use_datamover} {
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axi_mm2s_aclk]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axi_s2mm_aclk]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axis_mm2s_cmdsts_aclk]
    connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins axi_datamover_0/m_axis_s2mm_cmdsts_awclk]
}

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_ps7_0_75M/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins $soc_cell/rst_n]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins hdmi_test_0/rst_n]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins lcd_console_0/rst_n]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins $soc_cell/S_AXI_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins bringup_regs_0/S_AXI_ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_ctrl_smc/aresetn]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/ARESETN]
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S00_ARESETN]
if {$use_datamover} {
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S01_ARESETN]
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/S02_ARESETN]
}
connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_hp0_intercon/M00_ARESETN]
if {$use_datamover} {
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axi_mm2s_aresetn]
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axi_s2mm_aresetn]
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axis_mm2s_cmdsts_aresetn]
    connect_bd_net [get_bd_pins rst_ps7_0_75M/peripheral_aresetn] [get_bd_pins axi_datamover_0/m_axis_s2mm_cmdsts_aresetn]
}

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_smc/M00_AXI] [get_bd_intf_pins bringup_regs_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_ctrl_smc/M01_AXI] [get_bd_intf_pins $soc_cell/S_AXI]

if {$use_datamover} {
    connect_bd_intf_net [get_bd_intf_pins axi_datamover_0/M_AXI_MM2S] [get_bd_intf_pins axi_hp0_intercon/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins axi_datamover_0/M_AXI_S2MM] [get_bd_intf_pins axi_hp0_intercon/S01_AXI]
    connect_bd_intf_net [get_bd_intf_pins $soc_cell/M_AXI_DDR] [get_bd_intf_pins axi_hp0_intercon/S02_AXI]
} else {
    connect_bd_intf_net [get_bd_intf_pins $soc_cell/M_AXI_DDR] [get_bd_intf_pins axi_hp0_intercon/S00_AXI]
}
connect_bd_intf_net [get_bd_intf_pins axi_hp0_intercon/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

if {$use_datamover} {
    connect_bd_net [get_bd_pins $soc_cell/dm_mm2s_cmd_valid] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tvalid]
    connect_bd_net [get_bd_pins $soc_cell/dm_mm2s_cmd_ready] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tready]
    connect_bd_net [get_bd_pins $soc_cell/dm_mm2s_cmd_data] [get_bd_pins axi_datamover_0/s_axis_mm2s_cmd_tdata]
    connect_bd_net [get_bd_pins $soc_cell/dm_s2mm_cmd_valid] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tvalid]
    connect_bd_net [get_bd_pins $soc_cell/dm_s2mm_cmd_ready] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tready]
    connect_bd_net [get_bd_pins $soc_cell/dm_s2mm_cmd_data] [get_bd_pins axi_datamover_0/s_axis_s2mm_cmd_tdata]

    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tvalid] [get_bd_pins $soc_cell/dm_mm2s_sts_valid]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tready] [get_bd_pins $soc_cell/dm_mm2s_sts_ready]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_sts_tdata] [get_bd_pins $soc_cell/dm_mm2s_sts_data]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tvalid] [get_bd_pins $soc_cell/dm_s2mm_sts_valid]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tready] [get_bd_pins $soc_cell/dm_s2mm_sts_ready]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_s2mm_sts_tdata] [get_bd_pins $soc_cell/dm_s2mm_sts_data]

    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tdata] [get_bd_pins $soc_cell/dm_m_axis_mm2s_tdata]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tkeep] [get_bd_pins $soc_cell/dm_m_axis_mm2s_tkeep]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tlast] [get_bd_pins $soc_cell/dm_m_axis_mm2s_tlast]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tvalid] [get_bd_pins $soc_cell/dm_m_axis_mm2s_tvalid]
    connect_bd_net [get_bd_pins axi_datamover_0/m_axis_mm2s_tready] [get_bd_pins $soc_cell/dm_m_axis_mm2s_tready]
    connect_bd_net [get_bd_pins $soc_cell/dm_s_axis_s2mm_tdata] [get_bd_pins axi_datamover_0/s_axis_s2mm_tdata]
    connect_bd_net [get_bd_pins $soc_cell/dm_s_axis_s2mm_tkeep] [get_bd_pins axi_datamover_0/s_axis_s2mm_tkeep]
    connect_bd_net [get_bd_pins $soc_cell/dm_s_axis_s2mm_tlast] [get_bd_pins axi_datamover_0/s_axis_s2mm_tlast]
    connect_bd_net [get_bd_pins $soc_cell/dm_s_axis_s2mm_tvalid] [get_bd_pins axi_datamover_0/s_axis_s2mm_tvalid]
    connect_bd_net [get_bd_pins $soc_cell/dm_s_axis_s2mm_tready] [get_bd_pins axi_datamover_0/s_axis_s2mm_tready]
} else {
    create_const_net_if_present rv64_dm_const_1b0 1 0 [list \
        $soc_cell/dm_mm2s_cmd_ready \
        $soc_cell/dm_mm2s_sts_valid \
        $soc_cell/dm_s2mm_cmd_ready \
        $soc_cell/dm_s2mm_sts_valid \
        $soc_cell/dm_m_axis_mm2s_tlast \
        $soc_cell/dm_m_axis_mm2s_tvalid \
        $soc_cell/dm_s_axis_s2mm_tready \
    ]
    create_const_net_if_present rv64_dm_const_8b0 8 0 [list \
        $soc_cell/dm_mm2s_sts_data \
        $soc_cell/dm_s2mm_sts_data \
    ]
    create_const_net_if_present rv64_dm_const_32b0 32 0 [list $soc_cell/dm_m_axis_mm2s_tdata]
    create_const_net_if_present rv64_dm_const_4b0 4 0 [list $soc_cell/dm_m_axis_mm2s_tkeep]
}

if {$soc_has_display_ports} {
    connect_bd_net [get_bd_pins $soc_cell/display_enable] [get_bd_pins hdmi_test_0/display_enable]
    connect_bd_net [get_bd_pins $soc_cell/display_test_pattern_enable] [get_bd_pins hdmi_test_0/test_pattern_enable]
    connect_bd_net [get_bd_pins $soc_cell/display_text_enable] [get_bd_pins hdmi_test_0/text_enable]
    connect_bd_net [get_bd_pins $soc_cell/display_text_clear] [get_bd_pins hdmi_test_0/text_clear]
    connect_bd_net [get_bd_pins $soc_cell/display_mode] [get_bd_pins hdmi_test_0/mode]
    connect_bd_net [get_bd_pins $soc_cell/display_bg_color] [get_bd_pins hdmi_test_0/bg_color]
    connect_bd_net [get_bd_pins $soc_cell/display_text_we] [get_bd_pins hdmi_test_0/text_we]
    connect_bd_net [get_bd_pins $soc_cell/display_text_word_addr] [get_bd_pins hdmi_test_0/text_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/display_text_wdata] [get_bd_pins hdmi_test_0/text_wdata]
    connect_bd_net [get_bd_pins $soc_cell/display_text_wstrb] [get_bd_pins hdmi_test_0/text_wstrb]
    connect_bd_net [get_bd_pins $soc_cell/display_attr_we] [get_bd_pins hdmi_test_0/attr_we]
    connect_bd_net [get_bd_pins $soc_cell/display_attr_word_addr] [get_bd_pins hdmi_test_0/attr_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/display_attr_wdata] [get_bd_pins hdmi_test_0/attr_wdata]
    connect_bd_net [get_bd_pins $soc_cell/display_attr_wstrb] [get_bd_pins hdmi_test_0/attr_wstrb]
    connect_bd_net [get_bd_pins $soc_cell/display_font_we] [get_bd_pins hdmi_test_0/font_we]
    connect_bd_net [get_bd_pins $soc_cell/display_font_word_addr] [get_bd_pins hdmi_test_0/font_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/display_font_wdata] [get_bd_pins hdmi_test_0/font_wdata]
    connect_bd_net [get_bd_pins $soc_cell/display_font_wstrb] [get_bd_pins hdmi_test_0/font_wstrb]

    # LCD console on J20: text mirror of the HDMI console (display2 window)
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_enable] [get_bd_pins lcd_console_0/lcd_display_enable]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_bg_color] [get_bd_pins lcd_console_0/lcd_display_bg_color]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_enable] [get_bd_pins lcd_console_0/lcd_display_text_enable]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_clear] [get_bd_pins lcd_console_0/lcd_display_text_clear]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_we] [get_bd_pins lcd_console_0/lcd_display_text_we]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_word_addr] [get_bd_pins lcd_console_0/lcd_display_text_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_wdata] [get_bd_pins lcd_console_0/lcd_display_text_wdata]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_text_wstrb] [get_bd_pins lcd_console_0/lcd_display_text_wstrb]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_attr_we] [get_bd_pins lcd_console_0/lcd_display_attr_we]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_attr_word_addr] [get_bd_pins lcd_console_0/lcd_display_attr_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_attr_wdata] [get_bd_pins lcd_console_0/lcd_display_attr_wdata]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_attr_wstrb] [get_bd_pins lcd_console_0/lcd_display_attr_wstrb]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_font_we] [get_bd_pins lcd_console_0/lcd_display_font_we]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_font_word_addr] [get_bd_pins lcd_console_0/lcd_display_font_word_addr]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_font_wdata] [get_bd_pins lcd_console_0/lcd_display_font_wdata]
    connect_bd_net [get_bd_pins $soc_cell/lcd_display_font_wstrb] [get_bd_pins lcd_console_0/lcd_display_font_wstrb]
} else {
    puts "ZYNQ_CPU_SOC=$soc_kind: $soc_ref has no HDMI text/display ports; driving HDMI with fixed test-pattern defaults"
    create_const_net hdmi_const_1b1 1 1 [list hdmi_test_0/display_enable hdmi_test_0/test_pattern_enable]
    create_const_net hdmi_const_1b0 1 0 [list \
        hdmi_test_0/text_enable \
        hdmi_test_0/text_clear \
        hdmi_test_0/text_we \
        hdmi_test_0/attr_we \
        hdmi_test_0/font_we \
    ]
    create_const_net hdmi_const_mode 2 2 [list hdmi_test_0/mode]
    create_const_net hdmi_const_32b0 32 0 [list hdmi_test_0/bg_color hdmi_test_0/text_wdata hdmi_test_0/attr_wdata hdmi_test_0/font_wdata]
    create_const_net hdmi_const_12b0 12 0 [list hdmi_test_0/text_word_addr]
    create_const_net hdmi_const_11b0 11 0 [list hdmi_test_0/attr_word_addr]
    create_const_net hdmi_const_9b0 9 0 [list hdmi_test_0/font_word_addr]
    create_const_net hdmi_const_4b0 4 0 [list hdmi_test_0/text_wstrb hdmi_test_0/attr_wstrb hdmi_test_0/font_wstrb]
    # LCD console idle on rv64: keep DCLK/MMCM running, console disabled
    create_const_net lcd_const_1b1 1 1 [list lcd_console_0/lcd_display_enable lcd_console_0/lcd_display_text_enable]
    create_const_net lcd_const_1b0 1 0 [list \
        lcd_console_0/lcd_display_text_clear \
        lcd_console_0/lcd_display_text_we \
        lcd_console_0/lcd_display_attr_we \
        lcd_console_0/lcd_display_font_we \
    ]
    create_const_net lcd_const_32b0 32 0 [list lcd_console_0/lcd_display_bg_color lcd_console_0/lcd_display_text_wdata lcd_console_0/lcd_display_attr_wdata lcd_console_0/lcd_display_font_wdata]
    create_const_net lcd_const_8b0 8 0 [list lcd_console_0/lcd_display_text_word_addr]
    create_const_net lcd_const_7b0 7 0 [list lcd_console_0/lcd_display_attr_word_addr]
    create_const_net lcd_const_9b0 9 0 [list lcd_console_0/lcd_display_font_word_addr]
    create_const_net lcd_const_4b0 4 0 [list lcd_console_0/lcd_display_text_wstrb lcd_console_0/lcd_display_attr_wstrb lcd_console_0/lcd_display_font_wstrb]
}


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

# LCD console panel pins (J20)
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_R]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_G]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_B]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_DCLK]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_HS]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_VS]
make_bd_pins_external [get_bd_pins lcd_console_0/LCD_DE]

set_property name LCD_R [get_bd_ports LCD_R_0]
set_property name LCD_G [get_bd_ports LCD_G_0]
set_property name LCD_B [get_bd_ports LCD_B_0]
set_property name LCD_DCLK [get_bd_ports LCD_DCLK_0]
set_property name LCD_HS [get_bd_ports LCD_HS_0]
set_property name LCD_VS [get_bd_ports LCD_VS_0]
set_property name LCD_DE [get_bd_ports LCD_DE_0]

assign_bd_address
set_property offset 0x43C00000 [get_bd_addr_segs {processing_system7_0/Data/SEG_bringup_regs_0_reg0}]
set_property range 64K [get_bd_addr_segs {processing_system7_0/Data/SEG_bringup_regs_0_reg0}]
set soc_seg [get_bd_addr_segs "processing_system7_0/Data/SEG_${soc_cell}_reg0"]
if {$soc_kind eq "rv32"} {
    set_property offset 0x43C20000 $soc_seg
    set_property range 128K $soc_seg
} else {
    # rv64 has no display2 window; keep the same base as rv32 so one
    # ps_uart_probe.h (ZYNQ_CPU_DMA_BASE) serves both bitstreams.
    set_property offset 0x43C20000 $soc_seg
    set_property range 64K $soc_seg
}

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
read_xdc [file join $repo_dir constraints ax7020_lcd_j20.xdc]
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
# Vivado 2025.2: after -to_step opt_design, PROGRESS/STATUS reflect the *next*
# unstarted step (e.g. 33.33% / "Not started place_design"), so they cannot be
# used as completion evidence. The opt checkpoint file is the ground truth.
set opt_dcp [file join $build_dir zynq_cpu_hw.runs impl_1 zynq_cpu_system_wrapper_opt.dcp]
if {![file exists $opt_dcp]} {
    launch_runs impl_1 -to_step opt_design -jobs 8
    wait_on_run impl_1
}
if {![file exists $opt_dcp]} {
    error "impl_1 opt_design did not produce $opt_dcp"
}

# Vivado 2025.2: open_run on a run paused at a -to_step boundary fails
# ("Run has not been launched"); open the opt checkpoint file directly.
open_checkpoint $opt_dcp
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir zynq_cpu_system_utilization_opt_hier.rpt]
close_design

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
# Same 2025.2 caveat: the bitstream file is the completion evidence.
set bit_file [file join $build_dir zynq_cpu_hw.runs impl_1 zynq_cpu_system_wrapper.bit]
if {![file exists $bit_file]} {
    error "impl_1 did not produce $bit_file; STATUS: [get_property STATUS [get_runs impl_1]]"
}


open_run impl_1
report_utilization -file [file join $report_dir zynq_cpu_system_utilization.rpt]
report_timing_summary -file [file join $report_dir zynq_cpu_system_timing_summary.rpt]
write_hw_platform -fixed -include_bit -force -file [file join $build_dir zynq_cpu_system_wrapper.xsa]
