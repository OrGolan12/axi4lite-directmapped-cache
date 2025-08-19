// testbench/cache_core_tb.sv
`timescale 1ns/1ps

module cache_core_tb;

  // ===== Parameters (match DUT) =====
  localparam int ADDR_WIDTH   = 32;
  localparam int DATA_WIDTH   = 32;
  localparam int LINE_BYTES   = 16;  // 4 x 32-bit words per line
  localparam int NUM_LINES    = 8;   // small for easy conflict tests

  localparam int WORD_BYTES   = DATA_WIDTH/8;
  localparam int WORDS_PER_LINE = LINE_BYTES/WORD_BYTES;
  localparam int LINE_BITS    = LINE_BYTES*8;

  // ===== Clock / Reset =====
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk; // 100 MHz

  initial begin
    repeat (5) @(posedge clk);
    rst_n = 1;
  end

  // ===== CPU/Core <-> Cache interface =====
  logic                     core_req_valid;
  logic                     core_req_ready;
  logic                     core_req_we;
  logic [ADDR_WIDTH-1:0]    core_req_addr;
  logic [DATA_WIDTH-1:0]    core_req_wdata;
  logic [DATA_WIDTH/8-1:0]  core_req_wstrb;

  logic                     core_resp_valid;
  logic                     core_resp_is_write;
  logic [DATA_WIDTH-1:0]    core_resp_rdata;
  logic [1:0]               core_resp_resp;

  // ===== Cache <-> Memory (line interface) =====
  logic                     mem_req_valid;
  logic                     mem_req_ready;
  logic                     mem_req_we;
  logic [ADDR_WIDTH-1:0]    mem_req_addr;   // line-aligned
  logic [LINE_BITS-1:0]     mem_req_wline;

  logic                     mem_resp_valid;
  logic [LINE_BITS-1:0]     mem_resp_rline;

  // ===== DUT =====
  cache_core #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LINE_BYTES(LINE_BYTES),
    .NUM_LINES(NUM_LINES)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    // CPU/Core
    .core_req_valid(core_req_valid),
    .core_req_ready(core_req_ready),
    .core_req_we(core_req_we),
    .core_req_addr(core_req_addr),
    .core_req_wdata(core_req_wdata),
    .core_req_wstrb(core_req_wstrb),
    .core_resp_valid(core_resp_valid),
    .core_resp_is_write(core_resp_is_write),
    .core_resp_rdata(core_resp_rdata),
    .core_resp_resp(core_resp_resp),
    // Memory (line)
    .mem_req_valid(mem_req_valid),
    .mem_req_ready(mem_req_ready),
    .mem_req_we(mem_req_we),
    .mem_req_addr(mem_req_addr),
    .mem_req_wline(mem_req_wline),
    .mem_resp_valid(mem_resp_valid),
    .mem_resp_rline(mem_resp_rline)
  );

  // ===== Simple line memory model =====
  // - Always ready
  // - Refill latency: fixed N cycles
  // - One transaction in flight (matches DUT)
  localparam int MEM_WORDS = 1024; // 4KB simple backing store
  logic [DATA_WIDTH-1:0] mem_array [0:MEM_WORDS-1];

  // preload memory with recognizable pattern
  integer i;
  initial begin
    for (i = 0; i < MEM_WORDS; i++) begin
      mem_array[i] = 32'hA000_0000 + i; // unique per address
    end
  end

  // helpers
  function automatic [ADDR_WIDTH-1:0] line_align(input [ADDR_WIDTH-1:0] a);
    line_align = {a[ADDR_WIDTH-1: $clog2(LINE_BYTES)], {$clog2(LINE_BYTES){1'b0}}};
  endfunction

  // pack line from mem_array (little address order)
  function automatic [LINE_BITS-1:0] pack_line(input [ADDR_WIDTH-1:0] base_byte_addr);
    int w;
    for (w = 0; w < WORDS_PER_LINE; w++) begin
      pack_line[w*DATA_WIDTH +: DATA_WIDTH] =
        mem_array[(base_byte_addr >> $clog2(WORD_BYTES)) + w];
    end
  endfunction

  // write a whole line back to memory
  task automatic write_line(input [ADDR_WIDTH-1:0] base_byte_addr,
                            input [LINE_BITS-1:0]  line_bits);
    int w;
    begin
      for (w = 0; w < WORDS_PER_LINE; w++) begin
        mem_array[(base_byte_addr >> $clog2(WORD_BYTES)) + w] =
          line_bits[w*DATA_WIDTH +: DATA_WIDTH];
      end
    end
  endtask

  // latency pipeline for a single outstanding mem op
  localparam int REFILL_LAT = 3;
  logic                pend_valid_q;
  logic                pend_we_q;        // 1=writeback, 0=refill
  logic [ADDR_WIDTH-1:0]pend_addr_q;
  int                  countdown_q;

  assign mem_req_ready = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pend_valid_q <= 1'b0;
      mem_resp_valid <= 1'b0;
      mem_resp_rline <= '0;
    end else begin
      mem_resp_valid <= 1'b0; // default, pulse when ready

      // accept request
      if (mem_req_valid && mem_req_ready && !pend_valid_q) begin
        pend_valid_q <= 1'b1;
        pend_we_q    <= mem_req_we;
        pend_addr_q  <= line_align(mem_req_addr);
        countdown_q  <= REFILL_LAT;

        if (mem_req_we) begin
          // writeback: commit immediately (but still send acks after latency to mimic bus)
          write_line(line_align(mem_req_addr), mem_req_wline);
        end
      end

      // progress countdown and respond
      if (pend_valid_q) begin
        if (countdown_q > 0) countdown_q <= countdown_q - 1;
        if (countdown_q == 0) begin
          // For refill, return line; for writeback, just ack
          if (!pend_we_q) mem_resp_rline <= pack_line(pend_addr_q);
          mem_resp_valid <= 1'b1;
          pend_valid_q   <= 1'b0;
        end
      end
    end
  end

  // ===== CPU driver tasks =====
  task automatic cpu_read(input [ADDR_WIDTH-1:0] addr,
                          output [DATA_WIDTH-1:0] rdata);
    begin
      @(posedge clk);
      core_req_we    <= 1'b0;
      core_req_addr  <= addr;
      core_req_wdata <= '0;
      core_req_wstrb <= '0;
      core_req_valid <= 1'b1;
      // wait for accept
      while (!core_req_ready) @(posedge clk);
      @(posedge clk);
      core_req_valid <= 1'b0;

      // wait for response
      while (!core_resp_valid || core_resp_is_write) @(posedge clk);
      rdata = core_resp_rdata;
      $display("[%0t] READ  @%08h -> %08h", $time, addr, rdata);
    end
  endtask

  task automatic cpu_write(input [ADDR_WIDTH-1:0] addr,
                           input [DATA_WIDTH-1:0] wdata,
                           input [DATA_WIDTH/8-1:0] wstrb);
    begin
      @(posedge clk);
      core_req_we    <= 1'b1;
      core_req_addr  <= addr;
      core_req_wdata <= wdata;
      core_req_wstrb <= wstrb;
      core_req_valid <= 1'b1;
      // wait for accept
      while (!core_req_ready) @(posedge clk);
      @(posedge clk);
      core_req_valid <= 1'b0;

      // wait for write-ack
      while (!core_resp_valid || !core_resp_is_write) @(posedge clk);
      $display("[%0t] WRITE @%08h <- %08h (ok)", $time, addr, wdata);
    end
  endtask

  // ===== Waves =====
  initial begin
    $dumpfile("cache_core_tb.vcd");
    $dumpvars(0, cache_core_tb);
  end

  // ===== Test sequence =====
  localparam [ADDR_WIDTH-1:0] A0 = 32'h0000_0040; // line-aligned base
  localparam [ADDR_WIDTH-1:0] A1 = A0 + 32'd4;    // next word in same line
  localparam [ADDR_WIDTH-1:0] B0 = A0 ^ (NUM_LINES << $clog2(LINE_BYTES)); // maps to same index, different tag

  logic [DATA_WIDTH-1:0] rd;

  initial begin
    // CPU idle defaults
    core_req_valid = 0;
    core_req_we    = 0;
    core_req_addr  = '0;
    core_req_wdata = '0;
    core_req_wstrb = '0;

    // Wait for reset
    @(posedge rst_n);
    $display("[%0t] Reset deasserted", $time);

    // --- 1) Read miss -> refill -> read hit
    cpu_read(A0, rd);
    // expected from backing mem pattern
    assert (rd == mem_array[A0 >> $clog2(WORD_BYTES)])
      else $error("Read after refill mismatch at A0");

    // hit (no memory traffic expected)
    cpu_read(A0, rd);
    assert (rd == mem_array[A0 >> $clog2(WORD_BYTES)])
      else $error("Read hit mismatch at A0");

    // --- 2) Write miss with write-allocate, then read back (should see new data)
    cpu_write(A1, 32'hDEAD_BEEF, 4'hF);
    cpu_read (A1, rd);
    assert (rd == 32'hDEAD_BEEF) else $error("Write-allocate readback mismatch at A1");

    // --- 3) Force dirty eviction:
    // access another address that conflicts on the same index to evict A0's line.
    cpu_read(B0, rd); // causes eviction of (A0 line) if that line is dirty
    // Verify that memory now contains the modified data from A1 (writeback happened)
    if (mem_array[A1 >> $clog2(WORD_BYTES)] != 32'hDEAD_BEEF)
      $error("Dirty eviction failed: backing memory did not get updated word");

    // --- 4) Read A1 again -> miss (was evicted) -> refill (now from updated mem) -> should return DEADBEEF
    cpu_read(A1, rd);
    assert (rd == 32'hDEAD_BEEF) else $error("Post-evict read mismatch at A1");

    $display("[%0t] All checks passed.", $time);
    repeat (5) @(posedge clk);
    $finish;
  end

endmodule
