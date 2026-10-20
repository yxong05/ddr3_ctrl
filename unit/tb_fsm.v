// fsm regression.
`timescale 1ps/1ps
module tb_fsm;
  parameter K_RCD = 1, K_RTP = 1, K_WR = 4, K_RAS = 3, K_RP = 2, K_RFC = 13, K_ZQ = 16;

  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg calib = 0, req_valid = 0, ref_req = 0, zq_req = 0, prd_req = 0;
  reg cur_rd = 0, req_prd = 0, col_ok = 0, col2_ok = 1;
  wire fire_act, fire_col, fire_pre, fire_ref, fire_zq, take_req, take_prd, idle_ns;

  ddr3_fsm #(.TCQ(100), .K_RCD(K_RCD), .K_RTP(K_RTP), .K_WR(K_WR), .K_RAS(K_RAS),
             .K_RP(K_RP), .K_RFC(K_RFC), .K_ZQ(K_ZQ)) dut (
    .clk(clk), .rst(rst), .init_calib_complete(calib),
    .req_valid(req_valid), .ref_req(ref_req), .zq_req(zq_req), .prd_req(prd_req),
    .cur_rd(cur_rd), .req_prd(req_prd), .col_ok(col_ok), .col2_ok(col2_ok),
    .fire_act(fire_act), .fire_col(fire_col), .fire_pre(fire_pre),
    .fire_ref(fire_ref), .fire_zq(fire_zq),
    .take_req(take_req), .take_prd(take_prd), .idle_ns(idle_ns));

  integer cyc = 0;
  integer t_act = -1000, t_col = -1000, t_pre = -1000, t_ref = -1000, t_zq = -1000;
  integer n_act = 0, n_col = 0, n_pre = 0, n_ref = 0, n_zq = 0, n_prd = 0;
  integer errors = 0, i;
  reg open = 0;
  reg last_rd = 0;
  integer cols = 0;

  task bad (input [255:0] msg);
    begin errors = errors + 1; $display("ERROR at cycle %0d: %0s", cyc, msg); end
  endtask

  always @(negedge clk) if (!rst) begin
    if (fire_act + fire_col + fire_pre + fire_ref + fire_zq > 1) bad("two commands in one cycle");

    if (fire_act | fire_ref | fire_zq) begin
      if (open) bad("row command while a row is open");
      if (cyc - t_pre < K_RP) bad("tRP");
      if (cyc - t_ref < K_RFC) bad("tRFC");
      if (cyc - t_zq < K_ZQ) bad("tZQCS");
    end
    if (fire_col) begin
      if (!open) bad("READ/WRITE without ACT");
      if (cyc - t_act < K_RCD) bad("tRCD");
      if (cols == 1 && cyc - t_col != 1) bad("second READ is not in the next cycle");
      if (cols == 1 && !req_prd) bad("two READ/WRITEs in a normal job");
    end
    if (fire_pre) begin
      if (!open || cols == 0) bad("PRE without READ/WRITE");
      if (cyc - t_act < K_RAS) bad("tRAS");
      if (cyc - t_col < (last_rd ? K_RTP : K_WR)) bad("tRTP / write recovery");
      if (req_prd && cols != 2) bad("periodic read needs two READs");
    end

    if (fire_act) begin t_act = cyc; open = 1; cols = 0; n_act = n_act + 1; end
    if (fire_col) begin t_col = cyc; last_rd = cur_rd; cols = cols + 1; n_col = n_col + 1; end
    if (fire_pre) begin t_pre = cyc; open = 0; n_pre = n_pre + 1; end
    if (fire_ref) begin t_ref = cyc; n_ref = n_ref + 1; end
    if (fire_zq) begin t_zq = cyc; n_zq = n_zq + 1; end
    cyc = cyc + 1;
  end

  always @(posedge clk) begin
    if (take_req) begin cur_rd <= #100 $urandom; req_prd <= #100 1'b0; end
    if (take_prd) begin cur_rd <= #100 1'b1; req_prd <= #100 1'b1; n_prd = n_prd + 1; end
    if (fire_ref) ref_req <= #100 1'b0;
    if (fire_zq) zq_req <= #100 1'b0;
    if (take_prd) prd_req <= #100 1'b0;
  end

  initial begin
    repeat (3) @(posedge clk);
    #1000 rst = 0;
    repeat (5) @(posedge clk);
    #1000 calib = 1;
    for (i = 0; i < 20000; i = i + 1) begin
      @(posedge clk); #1000;
      req_valid = ($urandom_range(0, 2) != 0);
      col_ok = ($urandom_range(0, 4) != 0);
      if ($urandom_range(0, 40) == 0) ref_req = 1;
      if ($urandom_range(0, 200) == 0) zq_req = 1;
      if ($urandom_range(0, 60) == 0) prd_req = 1;
    end
    $display("ACT %0d  RD/WR %0d  PRE %0d  REF %0d  ZQCS %0d  periodic %0d  errors %0d",
             n_act, n_col, n_pre, n_ref, n_zq, n_prd, errors);
    if (errors == 0 && n_act > 100 && n_ref > 10 && n_zq > 5 && n_prd > 10) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
