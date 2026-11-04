# Initial clock / CDC constraints for hdmi_player_board_top, TD 6.2.
# Memory PLL: 100 MHz controller, 100 MHz forwarded clock at 306 degrees.
create_clock -name SYS_CLK -period 20.000 -waveform {0.000 10.000} [get_ports {SYS_CLK}]

# Read real PLL parameters rather than copying 25.175 MHz from old documents.
# Expected: memory 100/100/100 MHz (0/0/306), display 125/25 MHz (0/0).
derive_clocks

# External reset is asynchronous. KEY_LOAD_N is captured only by key_meta;
# key_meta -> key_sync and all subsequent debounce logic stay timed.
set_false_path -from [get_ports {Reset_n}]
set_false_path -from [get_ports {KEY_LOAD_N}]
set_false_path -from [get_ports {KEY_PREV_N KEY_NEXT_N KEY_AUTO_N KEY_SPECTRUM_N}]
set_false_path -from [get_ports {SW_MUTE_N}]
set_false_path -from [get_ports {key_img[*]}]
# Main exposes the display key bus; captured by the same first key synchronizer.
set_false_path -from [get_ports {key_in[*]}]

# Bound only the actual crossing nets to the destination clock. Selecting
# packed register cells can also select a neighbour (including sync stage 2).
# A path through the source net stops at the first destination register;
# later synchronizer stages retain ordinary setup AND hold checks.
# The original 8 ns bound is stricter than the 10 ns fastest FIFO clock.
set_max_delay -datapath_only -through [get_nets -hier {*u_memory/dut/wr_gray_ptr*}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_memory/dut/rd_gray_ptr*}] -to [get_clocks {SYS_CLK}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_display_fifo/u_fifo/wr_gray_ptr*}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_display_fifo/u_fifo/rd_gray_ptr*}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000

# Held descriptor payload crosses into memory; request and acknowledge
# toggles have separate synchronizers. Limit their source nets, not cells.
set_max_delay -datapath_only -through [get_nets -hier {*ucdc/req_toggle}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*ucdc/ack_toggle *uut/frame_write_done}] -to [get_clocks {SYS_CLK}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*ucdc/base_addr_reg* *ucdc/width_reg* *ucdc/height_reg* *ucdc/top_down_reg}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000

# Do not use a blanket asynchronous clock group: it would hide the FIFO
# Gray-bus route limits and the related pixel/5x serializer timing.

# External SPI input/output delays and HDMI electrical/board-skew budgets
# require interface sign-off. No guessed numeric I/O delays are inserted.
# Review unconstrained-I/O reports before claiming complete timing closure.

# Only asynchronous control pins of reset-release synchronizers are excepted.
# Their D-stage transfers and downstream reset recovery/removal remain timed.
set_false_path -to [get_pins -hier {*reset_release_reg*.sr *pix_release_reg*.sr *mem_release_reg*.sr}]

# The encrypted controller qualifies read data on the second controller edge
# following the SDRAM data-launch edge. This is a pipelined input latency,
# not a relaxation of application logic or SDRAM writes. Preserve hold checks.
set_multicycle_path -setup -from [get_pins -hier {*u_sdram_phy.dq*}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 2
set_multicycle_path -hold -from [get_pins -hier {*u_sdram_phy.dq*}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 1

# TD's packaged-SDRAM model assumes tAC(max)=5.0 ns. Reserve another
# 0.5 ns for the 5.5 ns reference-model/older EM638325 limit, in addition
# to the tool's 0.1 ns allowance. TD supports per-clock uncertainty only,
# so apply this conservative budget to all memory capture paths.
set_clock_uncertainty -setup 0.600 [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}]

# Audio mailbox: payload is held until the three-stage request/ack handshake.
# Limit just the crossing nets; the following synchronizer stages stay timed.
set_max_delay -datapath_only -through [get_nets -hier {*u_audio_fifo/wr_tog *u_audio_fifo/mailbox*}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_audio_fifo/rd_tog}] -to [get_clocks {SYS_CLK}] 8.000
# Frame-buffer handshake and status levels, all captured by existing 2/3 stages.
set_max_delay -datapath_only -through [get_nets -hier {*u_frame_buffers/abort_ack *u_frame_buffers/back_bank *u_frame_buffers/available_mem}] -to [get_clocks {SYS_CLK}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_frame_buffers/abort_toggle}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000
# Existing initialization status and new audio sink-ready status, first stage only.
set_max_delay -datapath_only -through [get_nets -hier {*u_memory/mem_reset_n *u_memory/mem_reset_release* *u_memory/Sdr_init_done}] -to [get_clocks {SYS_CLK}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_display/pix_reset_n}] -to [get_clocks {SYS_CLK}] 8.000

# Frame-rate Gray fade level, first pixel synchronizer stage only.
set_max_delay -datapath_only -through [get_nets -hier {*u_memory/fade_gray*}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000

# Registered WAV playing status to the first pixel-domain synchronizer.
set_max_delay -datapath_only -through [get_nets -hier {*player/playing}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000

# Existing two-stage display-status synchronizers: first SYS_CLK stage only.
set_max_delay -datapath_only -through [get_nets -hier {*u_display_fifo/underflow *u_display_fifo/frame_ready}] -to [get_clocks {SYS_CLK}] 8.000

# read_error_sync[1] is the other input of the synchronized display error level.
set_max_delay -datapath_only -through [get_nets -hier {*u_memory/read_error_sync*}] -to [get_clocks {SYS_CLK}] 8.000

# Subtitle descriptor payload shares the existing held request/ack crossing.
set_max_delay -datapath_only -through [get_nets -hier {*ucdc/user_reg*}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000
# Front descriptor mailbox is held until capture/ack, not a free-running bus.
set_max_delay -datapath_only -through [get_nets -hier {*u_subtitle_info/held* *u_subtitle_info/request}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_subtitle_info/ack}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000

# TXT glyph-cache banks are filled before a held descriptor is published.
# Acknowledge only after the pixel side swaps banks at the frame boundary.
set_max_delay -datapath_only -through [get_nets -hier {*u_text_cache/held* *u_text_cache/request}] -to [get_clocks {u_player/u_display/u_clk_wize/pll_inst.clkc[1]}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_text_cache/ack}] -to [get_clocks {SYS_CLK}] 8.000

# AV scheduling: single-bit first-stage synchronizers, all later stages timed.
set_max_delay -datapath_only -through [get_nets -hier {*u_display/transition_toggle *u_display/pause_request *u_display/sw_mute}] -to [get_clocks {SYS_CLK}] 8.000
set_max_delay -datapath_only -through [get_nets -hier {*u_player/presentation_ready}] -to [get_clocks {u_player/u_memory/u0_clk/pll_inst.clkc[1]}] 8.000
