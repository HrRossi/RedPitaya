

#*******************************************************************************
# Simple script to control vivado project via command line
#
# It takes two argument
#   clean   cleans project files
#   build   build all output files

set current_vivado_version [version -short]


#*******************************************************************************
# Open project

if { [string first 2013.3 $current_vivado_version] == -1 } {
   open_project ./vivado2015_4/red_pitaya.xpr
} else {
   open_project ./vivado/red_pitaya.xpr
}


#*******************************************************************************
# Update sources

update_compile_order -fileset sources_1


##*******************************************************************************
## Clean project

if {[lindex $argv 0] == "clean"} {
   ## clean implementation
   reset_run impl_1

   ## clean synthesis
   reset_run synth_1

   ## clean PS project configuration
   if { [string first 2013.3 $current_vivado_version] == -1 } {
      reset_target all [get_files  ./vivado2015_4/red_pitaya.srcs/sources_1/bd/system/system.bd]
   } else {
      reset_target all [get_files  ./vivado/red_pitaya.srcs/sources_1/bd/system/system.bd]
   }
}


##*******************************************************************************
## Make output files

if {[lindex $argv 0] == "build"} {

   ## export PS configuration
   if { [string first 2013.3 $current_vivado_version] == -1 } {
      generate_target all [get_files  ./vivado2015_4/red_pitaya.srcs/sources_1/bd/system/system.bd]
      open_bd_design ./vivado2015_4/red_pitaya.srcs/sources_1/bd/system/system.bd
      file mkdir ./vivado/red_pitaya.sdk/SDK/SDK_Export/hw/
      write_hwdef -file ./vivado/red_pitaya.sdk/SDK/SDK_Export/hw/system.hwdef
   } else {
      generate_target all [get_files  ./vivado/red_pitaya.srcs/sources_1/bd/system/system.bd]
      open_bd_design ./vivado/red_pitaya.srcs/sources_1/bd/system/system.bd
      export_hardware [get_files ./vivado/red_pitaya.srcs/sources_1/bd/system/system.bd]
   }
   close_bd_design system

   ## do synthesis
   launch_runs synth_1
   wait_on_run synth_1

   ## do implementation
   launch_runs impl_1
   wait_on_run impl_1

   ## make bit file
   launch_runs impl_1 -to_step write_bitstream
   wait_on_run impl_1
}


#*******************************************************************************
# Close opened project

close_project


exit

