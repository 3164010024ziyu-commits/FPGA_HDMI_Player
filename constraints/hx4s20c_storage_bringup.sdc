# Initial system-clock constraint, not a complete SD external-I/O timing sign-off.
# SPI SCK has startup/read rates and inter-byte gaps; do not cut MISO paths.
create_clock -name sys_clk -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
