`timescale 1ns/1ps

module cpu_translator_tb_read;
  logic clk, rst_n;

  // AXI4-Lite Read Address Channel
  logic [31:0] s_araddr;
  logic        s_arvalid;
  logic        s_arready;

  // AXI4-Lite Read Data Channel
  logic [31:0] s_rdata;
  logic  [1:0] s_rresp;
  logic        s_rvalid;
  logic        s_rready;

  // Core side simple port
  logic        core_req_valid;
  logic        core_req_ready;
  logic [31:0] core_req_addr;
  logic        core_resp_valid;
  logic [31:0] core_resp_data;

  // DUT
  cpu_translator dut (
    .clk(clk),
    .rst_n(rst_n),

    // AXI slave (read only here)
    .s_araddr(s_araddr),
    .s_arvalid(s_arvalid),
    .s_arready(s_arready),
    .s_rdata(s_rdata),
    .s_rresp(s_rresp),
    .s_rvalid(s_rvalid),
    .s_rready(s_rready),

    // Core port
    .core_req_valid(core_req_valid),
    .core_req_ready(core_req_ready),
    .core_req_addr(core_req_addr),
    .core_resp_valid(core_resp_valid),
    .core_resp_data(core_resp_data)
  );

  // Clock
  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    s_araddr  = 0;
    s_arvalid = 0;
    s_rready  = 0;
    core_req_ready = 0;
    core_resp_valid = 0;
    core_resp_data  = 32'hDEADBEEF;

    #20 rst_n = 1;

    // Cycle 1: issue AR=0x5, arvalid=1
    @(posedge clk);
    s_araddr  <= 32'h5;
    s_arvalid <= 1;
    s_rready  <= 1;
    core_req_ready <= 1; // core accepts immediately

    // Hold arvalid for 2 cycles
    repeat (2) @(posedge clk);

    // Drop valid after handshake
    s_arvalid <= 0;

    // Wait a few cycles then core responds
    repeat (3) @(posedge clk);
    core_resp_valid <= 1;

    @(posedge clk);
    core_resp_valid <= 0;

    // Finish
    repeat (5) @(posedge clk);
    $finish;
  end
endmodule
