module cache_main #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter CACHE_DEPTH = 32,
    parameter BLOCK_WIDTH = 4
)(  //general signals
    input logic clk,
    input logic rst_n,
    input logic evict_to_ram,
    output logic hit,
    output logic dirty_flag,
    output logic evicted,
    output logic refilled,
    output logic written_to_cache,
    
    //cpu signals
    
    input logic cpu_handshake_complete,
    input logic core_req_we,
    input logic [ADDR_WIDTH-1:0] core_req_addr,
    input logic [DATA_WIDTH-1:0] core_req_wdata,
    input logic [DATA_WIDTH/8-1:0] core_req_wstrb,
    output logic core_resp_valid,
    output logic core_resp_is_write,
    output logic [DATA_WIDTH-1:0] core_resp_rdata,
    output logic [1:0] core_resp_resp,
    
    //RAM signals
    
    input logic refill_from_ram,
    input logic [DATA_WIDTH-1:0] refilled_data_ram,
    //input logic [ADDR_WIDTH-1:0] refilled_address_ram,
    input logic ram_resp_valid,
    output logic [DATA_WIDTH-1:0] evicted_data_ram,
    output logic [ADDR_WIDTH-1:0] evicted_address_ram
);

reg [31:0]address_cache[0:31]; //CHANGE TO TAG ARRAY, NO NEED FOR THE WHOLE ADDRESS
reg valid_array[0:31];
reg dirty_array[0:31];
reg [31:0]data_cache[0:7][0:3];
reg [DATA_WIDTH-1:0] evicted_data;
reg [ADDR_WIDTH-1:0] evicted_address;

//cache bits + overhead
reg [1:0] offset;
reg [4:0] index;
reg [24:0] tag;


always_ff @(posedge clk) begin
    offset <= core_req_addr[1:0];
    index <= core_req_addr[7:2];
    tag <= core_req_addr[31:8];

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
assign evicted_data_ram = evicted_data;
assign evicted_address_ram = evicted_address;
endmodule
