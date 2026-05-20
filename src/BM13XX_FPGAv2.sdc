//Copyright (C)2014-2026 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Tool Version: V1.9.10.03 Education (64-bit) 
//Created Time: 2026-05-18 23:18:52
create_clock -name clk_50m -period 20 -waveform {0 10} [get_ports {clk_50m}]
