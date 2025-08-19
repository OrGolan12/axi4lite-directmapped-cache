// src/cache_core.sv
// Direct-mapped, blocking, write-back, write-allocate cache core.
// Icarus-friendly (no dynamic part-selects on arrays, explicit enum codes).

`timescale 1ns/1ps
module cache_core #(
  parameter int ADDR_WIDTH  = 32,
  parameter int DATA_WIDTH  = 32,
  parameter int LINE_BYTES  = 16,              // 16B line (4x32-bit words)
  parameter int NUM_LINES   = 64,              // power of 2
  parameter int LINE_BITS   = LINE_BYTES * 8   // used in port widths
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // ===== CPU/Core side =====
  input  logic                     core_req_valid,
  output logic                     core_req_ready,
  input  logic                     core_req_we,                 // 1=write, 0=read
  input  logic [ADDR_WIDTH-1:0]    core_req_addr,
  input  logic [DATA_WIDTH-1:0]    core_req_wdata,
  input  logic [DATA_WIDTH/8-1:0]  core_req_wstrb,

  output logic                     core_resp_valid,
  output logic                     core_resp_is_write,          // 1=write-ack, 0=read-data
  output logic [DATA_WIDTH-1:0]    core_resp_rdata,
  output logic [1:0]               core_resp_resp,              // 00=OKAY

  // ===== Memory/Backend (whole-line interface) =====
  output logic                     mem_req_valid,
  input  logic                     mem_req_ready,
  output logic                     mem_req_we,                  // 1=writeback, 0=refill
  output logic [ADDR_WIDTH-1:0]    mem_req_addr,                // line-aligned
  output logic [LINE_BITS-1:0]     mem_req_wline,               // on writeback
  input  logic                     mem_resp_valid,              // refill or WB-ack
  input  logic [LINE_BITS-1:0]     mem_resp_rline               // on refill
);

  // ---------------- Derived ----------------
  localparam int WORD_BYTES      = DATA_WIDTH/8;
  localparam int OFFSET_BITS     = $clog2(LINE_BYTES);
  localparam int INDEX_BITS      = $clog2(NUM_LINES);
  localparam int TAG_BITS        = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
  localparam int WORDS_PER_LINE  = LINE_BYTES / WORD_BYTES;
  localparam int WORD_IDX_BITS   = (WORDS_PER_LINE > 1) ? $clog2(WORDS_PER_LINE) : 1;
  localparam int BYTE_IDX_BITS   = (WORD_BYTES > 1) ? $clog2(WORD_BYTES) : 0;

  // masks (constant)
  localparam logic [INDEX_BITS-1:0] INDEX_MASK = (INDEX_BITS==0)? '0 : {INDEX_BITS{1'b1}};
  localparam logic [WORD_IDX_BITS-1:0] WIDX_MASK = (WORD_IDX_BITS==0)? '0 : {WORD_IDX_BITS{1'b1}};

  // ---------------- Arrays ----------------
  logic [TAG_BITS-1:0]    tag_arr   [NUM_LINES];
  logic                   valid_arr [NUM_LINES];
  logic                   dirty_arr [NUM_LINES];
  logic [DATA_WIDTH-1:0]  data_arr  [NUM_LINES][WORDS_PER_LINE];

  // ---------------- Request latch ----------------
  typedef struct packed {
    logic                   we;
    logic [ADDR_WIDTH-1:0]  addr;
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH/8-1:0]wstrb;
  } req_t;
  req_t req_q, req_d;

  // ---------------- FSM ----------------
  typedef enum logic [3:0] {
    S_IDLE         = 4'd0,
    S_HIT_READ     = 4'd1,
    S_HIT_WRITE    = 4'd2,
    S_EVICT_ISSUE  = 4'd3,
    S_EVICT_WAIT   = 4'd4,
    S_REFILL_ISSUE = 4'd5,
    S_REFILL_WAIT  = 4'd6,
    S_FILL_LINE    = 4'd7,
    S_RESP_READ    = 4'd8,
    S_RESP_WRITE   = 4'd9
  } state_e;
  state_e s_q, s_d;

  // ---------------- Address slices (no part-selects with variables) ----------------
  wire [INDEX_BITS-1:0]    idx  = (INDEX_BITS==0) ? '0
                           : ((core_req_addr >> OFFSET_BITS) & INDEX_MASK);
  wire [TAG_BITS-1:0]      tag  = core_req_addr >> (OFFSET_BITS + INDEX_BITS);
  wire [WORD_IDX_BITS-1:0] widx = (WORD_IDX_BITS==0) ? '0
                           : (((core_req_addr >> BYTE_IDX_BITS) & WIDX_MASK));

  // line-align helper (constant mask)
  function automatic [ADDR_WIDTH-1:0] align_addr(input [ADDR_WIDTH-1:0] a);
    align_addr = {a[ADDR_WIDTH-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  endfunction

  // ---------------- Lookup ----------------
  wire hit = valid_arr[idx] && (tag_arr[idx] == tag);

  // Victim line pack (for writeback)
  logic [LINE_BITS-1:0] victim_line;
  integer pw;
  always_comb begin
    victim_line = '0;
    for (pw = 0; pw < WORDS_PER_LINE; pw++) begin
      victim_line[pw*DATA_WIDTH +: DATA_WIDTH] = data_arr[idx][pw];
    end
  end

  // Latched refill line
  logic [LINE_BITS-1:0] refill_line_q;

  // ---------------- Defaults / Next-state ----------------
  always_comb begin
    // CPU side
    core_req_ready     = 1'b0;
    core_resp_valid    = 1'b0;
    core_resp_is_write = 1'b0;
    core_resp_rdata    = '0;
    core_resp_resp     = 2'b00;

    // Mem side
    mem_req_valid      = 1'b0;
    mem_req_we         = 1'b0;
    mem_req_addr       = '0;
    mem_req_wline      = victim_line;

    // Next
    s_d   = s_q;
    req_d = req_q;

    case (s_q)
      // -------- IDLE / LOOKUP --------
      S_IDLE: begin
        core_req_ready = 1'b1;
        if (core_req_valid) begin
          req_d.we    = core_req_we;
          req_d.addr  = core_req_addr;
          req_d.wdata = core_req_wdata;
          req_d.wstrb = core_req_wstrb;

          if (hit) begin
            s_d = core_req_we ? S_HIT_WRITE : S_HIT_READ;
          end else begin
            if (valid_arr[idx] && dirty_arr[idx]) begin
              // writeback victim (tag_arr[idx], idx)
              mem_req_we    = 1'b1;
              mem_req_addr  = { tag_arr[idx], idx, {OFFSET_BITS{1'b0}} }; // already aligned
              mem_req_valid = 1'b1;
              s_d           = mem_req_ready ? S_EVICT_WAIT : S_EVICT_ISSUE;
            end else begin
              // straight refill
              mem_req_we    = 1'b0;
              mem_req_addr  = align_addr(core_req_addr);
              mem_req_valid = 1'b1;
              s_d           = mem_req_ready ? S_REFILL_WAIT : S_REFILL_ISSUE;
            end
          end
        end
      end

      // -------- HIT paths --------
      S_HIT_READ: begin
        core_resp_valid    = 1'b1;
        core_resp_is_write = 1'b0;
        core_resp_rdata    = data_arr[idx][widx];
        s_d = S_IDLE;
      end

      S_HIT_WRITE: begin
        // write done in seq block
        s_d = S_RESP_WRITE;
      end

      S_RESP_WRITE: begin
        core_resp_valid    = 1'b1;
        core_resp_is_write = 1'b1;
        s_d = S_IDLE;
      end

      // -------- EVICT --------
      S_EVICT_ISSUE: begin
        mem_req_we    = 1'b1;
        mem_req_addr  = { tag_arr[idx], idx, {OFFSET_BITS{1'b0}} };
        mem_req_valid = 1'b1;
        if (mem_req_ready) s_d = S_EVICT_WAIT;
      end

      S_EVICT_WAIT: begin
        if (mem_resp_valid) begin
          mem_req_we    = 1'b0;
          mem_req_addr  = align_addr(req_q.addr);
          mem_req_valid = 1'b1;
          s_d           = mem_req_ready ? S_REFILL_WAIT : S_REFILL_ISSUE;
        end
      end

      // -------- REFILL --------
      S_REFILL_ISSUE: begin
        mem_req_we    = 1'b0;
        mem_req_addr  = align_addr(req_q.addr);
        mem_req_valid = 1'b1;
        if (mem_req_ready) s_d = S_REFILL_WAIT;
      end

      S_REFILL_WAIT: begin
        if (mem_resp_valid) begin
          s_d = S_FILL_LINE;
        end
      end

      S_FILL_LINE: begin
        s_d = req_q.we ? S_RESP_WRITE : S_RESP_READ;
      end

      S_RESP_READ: begin
        core_resp_valid    = 1'b1;
        core_resp_is_write = 1'b0;
        core_resp_rdata    = data_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK]
                                       [((req_q.addr >> BYTE_IDX_BITS) & WIDX_MASK)];
        s_d = S_IDLE;
      end

      default: s_d = S_IDLE;
    endcase
  end

  // ---------------- Sequential ----------------
  integer i, w, b;
  logic [DATA_WIDTH-1:0] tmp_word;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_q   <= S_IDLE;
      req_q <= '0;
      refill_line_q <= '0;
      for (i = 0; i < NUM_LINES; i++) begin
        valid_arr[i] <= 1'b0;
        dirty_arr[i] <= 1'b0;
        tag_arr[i]   <= '0;
        for (w = 0; w < WORDS_PER_LINE; w++) data_arr[i][w] <= '0;
      end
    end else begin
      s_q   <= s_d;
      req_q <= req_d;

      // capture refill line
      if (s_q == S_REFILL_WAIT && mem_resp_valid) begin
        refill_line_q <= mem_resp_rline;
      end

      // HIT_WRITE: merge bytes using a temp word (avoid var part-select on array)
      if (s_q == S_HIT_WRITE) begin
        tmp_word = data_arr[idx][widx];
        for (b = 0; b < WORD_BYTES; b++) begin
          if (core_req_wstrb[b]) begin
            tmp_word[8*b +: 8] = core_req_wdata[8*b +: 8];
          end
        end
        data_arr[idx][widx] <= tmp_word;
        dirty_arr[idx]      <= 1'b1;
      end

      // FILL_LINE: install line, tag/valid/dirty; merge write-allocate bytes
      if (s_q == S_FILL_LINE) begin
        for (w = 0; w < WORDS_PER_LINE; w++) begin
          data_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK][w]
            <= refill_line_q[w*DATA_WIDTH +: DATA_WIDTH];
        end
        tag_arr  [(req_q.addr >> OFFSET_BITS) & INDEX_MASK] <= req_q.addr >> (OFFSET_BITS+INDEX_BITS);
        valid_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK] <= 1'b1;
        dirty_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK] <= req_q.we;

        if (req_q.we) begin
          tmp_word = data_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK]
                               [((req_q.addr >> BYTE_IDX_BITS) & WIDX_MASK)];
          for (b = 0; b < WORD_BYTES; b++) begin
            if (req_q.wstrb[b])
              tmp_word[8*b +: 8] = req_q.wdata[8*b +: 8];
          end
          data_arr[(req_q.addr >> OFFSET_BITS) & INDEX_MASK]
                  [((req_q.addr >> BYTE_IDX_BITS) & WIDX_MASK)] <= tmp_word;
        end
      end
    end
  end

endmodule
