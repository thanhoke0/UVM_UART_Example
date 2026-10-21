`timescale 1ns/10ps
`include "uvm_pkg.sv"
`include "uvm_macros.svh"
`include "uart_interface.sv"
`include "cpu_intr_interface.sv"
package uart_config_check;
import uvm_pkg::*;
`include "uart_host_config.sv"
endpackage
