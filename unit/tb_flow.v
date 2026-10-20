// flow regression.
`timescale 1ps/1ps
module tb_flow;
  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg ctl_full = 0, cmd_full = 0, data_full = 0, rd_busy = 0, cur_rd = 0, req_prd = 0;
  wire col_ok, col2_ok;

  ddr3_flow #(.TCQ(100)) dut (
    .clk(clk), .rst(rst),
    .phy_mc_ctl_full(ctl_full), .phy_mc_cmd_full(cmd_full), .phy_mc_data_full(data_full),
    .rd_fifo_busy(rd_busy), .cur_rd(cur_rd), .req_prd(req_prd),
    .col_ok(col_ok), .col2_ok(col2_ok));

  reg full_p1 = 0, full_p2 = 0;
  integer errors = 0, oks = 0, i;
  always @(posedge clk) begin full_p1 <= ctl_full | cmd_full; full_p2 <= full_p1; end

  always @(negedge clk) if (!rst) begin
    if (col_ok) oks = oks + 1;
    if (col_ok && full_p2) begin errors = errors + 1; $display("ERROR col_ok while PHY FIFO full"); end
    if (col_ok && cur_rd && rd_busy) begin errors = errors + 1; $display("ERROR READ while tag FIFO busy"); end
    if (col_ok && req_prd && full_p1) begin errors = errors + 1; $display("ERROR periodic read: next cycle not free"); end
    if (col2_ok && full_p2) begin errors = errors + 1; $display("ERROR col2_ok while PHY FIFO full"); end
  end

  initial begin
    repeat (3) @(posedge clk);
    #1000 rst = 0;
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clk); #1000;
      ctl_full = ($urandom_range(0, 5) == 0); cmd_full = ($urandom_range(0, 5) == 0);
      rd_busy = ($urandom_range(0, 3) == 0);
      cur_rd = $urandom; req_prd = cur_rd & ($urandom_range(0, 3) == 0);
    end
    $display("col_ok seen %0d times, errors = %0d", oks, errors);
    if (errors == 0 && oks > 500) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
