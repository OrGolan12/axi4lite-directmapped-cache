`timescale 1ns/1ps
`default_nettype none
module cache #(parameter ADDR_W=32, DATA_W=32)(
  input  logic clk, rst,
  input  logic [ADDR_W-1:0] cpu_ar_addr,
  input  logic              cpu_ar_valid,
  output logic              cpu_ar_ready,
  output logic [DATA_W-1:0] cpu_r_data,
  output logic [1:0]        cpu_r_resp,
  output logic              cpu_r_valid,
  input  logic              cpu_r_ready
);
  // super-dumb stub: one-cycle AR ready, one-cycle R valid a beat later
  logic pending;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cpu_ar_ready <= 0;
      cpu_r_valid  <= 0;
      cpu_r_resp   <= 2'b00;
      cpu_r_data   <= '0;
      pending      <= 0;
    end else begin
      // accept a read address once per request
      cpu_ar_ready <= cpu_ar_valid && !cpu_ar_ready;
      if (cpu_ar_valid && cpu_ar_ready) begin
        pending     <= 1;
      end

      // produce data exactly one cycle after handshake
      if (pending) begin
        cpu_r_valid <= 1;
        cpu_r_resp  <= 2'b00;
        cpu_r_data  <= 32'hDEAD_BEEF;
        pending     <= 0;
      end else if (cpu_r_valid && cpu_r_ready) begin
        cpu_r_valid <= 0;
      end
    end
  end
endmodule
`default_nettype wire
