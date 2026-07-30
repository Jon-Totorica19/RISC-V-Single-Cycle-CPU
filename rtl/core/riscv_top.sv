// top level riscv module. Instantiate the riscv core and instr and data memories, then wire together
module riscv_top (
    input logic clk, rst
);

    logic MemRead, MemWrite;
    logic [31:0] instr_addr, data_addr, writeData;
    logic [31:0] instr, readData;

    riscv_core riscv_core (
        .clk(clk),
        .rst(rst),
        .instr(instr),
        .readData(readData),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .instr_addr(instr_addr),
        .data_addr(data_addr),
        .writeData(writeData)
    );

    instr_mem instr_mem (
        .addr(instr_addr),
        .instr(instr)
    );

    data_mem data_mem (
        .clk(clk),
        .MemRead(MemRead),
        .MemWrite(MemWrite),
        .writeData(writeData),
        .addr(data_addr),
        .readData(readData)
    );

endmodule