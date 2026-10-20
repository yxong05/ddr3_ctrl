// req regression.
`timescale 1ps/1ps
module tb_req;
  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg [2:0] cmd = 0; reg [2:0] bank = 0; reg [13:0] row = 0; reg [9:0] col = 0;
  reg [4:0] tag = 0; reg use_addr = 0;
  reg idle_ns = 0, any_maint = 0, take_prd = 0;
  wire accept, accept_ns, req_valid, req_rd, req_prd, cur_rd;
  wire [2:0] req_bank; wire [13:0] req_row; wire [9:0] req_col; wire [4:0] req_tag;

  ddr3_req #(.TCQ(100), .BANK_WIDTH(3), .ROW_WIDTH(14), .COL_WIDTH(10), .TAGW(5)) dut (
    .clk(clk), .rst(rst), .cmd(cmd), .bank(bank), .row(row), .col(col),
    .data_buf_addr(tag), .use_addr(use_addr), .accept(accept), .accept_ns(accept_ns),
    .init_calib_complete(1'b1), .idle_ns(idle_ns), .any_maint(any_maint),
    .take_req(req_valid), .take_prd(take_prd),
    .req_valid(req_valid), .req_rd(req_rd), .req_prd(req_prd),
    .req_bank(req_bank), .req_row(req_row), .req_col(req_col), .req_tag(req_tag),
    .cur_rd(cur_rd));

  reg [2:0] cmd_p; reg [2:0] bank_p; reg [13:0] row_p; reg [9:0] col_p;
  reg e_rd; reg [2:0] e_bank; reg [13:0] e_row; reg [9:0] e_col; reg [4:0] e_tag;
  reg e_new = 0, acc_exp = 0;
  integer errors = 0, taken = 0, i;

  always @(posedge clk) begin
    cmd_p <= cmd; bank_p <= bank; row_p <= row; col_p <= col;
    acc_exp <= ~rst & idle_ns & ~any_maint;
    e_new <= 1'b0;
    if (!rst && acc_exp && use_addr) begin
      e_rd <= (cmd_p[1:0] == 2'b01); e_bank <= bank_p; e_row <= row_p; e_col <= col_p; e_tag <= tag;
      e_new <= 1'b1;
    end
  end

  always @(negedge clk) if (!rst) begin
    if (accept !== acc_exp) begin errors = errors + 1; $display("ERROR accept"); end
    if (e_new) begin
      taken = taken + 1;
      if ({req_rd, req_bank, req_row, req_col, req_tag} !== {e_rd, e_bank, e_row, e_col, e_tag}) begin
        errors = errors + 1; $display("ERROR wrong request stored");
      end
      if (req_prd !== 1'b0) begin errors = errors + 1; $display("ERROR req_prd after a user request"); end
    end
  end

  initial begin
    repeat (3) @(posedge clk);
    #1000 rst = 0;
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clk); #1000;
      cmd = $urandom; bank = $urandom; row = $urandom; col = $urandom; tag = $urandom;
      use_addr = $urandom;
      idle_ns = ($urandom_range(0, 2) == 0);
      any_maint = ($urandom_range(0, 5) == 0);
    end

    @(posedge clk); #1000; use_addr = 0; take_prd = 1;
    @(posedge clk); #1000; take_prd = 0;
    @(negedge clk);
    if (!req_prd || !cur_rd || {req_bank, req_row, req_col} !== {e_bank, e_row, e_col}) begin
      errors = errors + 1; $display("ERROR periodic read");
    end
    $display("requests taken = %0d, errors = %0d", taken, errors);
    if (errors == 0 && taken > 200) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
