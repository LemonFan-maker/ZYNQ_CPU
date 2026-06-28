set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $repo_dir build vivado_synth]
set report_dir [file join $build_dir reports]

file mkdir $build_dir
file mkdir $report_dir

read_verilog -sv [file join $repo_dir rtl core alu.sv]
read_verilog -sv [file join $repo_dir rtl core regfile.sv]
read_verilog -sv [file join $repo_dir rtl core zx32_core.sv]
read_verilog -sv [file join $repo_dir rtl periph simple_ram.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_uart_tx.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_timer.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_irqctrl.sv]
read_verilog -sv [file join $repo_dir rtl periph mmio_gpu_fill.sv]
read_verilog -sv [file join $repo_dir rtl video mmio_display_ctrl.sv]
read_verilog -sv [file join $repo_dir rtl periph axis_scratchpad.sv]
read_verilog -sv [file join $repo_dir rtl bus datamover_ctrl.sv]
read_verilog -sv [file join $repo_dir rtl bus axi4_master_bridge.sv]
read_verilog -sv [file join $repo_dir rtl soc zx32_soc.sv]

synth_design -top zx32_soc -part xc7z020clg400-2

report_utilization -file [file join $report_dir zx32_soc_utilization.rpt]
report_timing_summary -file [file join $report_dir zx32_soc_timing_summary.rpt]
write_checkpoint -force [file join $build_dir zx32_soc_synth.dcp]
