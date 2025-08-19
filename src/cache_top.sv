// cache_top.sv — glue using ONLY signals present in BOTH modules
`timescale 1ns/1ps
module cache_top #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int LINE_BYTES = 16,
  parameter int NUM_LINES  = 32
)(
  // shared top ports
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic                    core_req_we,
  input  logic [ADDR_WIDTH-1:0]   core_req_addr,
  input  logic [DATA_WIDTH-1:0]   core_req_wdata,
  input  logic [DATA_WIDTH/8-1:0] core_req_wstrb,

  output logic                    core_req_ready,
  output logic                    core_resp_valid, 
  output logic                    core_resp_is_write,
  output logic [DATA_WIDTH-1:0]   core_resp_rdata,
  output logic [1:0]              core_resp_resp
);

  // sizing for compare ports
  localparam int OFFSET_BITS = $clog2(LINE_BYTES);
  localparam int INDEX_BITS  = $clog2(NUM_LINES);
  localparam int TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

  // ctrl <-> dp overlap only
  logic                        req_tag_cmp;        // FSM -> DP (maps to dp.cmp_tag_req)
  logic                        req_tag_cmp_resp;   // DP  -> FSM
  logic                        req_tag_cmp_valid;  // DP  -> FSM

  // =================== Datapath ===================
  cache_dp #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .LINE_BYTES (LINE_BYTES),
    .NUM_LINES  (NUM_LINES)
  ) u_dp (
    .clk,
    .rst_n,

    // common core-side inputs
    .core_req_we,
    .core_req_addr,
    .core_req_wdata,
    .core_req_wstrb,

    // ctrl <-> dp compare handshake
    .cmp_tag_req       (req_tag_cmp),
    .req_tag_cmp_resp  (req_tag_cmp_resp),
    .req_tag_cmp_valid (req_tag_cmp_valid)
  );

  // =================== Control FSM ===================
  cache_fsm #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .LINE_BYTES (LINE_BYTES),
    .NUM_LINES  (NUM_LINES)
  ) u_fsm (
    .clk,
    .rst_n,

    // common core-side inputs
    .core_req_we,
    .core_req_addr,
    .core_req_wdata,
    .core_req_wstrb,

    // top-level outputs come from FSM (single driver)
    .core_req_ready     (core_req_ready),
    .core_resp_valid    (core_resp_valid),
    .core_resp_is_write (core_resp_is_write),
    .core_resp_rdata    (core_resp_rdata),
    .core_resp_resp     (core_resp_resp),

    // ctrl <-> dp compare handshake
    .req_tag_cmp_resp   (req_tag_cmp_resp),
    .req_tag_cmp_valid  (req_tag_cmp_valid),
    .req_tag_cmp        (req_tag_cmp),
  );

endmodule
