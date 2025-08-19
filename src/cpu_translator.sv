// cpu_translator.sv — AXI4-Lite (CPU) <-> simple core port
// - AW/W accepted independently; single-beat
// - One in-flight total; responses held on B/R skid regs
// - Moore issue (both read and write).
// - Arbitration: same-address hazard => WRITE wins; else WRITE_OVER_READ decides.
// - dbg_w_state[2:0], dbg_r_state[1:0] exported for waves

`timescale 1ns/1ps
module cpu_translator #(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  parameter bit WRITE_OVER_READ = 1'b1   // 1=write wins when both can issue
)(
  input  logic                     clk,
  input  logic                     rst_n,

  // ================= AXI4-Lite Slave (CPU) =================
  // Write address channel
  input  logic [ADDR_WIDTH-1:0]    s_awaddr,
  input  logic                     s_awvalid,
  output logic                     s_awready,

  // Write data channel
  input  logic [DATA_WIDTH-1:0]    s_wdata,
  input  logic [DATA_WIDTH/8-1:0]  s_wstrb,
  input  logic                     s_wvalid,
  output logic                     s_wready,

  // Write response channel
  output logic [1:0]               s_bresp,   // 2'b00=OKAY
  output logic                     s_bvalid,
  input  logic                     s_bready,

  // Read address channel
  input  logic [ADDR_WIDTH-1:0]    s_araddr,
  input  logic                     s_arvalid,
  output logic                     s_arready,

  // Read data channel
  output logic [DATA_WIDTH-1:0]    s_rdata,
  output logic [1:0]               s_rresp,   // 2'b00=OKAY
  output logic                     s_rvalid,
  input  logic                     s_rready,

  // ================= Simple Core Port =================
  // Request
  output logic                     core_req_valid,
  input  logic                     core_req_ready,
  output logic                     core_req_we,         // 1=write, 0=read
  output logic [ADDR_WIDTH-1:0]    core_req_addr,
  output logic [DATA_WIDTH-1:0]    core_req_wdata,
  output logic [DATA_WIDTH/8-1:0]  core_req_wstrb,

  // Response (one beat per request)
  input  logic                     core_resp_valid,     // completion pulse
  input  logic                     core_resp_is_write,  // 1=write completion (B), 0=read completion (R)
  input  logic [DATA_WIDTH-1:0]    core_resp_rdata,     // valid when is_write=0
  input  logic [1:0]               core_resp_resp,      // response code

  // ================= DEBUG (visible in waves) =================
  output logic [2:0]               dbg_w_state,
  output logic [1:0]               dbg_r_state
);

  // -------------------------- Write FSM --------------------------
  typedef enum logic [2:0] {
    W_IDLE    = 3'd0,
    W_HAVE_AW = 3'd1,
    W_HAVE_W  = 3'd2,
    W_ISSUE   = 3'd3,
    W_WAIT_B  = 3'd4
  } w_state_e;

  (* keep *) w_state_e w_state, w_state_n;

  logic [ADDR_WIDTH-1:0]   w_awaddr_q;
  logic [DATA_WIDTH-1:0]   w_wdata_q;
  logic [DATA_WIDTH/8-1:0] w_wstrb_q;

  // -------------------------- Read FSM ---------------------------
  typedef enum logic [1:0] {
    R_IDLE   = 2'd0,
    R_ISSUE  = 2'd1,
    R_WAIT_R = 2'd2
  } r_state_e;

  (* keep *) r_state_e r_state, r_state_n;

  logic [ADDR_WIDTH-1:0]   r_araddr_q;

  // ---------------------- Response holding (skid) ----------------
  // B channel hold
  logic        b_hold_valid;
  logic [1:0]  b_hold_resp;

  // R channel hold
  logic        r_hold_valid;
  logic [1:0]  r_hold_resp;
  logic [DATA_WIDTH-1:0] r_hold_data;

  // ----------------------- Handshake helpers ---------------------
  wire aw_hs = s_awvalid && s_awready;
  wire w_hs  = s_wvalid  && s_wready;
  wire ar_hs = s_arvalid && s_arready;

  // One in-flight means "busy" only while waiting for completion
  wire core_busy = (w_state == W_WAIT_B) || (r_state == R_WAIT_R);

  // ----------------------- State & captures ----------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // states
      w_state      <= W_IDLE;
      r_state      <= R_IDLE;
      // captures
      w_awaddr_q   <= '0;
      w_wdata_q    <= '0;
      w_wstrb_q    <= '0;
      r_araddr_q   <= '0;
      // holds
      b_hold_valid <= 1'b0;
      b_hold_resp  <= 2'b00;
      r_hold_valid <= 1'b0;
      r_hold_resp  <= 2'b00;
      r_hold_data  <= '0;
    end else begin
      // next states
      w_state <= w_state_n;
      r_state <= r_state_n;

      // capture AW/W/AR on local handshakes
      if (aw_hs) begin
        w_awaddr_q <= s_awaddr;
      end
      if (w_hs) begin
        w_wdata_q  <= s_wdata;
        w_wstrb_q  <= s_wstrb;
      end
      if (ar_hs) begin
        r_araddr_q <= s_araddr;
      end

      // write completion → latch B hold
      if (core_resp_valid && core_resp_is_write) begin
        b_hold_valid <= 1'b1;
        b_hold_resp  <= core_resp_resp;
      end else if (b_hold_valid && s_bready) begin
        b_hold_valid <= 1'b0;
      end

      // read completion → latch R hold
      if (core_resp_valid && !core_resp_is_write) begin
        r_hold_valid <= 1'b1;
        r_hold_resp  <= core_resp_resp;
        r_hold_data  <= core_resp_rdata;
      end else if (r_hold_valid && s_rready) begin
        r_hold_valid <= 1'b0;
      end
    end
  end

  // --------------------- AXI ready (accept) ----------------------
  // Accept AW if write path hasn't captured AW yet (IDLE or HAVE_W)
  assign s_awready = (w_state == W_IDLE) || (w_state == W_HAVE_W);
  // Accept W  if write path hasn't captured W  yet (IDLE or HAVE_AW)
  assign s_wready  = (w_state == W_IDLE) || (w_state == W_HAVE_AW);
  // Accept AR only when read path is idle (no AR queue)
  assign s_arready = (r_state == R_IDLE);

  // --------------------- Arbitration & drive ---------------------
  // Moore issue: only assert during *_ISSUE, and only when not busy
  wire can_issue_w = !core_busy && (w_state == W_ISSUE);
  wire can_issue_r = !core_busy && (r_state == R_ISSUE);

  // RAW hazard: same full address (replace with line-compare if preferred)
  wire write_addr_known = (w_state == W_HAVE_AW) || (w_state == W_ISSUE) || (w_state == W_WAIT_B);
  wire read_addr_known  = (r_state == R_ISSUE);
  wire same_addr_hazard = write_addr_known && read_addr_known && (w_awaddr_q == r_araddr_q);

  // Selection:
  // 1) If both can issue and same address -> WRITE wins (prevent stale read)
  // 2) Else, if both can issue -> policy: WRITE_OVER_READ (here =1, so WRITE wins)
  // 3) Else, whichever is available.
  wire both_can = can_issue_w && can_issue_r;

  wire sel_w_now = (both_can && same_addr_hazard) ? 1'b1
                   : (both_can ? WRITE_OVER_READ
                               : can_issue_w);
  wire sel_r_now = (!sel_w_now) && can_issue_r;

  // Payloads: Moore → use captured regs
  wire [ADDR_WIDTH-1:0]    w_addr_eff  = w_awaddr_q;
  wire [DATA_WIDTH-1:0]    w_data_eff  = w_wdata_q;
  wire [DATA_WIDTH/8-1:0]  w_strb_eff  = w_wstrb_q;
  wire [ADDR_WIDTH-1:0]    r_addr_eff  = r_araddr_q;

  // Drive core
  assign core_req_valid = sel_w_now || sel_r_now;
  assign core_req_we    = sel_w_now;
  assign core_req_addr  = sel_w_now ? w_addr_eff : r_addr_eff;
  assign core_req_wdata = sel_w_now ? w_data_eff : '0;
  assign core_req_wstrb = sel_w_now ? w_strb_eff : '0;

  wire core_hs_now = core_req_valid && core_req_ready;

  // --------------------- Next-state logic (single block) ---------
  always_comb begin
    // defaults
    w_state_n = w_state;
    r_state_n = r_state;

    // ---------- WRITE FSM ----------
    unique case (w_state)
      W_IDLE: begin
        if      (aw_hs && w_hs) w_state_n = W_ISSUE;
        else if (aw_hs)         w_state_n = W_HAVE_AW;
        else if (w_hs)          w_state_n = W_HAVE_W;
      end
      W_HAVE_AW: begin
        if (w_hs) w_state_n = W_ISSUE;
      end
      W_HAVE_W: begin
        if (aw_hs) w_state_n = W_ISSUE;
      end
      W_ISSUE: begin
        if (core_hs_now && sel_w_now) w_state_n = W_WAIT_B;
      end
      W_WAIT_B: begin
        if (core_resp_valid && core_resp_is_write) w_state_n = W_IDLE;
      end
      default: w_state_n = W_IDLE;
    endcase

    // ---------- READ FSM ----------
    unique case (r_state)
      R_IDLE: begin
        if (ar_hs) r_state_n = R_ISSUE;
      end
      R_ISSUE: begin
        if (core_hs_now && sel_r_now) r_state_n = R_WAIT_R;
      end
      R_WAIT_R: begin
        if (core_resp_valid && !core_resp_is_write) r_state_n = R_IDLE;
      end
      default: r_state_n = R_IDLE;
    endcase
  end

  // --------------------- AXI responses (with holds) --------------
  // B channel
  assign s_bvalid = b_hold_valid;
  assign s_bresp  = b_hold_resp;

  // R channel
  assign s_rvalid = r_hold_valid;
  assign s_rresp  = r_hold_resp;
  assign s_rdata  = r_hold_data;

  // --------------------- DEBUG drives ----------------------------
  assign dbg_w_state = w_state;
  assign dbg_r_state = r_state;

`ifdef ASSERTIONS
  // Never drive a new request while a completion is pending
  assert_no_issue_while_busy:
    assert property (@(posedge clk) core_req_valid |-> !core_busy);

  // Only one selection at a time
  assert_one_hot_sel:
    assert property (@(posedge clk) !(sel_w_now && sel_r_now));

  // If both can issue and same address => must pick write
  assert_hazard_write_wins:
    assert property (@(posedge clk)
      (can_issue_w && can_issue_r && same_addr_hazard) |-> sel_w_now && !sel_r_now);
`endif

endmodule
