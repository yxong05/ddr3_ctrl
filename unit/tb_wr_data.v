// wr_data regression.
`timescale 1ps/1ps
module tb_wr_data;
  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg fire = 0;
  reg [4:0] tag = 0;
  wire wr_data_en, mc_wrdata_en;
  wire [4:0] wr_data_addr;
  wire [1:0] mc_odt;

  ddr3_wr_data #(.TCQ(100), .TAGW(5)) dut (
    .clk(clk), .rst(rst), .wr_fire(fire), .req_tag(tag),
    .wr_data_en(wr_data_en), .wr_data_addr(wr_data_addr),
    .mc_wrdata_en(mc_wrdata_en), .mc_odt(mc_odt));

  reg fire_h [1:3];
  reg [4:0] tag_h [1:3];
  integer errors = 0, writes = 0, i;

  always @(posedge clk) begin
    fire_h[1] <= fire & ~rst; fire_h[2] <= fire_h[1]; fire_h[3] <= fire_h[2];
    tag_h[1] <= tag; tag_h[2] <= tag_h[1]; tag_h[3] <= tag_h[2];
    if (fire & ~rst) writes <= writes + 1;
  end

  always @(negedge clk) if (!rst && fire_h[3] !== 1'bx) begin
    if (wr_data_en !== fire_h[2]) begin errors = errors + 1; $display("ERROR wr_data_en"); end
    if (fire_h[2] && wr_data_addr !== tag_h[2]) begin errors = errors + 1; $display("ERROR wr_data_addr"); end
    if (mc_wrdata_en !== fire_h[3]) begin errors = errors + 1; $display("ERROR mc_wrdata_en"); end
    if (mc_odt !== {1'b0, fire_h[1] | fire_h[2]}) begin errors = errors + 1; $display("ERROR mc_odt"); end
  end

  initial begin
    fire_h[1] = 0; fire_h[2] = 0; fire_h[3] = 1'bx;
    repeat (3) @(posedge clk);
    #1000 rst = 0; fire_h[3] = 0;
    for (i = 0; i < 2000; i = i + 1) begin
      @(posedge clk); #1000;
      fire = ($urandom_range(0, 3) == 0);
      tag = $urandom;
    end
    $display("writes = %0d, errors = %0d", writes, errors);
    if (errors == 0 && writes > 100) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
