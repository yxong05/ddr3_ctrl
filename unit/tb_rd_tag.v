// rd_tag regression.
`timescale 1ps/1ps
module tb_rd_tag;
  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg push = 0, valid = 0, drop = 0;
  reg [4:0] tag = 0;
  wire en, busy, empty, idle;
  wire [4:0] addr;

  ddr3_rd_tag #(.TCQ(100), .TAGW(5)) dut (
    .clk(clk), .rst(rst), .init_calib_complete(1'b1),
    .push(push), .push_tag(tag), .push_drop(drop),
    .phy_rddata_valid(valid), .rd_data_en(en), .rd_data_addr(addr),
    .busy(busy), .empty(empty), .mc_read_idle(idle));

  reg [5:0] model [$];
  reg [5:0] exp;
  integer errors = 0, checked = 0, i;

  always @(negedge clk) if (!rst) begin
    if (empty !== (model.size() == 0)) begin errors = errors + 1; $display("ERROR empty flag"); end
    if (valid && model.size() > 0) begin
      exp = model[0];
      if (en !== ~exp[5]) begin errors = errors + 1; $display("ERROR rd_data_en"); end
      if (!exp[5] && addr !== exp[4:0]) begin errors = errors + 1; $display("ERROR tag %0d, expected %0d", addr, exp[4:0]); end
      checked = checked + 1;
    end
    else if (en) begin errors = errors + 1; $display("ERROR rd_data_en without data"); end
  end

  always @(posedge clk) if (!rst) begin
    if (valid && model.size() > 0) void'(model.pop_front());
    if (push) model.push_back({drop, tag});
  end

  initial begin
    repeat (3) @(posedge clk);
    #1000 rst = 0;
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clk); #1000;
      push = ~busy & ($urandom_range(0, 2) == 0);
      tag = $urandom;
      drop = ($urandom_range(0, 7) == 0);
      valid = ($urandom_range(0, 3) == 0);
    end
    $display("checked %0d pops, errors = %0d", checked, errors);
    if (errors == 0 && checked > 500) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
