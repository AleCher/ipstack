vlib work

vlog  "../sources/ip_minimal.v"
vlog  "../implementation/eth_fifo.v"
vlog  "test_ip_minimal.v"

vsim -voptargs="+acc" -t 1ps  -L xilinxcorelib_ver -L unisims_ver -L secureip -lib work work.test_ip_minimal

do {test_ip_minimal_wave.fdo}

view wave
view structure
view signals

run 100000ns
