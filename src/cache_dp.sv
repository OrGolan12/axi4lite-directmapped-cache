module cache_dp #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int LINE_BYTES   = 16;        // bytes per line (e.g., 16B = 4 words)
    parameter int NUM_LINES    = 32;        // number of lines (power of 2)

)(  //general signals
    input logic clk,
    input logic rst_n,
    //cpu signals
    input logic core_req_we,
    input logic [ADDR_WIDTH-1:0] core_req_addr,
    input logic [DATA_WIDTH-1:0] core_req_wdata,
    input logic [DATA_WIDTH/8-1:0] core_req_wstrb,
    //RAM signals



    //control path signals
    input logic cmp_tag_req,
    output logic req_tag_cmp_resp, //0 = miss, 1 = hit
    output logic req_tag_cmp_valid 



);

    localparam int OFFSET_BITS   = $clog2(LINE_BYTES);
    localparam int INDEX_BITS    = $clog2(NUM_LINES);
    localparam int TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int LINE_BITS     = LINE_BYTES * BYTE_BITS;        // full line width
    localparam int WORD_BYTES    = (DATA_WIDTH / BYTE_BITS);
    localparam int WORDS_PER_LINE= LINE_BYTES / WORD_BYTES;
    localparam int WORD_OFF_BITS = $clog2(WORDS_PER_LINE);

    logic [TAG_BITS-1:0]   tag_array   [NUM_LINES];
    logic                  valid_array [NUM_LINES];
    logic                  dirty_array [NUM_LINES];
    logic [DATA_WIDTH-1:0] data_array  [NUM_LINES][WORDS_PER_LINE]; // word-granular is BRAM-friendly   

    assign req_tag_cmp_resp = cmp_tag_req ? ((tag_array[index] == core_req_addr[LINE_BITS-1:OFFSET_BITS+INDEX_BITS]) && valid_array[OFFSET_BITS+INDEX_BITS-1 -: INDEX_BITS]) : 1'b0;
    
    
    
    always_ff @(posedge clk) begin

        offset <= core_req_addr[OFFSET_BITS-1:0];
        index <= core_req_addr[OFFSET_BITS+INDEX_BITS-1 -: INDEX_BITS];
        tag <= core_req_addr[LINE_BITS-1:OFFSET_BITS+INDEX_BITS];

        if (evict_to_ram == 1) begin //dirty bit handling
            evicted_data[7:0] <= data_cache[index][0];
            evicted_data[15:8] <= data_cache[index][1];
            evicted_data[23:16] <= data_cache[index][2];
            evicted_data[31:24] <= data_cache[index][3];
            evicted_address <= core_req_addr;
            if (ram_resp_valid == 1) evicted <= 1;
        end

        if (refill_from_ram == 1) begin //bring block from RAM
            data_cache[index][0] <= refilled_data_ram[7:0];
            data_cache[index][1] <= refilled_data_ram[15:8];
            data_cache[index][2] <= refilled_data_ram[23:16];
            data_cache[index][3] <= refilled_data_ram[31:24];
            if (core_req_we == 1) begin
            data_cache[index][0] <= core_req_wdata[7:0];
            data_cache[index][1] <= core_req_wdata[15:8];
            data_cache[index][2] <= core_req_wdata[23:16];
            data_cache[index][3] <= core_req_wdata[31:24];
            end
            refilled <= 1;
        end

        if (core_req_we == 1 && hit == 1) begin //relevant only if hit
            data_cache[index][0] <= core_req_wdata[7:0];
            data_cache[index][1] <= core_req_wdata[15:8];
            data_cache[index][2] <= core_req_wdata[23:16];
            data_cache[index][3] <= core_req_wdata[31:24];
            dirty_array[index] <= 1;
            written_to_cache <= 1;
        end
        
        //if (refilled == 1 && )

    end 

    always_comb begin

        if (cpu_handshake_complete == 1) begin //handshake, doesnt matter if read or write
            
            if (core_req_we == 0) begin
                    core_resp_rdata = data_cache[index][offset];
                end

            
            if (tag == address_cache[index][31:8] && valid_array[index] == 1) begin //hit     
                hit = 1;
                core_resp_valid = 1;     
            end

            else if (tag != address_cache[index][31:8] || valid_array[index] == 0) begin //miss
                hit = 0;
            end 
        end
    end

    assign core_resp_rdata = cpu_handshake_complete == 1 && core_req_we == 0 ? data_cache[index][offset] : '0;
    assign evicted_data_ram = evicted_data;
    assign evicted_address_ram = evicted_address;
endmodule
