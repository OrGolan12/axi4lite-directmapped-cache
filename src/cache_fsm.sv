module cache_fsm #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int LINE_BYTES   = 16,        // bytes per line (e.g., 16B = 4 words)
    parameter int NUM_LINES    = 32        // number of lines (power of 2)
)(  // ================ Simple Cache-Core Internal Interface ================
    input logic clk,
    input logic rst_n,
    input logic core_req_valid,
    input logic core_req_we,
    input logic [ADDR_WIDTH-1:0] core_req_addr,
    input logic [DATA_WIDTH-1:0] core_req_wdata,
    input logic [DATA_WIDTH/8-1:0] core_req_wstrb,
    output logic core_req_ready,
    output logic core_resp_valid,
    output logic core_resp_is_write,
    output logic [DATA_WIDTH-1:0] core_resp_rdata,
    output logic [1:0] core_resp_resp,
    // ================ Data path Signals ================
    input logic req_tag_cmp_resp, // 0 = miss, 1 = hit
    input logic req_tag_cmp_valid,
    output logic req_tag_cmp
    );



  // -------- Derived constants --------
localparam int OFFSET_BITS   = $clog2(LINE_BYTES);
localparam int INDEX_BITS    = $clog2(NUM_LINES);
localparam int TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
localparam int LINE_BITS     = LINE_BYTES * BYTE_BITS;        // full line width
localparam int WORD_BYTES    = (DATA_WIDTH / BYTE_BITS);
localparam int WORDS_PER_LINE= LINE_BYTES / WORD_BYTES;
localparam int WORD_OFF_BITS = $clog2(WORDS_PER_LINE);
localparam int BYTE_BITS     = 8; // Assuming 8 bits per byte

// -------- States --------
typedef enum logic [2:0] { IDLE, LOOKUP, EVICT, REFILL } state_e;
state_e current, next;

// -------- State register (SEQUENTIAL) --------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) current <= IDLE;
    else        current <= next;
end

// Keep previous state (for entry one-shot)
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) prev <= IDLE;
    else        prev <= current;
end

assign req_tag_cmp = (current == LOOKUP) && (prev != LOOKUP);

always_comb begin
    next = current;
    unique case (current)
        IDLE: if (core_req_valid) next = LOOKUP;
        LOOKUP: begin
            if (hit) begin
                if (!core_req_we) next = IDLE;
                if (core_req_we && written_to_cache) next = IDLE;
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



endmodule
