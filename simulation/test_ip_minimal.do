vlib work

vlog  "../sources/ip_minimal.v"
vlog  "test_ip_minimal.v"

vsim -voptargs="+acc" -t 1ps -lib work work.test_ip_minimal

do {test_ip_minimal_wave.fdo}

view wave
view structure
view signals

run -all
