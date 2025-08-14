`timescale 1ns/1ps
module core_translator_tb;

  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;

  // ===== Clock / Reset =====
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk; // 100 MHz

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
  end

  // ===== DUT I/O (AXI slave side) =====
  logic [ADDR_WIDTH-1:0] s_awaddr; logic s_awvalid, s_awready;
  logic [DATA_WIDTH-1:0] s_wdata;  logic [DATA_WIDTH/8-1:0] s_wstrb; logic s_wvalid, s_wready;
  logic [1:0] s_bresp; logic s_bvalid, s_bready;
  logic [ADDR_WIDTH-1:0] s_araddr; logic s_arvalid, s_arready;
  logic [DATA_WIDTH-1:0] s_rdata;  logic [1:0] s_rresp; logic s_rvalid, s_rready;

  // ===== Core side =====
  logic core_req_valid, core_req_ready, core_req_we;
  logic [ADDR_WIDTH-1:0] core_req_addr;
  logic [DATA_WIDTH-1:0] core_req_wdata;
  logic [DATA_WIDTH/8-1:0] core_req_wstrb;
  logic core_resp_valid, core_resp_is_write;
  logic [DATA_WIDTH-1:0] core_resp_rdata;
  logic [1:0] core_resp_resp;

  // ===== DEBUG =====
  logic [2:0] dbg_w_state;
  logic [1:0] dbg_r_state;

  // ===== DUT =====
  cpu_translator #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
    .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rdata(s_rdata), .s_rresp(s_rresp), .s_rvalid(s_rvalid), .s_rready(s_rready),
    .core_req_valid(core_req_valid), .core_req_ready(core_req_ready),
    .core_req_we(core_req_we), .core_req_addr(core_req_addr),
    .core_req_wdata(core_req_wdata), .core_req_wstrb(core_req_wstrb),
    .core_resp_valid(core_resp_valid), .core_resp_is_write(core_resp_is_write),
    .core_resp_rdata(core_resp_rdata), .core_resp_resp(core_resp_resp),
    .dbg_w_state(dbg_w_state),
    .dbg_r_state(dbg_r_state)
  );

  // ===== Waves =====
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, core_translator_tb);
  end

  // ===== Defaults / Reset init =====
  task automatic defaults();
    begin
      s_awaddr = '0;   s_awvalid = 0;
      s_wdata  = '0;   s_wstrb  = '0;   s_wvalid = 0;
      s_bready = 0;

      s_araddr = '0;   s_arvalid = 0;
      s_rready = 0;

      core_req_ready    = 0; // will be pulsed when we want the issue handshake
      core_resp_valid   = 0;
      core_resp_is_write= 0;
      core_resp_resp    = 2'b00;
      core_resp_rdata   = '0;
    end
  endtask

  // ===== One-shot pulse helper =====
  task automatic pulse(input int cycles, output logic sig);
    begin
      sig = 1;
      repeat (cycles) @(posedge clk);
      sig = 0;
    end
  endtask

  // ===== Monitors (printf) =====
  always @(posedge clk) if (rst_n) begin
    if (core_req_valid && core_req_ready)
      $display("[%0t] ISSUE: we=%0d addr=%h wdata=%h wstrb=%h",
               $time, core_req_we, core_req_addr, core_req_wdata, core_req_wstrb);
    if (s_bvalid)
      $display("[%0t] B: bvalid=1 bresp=%0b (bready=%0b)", $time, s_bresp, s_bready);
  end

  // ===== Test 1: AW @ T=5, W @ T=10, then complete =====
// Waves + stimulus + monitors (drop this whole block into your TB)
initial begin
  $dumpfile("waves.vcd");
  $dumpvars(0, core_translator_tb);

  // defaults
  s_awvalid=0; s_wvalid=0; s_arvalid=0;
  s_bready=0;  s_rready=0;
  core_req_ready=1;
  core_resp_valid=0; core_resp_is_write=0; core_resp_resp=2'b00;

  @(posedge rst_n);
  $display("[%0t] Reset deasserted", $time);

  // === T=5: AW for 1 cycle ===
  repeat (5) @(posedge clk);
  s_awaddr  = 32'h0000_0000;
  s_awvalid = 1;
  @(posedge clk);
  s_awvalid = 0;
  @(posedge clk);
  @(posedge clk);
  s_araddr  = 32'h0000_0010;
  s_arvalid = 1;
  @(posedge clk);
  s_arvalid = 0;
  @(posedge clk);
  @(posedge clk);
  s_wdata  = 32'hDEADBEEF;
  s_wstrb  = 4'b1111; // Full write
  s_wvalid = 1;
  @(posedge clk);
  @(posedge clk);
  core_resp_rdata = 32'h12345678; // Mock read data
  core_resp_valid = 1; core_resp_is_write = 0; core_resp_resp = 2'b00;
  @(posedge clk);
  core_resp_valid = 0;
  core_req_ready=1;
  @(posedge clk);
  s_wvalid = 0;
  @(posedge clk);
  @(posedge clk);
  core_resp_valid = 1; core_resp_is_write = 1; core_resp_resp = 2'b00;
  @(posedge clk);
  @(posedge clk);

  $finish;
end


  // ===== Simple assertion: do not get stuck in W_ISSUE too long =====
  int issue_stall_cnt;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) issue_stall_cnt <= 0;
    else if (dbg_w_state == 3'b011) begin
      issue_stall_cnt <= issue_stall_cnt + 1;
      if (issue_stall_cnt > 8) begin
        $error("[%0t] Stuck in W_ISSUE for >8 cycles. Check core_busy/grant logic.", $time);
        $stop;
      end
    end else begin
      issue_stall_cnt <= 0;
    end
  end

endmodule
