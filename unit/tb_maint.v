// maint regression.
`timescale 1ps/1ps
module tb_maint;
  localparam PRESC_DIV = 4, REF_TICKS = 10, ZQ_TICKS = 100, PRD_TICKS = 7;

  reg clk = 0, rst = 1;
  always #5000 clk = ~clk;

  reg calib = 0, fire_ref = 0, fire_zq = 0, take_prd = 0, busy = 0;
  wire ref_req, zq_pend, prd_pend, any_maint, wip, ref_ack, zq_ack;

  ddr3_maint #(.TCQ(100), .PRESC_DIV(PRESC_DIV), .REF_TICKS(REF_TICKS),
               .ZQ_TICKS(ZQ_TICKS), .PRD_TICKS(PRD_TICKS), .USER_REFRESH("OFF")) dut (
    .clk(clk), .rst(rst), .init_calib_complete(calib),
    .app_ref_req(1'b0), .app_zq_req(1'b0), .app_periodic_rd_req(1'b0),
    .app_ref_ack(ref_ack), .app_zq_ack(zq_ack),
    .fire_ref(fire_ref), .fire_zq(fire_zq), .take_prd(take_prd),
    .idle_ns(~busy), .rd_empty(1'b1),
    .ref_req(ref_req), .zq_pend(zq_pend), .prd_pend(prd_pend),
    .any_maint(any_maint), .mc_ref_zq_wip(wip));

  integer n_ref = 0, n_zq = 0, n_prd = 0, cyc = 0, errors = 0, exp;
  always @(posedge clk) begin
    fire_ref <= #100 1'b0; fire_zq <= #100 1'b0; take_prd <= #100 1'b0;
    if (calib && !busy && !fire_ref && !fire_zq && !take_prd) begin
      if (ref_req) begin fire_ref <= #100 1'b1; n_ref = n_ref + 1; end
      else if (zq_pend) begin fire_zq <= #100 1'b1; n_zq = n_zq + 1; end
      else if (prd_pend) begin take_prd <= #100 1'b1; n_prd = n_prd + 1; end
    end
    if (calib) cyc = cyc + 1;
  end

  task check (input [63:0] name, input integer got, input integer ticks_per);
    begin
      exp = 1 + cyc / (PRESC_DIV * ticks_per);
      if (got < exp - 1 || got > exp) begin
        errors = errors + 1; $display("ERROR %0s: got %0d, expected about %0d", name, got, exp);
      end
    end
  endtask

  initial begin
    repeat (3) @(posedge clk);
    #1000 rst = 0;
    repeat (20) @(posedge clk);
    if (ref_req !== 1'b1 || zq_pend !== 1'b1 || prd_pend !== 1'b1) begin
      errors = errors + 1; $display("ERROR nothing asked after reset");
    end
    #1000 calib = 1;
    repeat (4000) @(posedge clk);
    check("REF", n_ref, REF_TICKS); check("ZQCS", n_zq, ZQ_TICKS); check("PRD", n_prd, PRD_TICKS);

    #1000 busy = 1;
    repeat (5 * PRESC_DIV * REF_TICKS) @(posedge clk);
    #1000 busy = 0;
    repeat (100) @(posedge clk);
    check("REF", n_ref, REF_TICKS);

    $display("after %0d cycles: REF %0d  ZQCS %0d  periodic %0d  errors %0d", cyc, n_ref, n_zq, n_prd, errors);
    if (errors == 0) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
