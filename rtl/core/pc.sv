// Program Counter: Holds the current PC value and increments on each clock edge. PC value used to address the instruction memory
module pc (
    input logic clk,
    input logic [31:0] next_pc,
    output logic [31:0] pc_addr
);

    initial pc_addr = 32'd0;

    always_ff @(posedge clk) begin
        pc_addr <= next_pc;
    end

endmodule
