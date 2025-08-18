module fsm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHE_DEPTH = 32,
    parameter BLOCK_WIDTH = 4
)(  // ================ Simple Cache-Core Internal Interface ================
    input logic clk,
    input logic rst_n,
    input logic core_req_valid,
    input logic core_req_we,
    input logic [ADDR_WIDTH-1:0] core_req_addr,
    input logic [DATA_WIDTH-1:0] core_req_wdata,
    input logic [DATA_WIDTH/8-1:0] core_req_wstrb,
    input logic hit,
    input logic dirty,
    input logic evicted,
    input logic refilled,
    input logic written_to_cache,
    output logic cpu_handshake_complete,
    output logic evict_to_ram,
    output logic core_req_ready,
    output logic core_resp_valid,
    output logic core_resp_is_write,
    output logic [DATA_WIDTH-1:0] core_resp_rdata,
    output logic [1:0] core_resp_resp
    );

//states
 typedef enum logic [3:0] {
    IDLE    = 4'd0,
    LOOKUP  = 4'd1,
    READ   = 4'd2,
    WRITE = 4'd4,
    EVICT = 4'd6,
    REFILL = 4'd7
  } state_e;

state_e current, next;

always_ff @(posedge clk) begin
    if (!rst_n)
        current <= IDLE;      // reset state
    else
        current <= next;  // update state on clock edge
end

always_comb begin
    next = current;
    
    unique case (current)
        IDLE: begin
            if (core_req_valid == 1) next = LOOKUP;
            else next = IDLE;
        end

        LOOKUP: begin
            if (hit == 1) begin
                if (core_req_we == 0) next = IDLE;
                if (core_req_we == 1 && written_to_cache == 1) next = IDLE;
            end 
            else if (hit == 0) begin
                if (core_req_we == 0) next = REFILL;
                else next = EVICT;
            end 
            if (core_resp_valid == 1 && dirty == 0) next = IDLE;
            else if (dirty == 1) next = EVICT;
            else next = LOOKUP;
        end 

        EVICT: begin
            if (evicted == 1) next = REFILL;
            else next = EVICT;
        end 

        REFILL: begin
            if (refilled == 1) next = IDLE;
            else next = REFILL;
        end
    endcase 

end 

always_comb begin
    
    core_req_ready = 0;
    evict_to_ram = 0;

    unique case (current)
        IDLE: begin
            core_req_ready = 1;
            evict_to_ram = 0;
            if (core_req_valid == 1) cpu_handshake_complete = 1;
            else cpu_handshake_complete = 0;
        end

        LOOKUP: begin
            core_req_ready = 0;
            
            
        end 

        EVICT: begin
            evict_to_ram = 1;
        end 

        REFILL: begin
            evict_to_ram = 0;
        end
    endcase
end
endmodule
