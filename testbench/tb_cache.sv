`timescale 1ns/1ps
`default_nettype none
module tb;
  // clock/reset
  logic clk=0; always #5 clk = ~clk; // 100 MHz
  logic rst=1;

  // AXI-lite read subset
  logic [31:0] ar_addr;
  logic        ar_valid, ar_ready;
  logic [31:0] r_data;
  logic [1:0]  r_resp;
  logic        r_valid, r_ready;

  // DUT
  cache dut(
    .clk(clk), .rst(rst),
    .cpu_ar_addr(ar_addr), .cpu_ar_valid(ar_valid), .cpu_ar_ready(ar_ready),
    .cpu_r_data(r_data),   .cpu_r_resp(r_resp),
    .cpu_r_valid(r_valid), .cpu_r_ready(r_ready)
  );

  // waves
  initial begin
    $dumpfile("sim/waves.vcd");
    $dumpvars(0, tb);
  end

  // defaults
  initial begin
    ar_addr  = '0;
    ar_valid = 0;
    r_ready  = 0;
  end

  // stimulus: fixed timeline, guaranteed finish
  initial begin
    repeat (5) @(posedge clk);  // hold reset
    rst = 0;

    // present AR for one beat
    @(posedge clk);
    ar_addr  <= 32'h0000_0040;
    ar_valid <= 1;

    // accept AR (DUT pulses ar_ready)
    @(posedge clk);
    ar_valid <= 0;

    // be ready to take data for a few cycles
    r_ready <= 1;
    repeat (4) @(posedge clk);
    r_ready <= 0;

    // small pause and finish regardless
    repeat (5) @(posedge clk);
    $display("[%0t] DONE. r_valid=%0d r_data=0x%08h", $time, r_valid, r_data);
    $finish;
  end

  // watchdog (use $finish, not $fatal)
  initial begin
    #2000;  // 2 us max
    $display("[TIMEOUT] Ending sim.");
    $finish;
  end
endmodule
`default_nettype wire
