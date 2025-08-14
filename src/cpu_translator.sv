// cpu_translator.sv
// AXI4-Lite (CPU slave) <-> Simple one-request Core Port
// - AW/W can arrive in any order (collected independently)
// - One request in-flight total (no RAW checks beyond same-address gate here)
// - Response holding (skid) for B and R channels
// - DEBUG: dbg_w_state[2:0], dbg_r_state[1:0]

`timescale 1ns/1ps

module cpu_translator #(
  parameter int ADDR_WIDTH      = 32,
  parameter int DATA_WIDTH      = 32,
  // 1 = write priority when both are ready; 0 = read-first (with RAW override)
  parameter bit WRITE_OVER_READ = 1'b1
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

  // ================= Simple Core Port (to cache core) =================
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

  // ================= DEBUG =================
  output logic [2:0]               dbg_w_state,
  output logic [1:0]               dbg_r_state
);

  // -------------------------- Write FSM --------------------------
  typedef enum logic [2:0] {
    W_IDLE    = 3'd0,
    W_GOT_AW  = 3'd1,
    W_GOT_W   = 3'd2,
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

  // ---------------------- Response holding -----------------------
  // B channel hold
  logic        b_hold_valid;
  logic [1:0]  b_hold_resp;

  // R channel hold
  logic        r_hold_valid;
  logic [1:0]  r_hold_resp;
  logic [DATA_WIDTH-1:0] r_hold_data;

  // ----------------------- Busy & pending ------------------------
  // Busy ONLY while waiting for completion
  wire core_busy  = (w_state == W_WAIT_B) || (r_state == R_WAIT_R);
  // Pending when in ISSUE states
  wire w_req_pend = (w_state == W_ISSUE);
  wire r_req_pend = (r_state == R_ISSUE);

  // ----------------------- RAW hazard gate -----------------------
  // Write address is known after AW is captured (GOT_AW or later)
  wire write_addr_valid = (w_state == W_GOT_AW) || (w_state == W_ISSUE) || (w_state == W_WAIT_B);
  // Read address is known in R_ISSUE
  wire read_addr_valid  = (r_state == R_ISSUE);

  // Same-byte-address hazard (upgrade to line compare if needed)
  wire addr_hazard = write_addr_valid && read_addr_valid && (w_awaddr_q == r_araddr_q);

  // ----------------------- Registered grants ---------------------
  (* keep *) logic grant_w, grant_r;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      grant_w <= 1'b0;
      grant_r <= 1'b0;
    end else begin
      // Clear grant on handshake
      if (core_req_valid && core_req_ready) begin
        grant_w <= 1'b0;
        grant_r <= 1'b0;
      end
      // Take new grant only when core is free and no active grant
      else if (!core_busy && !grant_w && !grant_r) begin
        unique case (1'b1)
          // Both want to issue: hazard forces write first; else policy
          (w_req_pend && r_req_pend): begin
            if (addr_hazard) begin
              grant_w <= 1'b1;
            end else begin
              if (WRITE_OVER_READ) grant_w <= 1'b1;
              else                 grant_r <= 1'b1; // read-first
            end
          end
          // Only write pending
          (w_req_pend): grant_w <= 1'b1;
          // Only read pending: if hazard exists (write addr captured & same), stall read; else grant read
          (r_req_pend): begin
            if (!addr_hazard) grant_r <= 1'b1;
            // else wait until write can issue when W arrives
          end
          default: /* idle */ ;
        endcase
      end
    end
  end

  // --------------------- Drive core from grant -------------------
  assign core_req_valid = grant_w | grant_r;
  assign core_req_we    = grant_w;

  assign core_req_addr  = grant_w ? w_awaddr_q :
                          grant_r ? r_araddr_q : '0;

  assign core_req_wdata = grant_w ? w_wdata_q  : '0;
  assign core_req_wstrb = grant_w ? w_wstrb_q  : '0;

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
      if (s_awready && s_awvalid) begin
        w_awaddr_q <= s_awaddr;
      end
      if (s_wready && s_wvalid) begin
        w_wdata_q  <= s_wdata;
        w_wstrb_q  <= s_wstrb;
      end
      if (s_arready && s_arvalid) begin
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

  // --------------------- Write FSM next-state --------------------
  always_comb begin
    w_state_n = w_state;
    unique case (w_state)
      W_IDLE: begin
        // accept either AW or W (independently)
        if      (s_awvalid && s_awready) w_state_n = W_GOT_AW;
        else if (s_wvalid  && s_wready ) w_state_n = W_GOT_W;
      end
      W_GOT_AW: begin
        if (s_wvalid && s_wready) w_state_n = W_ISSUE;
      end
      W_GOT_W: begin
        if (s_awvalid && s_awready) w_state_n = W_ISSUE;
      end
      // Advance ONLY when THIS write was actually issued
      W_ISSUE: begin
        if (grant_w && core_req_valid && core_req_ready) w_state_n = W_WAIT_B;
      end
      W_WAIT_B: begin
        if (core_resp_valid && core_resp_is_write) w_state_n = W_IDLE;
      end
      default: w_state_n = W_IDLE;
    endcase
  end

  // ---------------------- Read FSM next-state --------------------
  always_comb begin
    r_state_n = r_state;
    unique case (r_state)
      R_IDLE: begin
        if (s_arvalid && s_arready) r_state_n = R_ISSUE;
      end
      // Advance ONLY when THIS read was actually issued
      R_ISSUE: begin
        if (grant_r && core_req_valid && core_req_ready) r_state_n = R_WAIT_R;
      end
      R_WAIT_R: begin
        if (core_resp_valid && !core_resp_is_write) r_state_n = R_IDLE;
      end
      default: r_state_n = R_IDLE;
    endcase
  end

  // --------------------- AXI ready (accept) ----------------------
  // Accept AW if write path hasn't captured AW yet (IDLE or GOT_W)
  assign s_awready = (w_state == W_IDLE) || (w_state == W_GOT_W);
  // Accept W  if write path hasn't captured W  yet (IDLE or GOT_AW)
  assign s_wready  = (w_state == W_IDLE) || (w_state == W_GOT_AW);
  // Accept AR only when read path is idle (no AR queue)
  assign s_arready = (r_state == R_IDLE);

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

endmodule

