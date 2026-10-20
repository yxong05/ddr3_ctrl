// Integrated queue/scheduler/flow check. Compare REUSE=0 and REUSE=1.
`timescale 1ps/1ps
module tb_queued;
  parameter REUSE=1;
  reg clk=0,rst=1;
  always #5000 clk=~clk;
  reg [2:0] cmd=1,bank=0;
  reg [13:0] row=0;
  reg [9:0] col=0;
  reg [7:0] tag=0;
  reg use_addr=0,ref_req=0,zq_req=0,prd_req=0;
  reg ctl_full=0,cmd_full=0,data_full=0,rd_busy=0;
  wire accept,accept_ns,req_valid,next_hit,req_rd,req_prd,cur_rd;
  wire [2:0] req_bank;
  wire [13:0] req_row;
  wire [9:0] req_col;
  wire [7:0] req_tag;
  wire act,cas,pre,ref_cmd,zq,take,take_prd,idle_ns,col_ok,col2_ok;
  wire maint=ref_req|zq_req|prd_req;
  ddr3_req_queue #(.TAGW(8)) q(
    .clk(clk),.rst(rst),.cmd(cmd),.bank(bank),.row(row),.col(col),
    .data_buf_addr(tag),.use_addr(use_addr),.accept(accept),.accept_ns(accept_ns),
    .init_calib_complete(1'b1),.any_maint(maint),
    .take_req(take),.take_prd(take_prd),.req_valid(req_valid),.next_hit(next_hit),
    .req_rd(req_rd),.req_prd(req_prd),.req_bank(req_bank),.req_row(req_row),
    .req_col(req_col),.req_tag(req_tag),.cur_rd(cur_rd));
  ddr3_fsm #(.REUSE_ROWS(REUSE)) f(
    .clk(clk),.rst(rst),.init_calib_complete(1'b1),.next_hit(next_hit),
    .req_valid(req_valid),.ref_req(ref_req),.zq_req(zq_req),.prd_req(prd_req),
    .cur_rd(cur_rd),.req_prd(req_prd),.col_ok(col_ok),.col2_ok(col2_ok),
    .fire_act(act),.fire_col(cas),.fire_pre(pre),.fire_ref(ref_cmd),.fire_zq(zq),
    .take_req(take),.take_prd(take_prd),.idle_ns(idle_ns));
  ddr3_flow flow(.clk(clk),.rst(rst),.phy_mc_ctl_full(ctl_full),
    .phy_mc_cmd_full(cmd_full),.phy_mc_data_full(data_full),.rd_fifo_busy(rd_busy),
    .cur_rd(cur_rd),.req_prd(req_prd),.col_ok(col_ok),.col2_ok(col2_ok));
  reg [35:0] expected [0:4095]; // rd, bank, row, col, tag
  reg [27:0] delayed_addr;
  integer accepted=0,issued=0,cycles=0,acts=0,refs=0,zqs=0,prds=0;
  integer last_act=-1000,last_col=-1000,last_pre=-1000,last_ref=-1000,last_zq=-1000;
  integer stream_end=0,stream_acts=0,run_cols=0;
  reg opened=0,last_rd=0;
  reg [2:0] open_bank;
  reg [13:0] open_row;
  always @(posedge clk) begin
    delayed_addr <= {(cmd[1:0]==1),bank,row,col};
    if (!rst) begin
      cycles=cycles+1;
      if (accept && use_addr) begin
        expected[accepted]={delayed_addr,tag}; accepted=accepted+1;
      end
      if (q.count>4) $fatal(1,"queue overflow");
      if (act) begin
        if (opened || cycles-last_pre<2 || cycles-last_ref<13 || cycles-last_zq<16)
          $fatal(1,"illegal ACT");
        opened=1; open_bank=req_bank; open_row=req_row;
        last_act=cycles; acts=acts+1; run_cols=0;
      end
      if (cas) begin
        if (!opened || req_bank!=open_bank || req_row!=open_row || cycles-last_act<1)
          $fatal(1,"column to wrong row / tRCD");
        if (run_cols>0 && !req_prd && cycles-last_col<(last_rd ? 2 : 5))
          $fatal(1,"column recovery");
        if (!req_prd) begin
          if (issued>=accepted || {req_rd,req_bank,req_row,req_col,req_tag}!==expected[issued])
            $fatal(1,"request lost/reordered/corrupted at %0d",issued);
          issued=issued+1;
          if (issued==32) begin stream_end=cycles; stream_acts=acts; end
        end else prds=prds+1;
        last_col=cycles; last_rd=cur_rd; run_cols=run_cols+1;
        if (!req_prd && run_cols>8 && REUSE) $fatal(1,"unbounded row reuse");
      end
      if (pre) begin
        if (!opened || cycles-last_act<3 || cycles-last_col<(last_rd ? 1 : 4))
          $fatal(1,"illegal PRE");
        opened=0; last_pre=cycles;
      end
      if (ref_cmd || zq) begin
        if (opened || cycles-last_pre<2 || cycles-last_ref<13 || cycles-last_zq<16)
          $fatal(1,"maintenance timing");
      end
      if (ref_cmd) begin last_ref=cycles; refs=refs+1; end
      if (zq) begin last_zq=cycles; zqs=zqs+1; end
    end
  end
  // Sticky requests, cleared when serviced.
  always @(posedge clk) begin
    if (ref_cmd) ref_req<=#100 0;
    if (zq) zq_req<=#100 0;
    if (take_prd) prd_req<=#100 0;
  end
  integer i;
  initial begin
    repeat(3) @(negedge clk);
    rst=0;
    // Continuous same-row reads, then mixed traffic and random stalls.
    for(i=0;i<4000;i=i+1) begin
      @(negedge clk); #1000;
      use_addr=(accepted<32) ? 1 : ($urandom_range(0,3)!=0);
      tag=i;
      if (accepted>=32) begin
        cmd=$urandom_range(0,1); bank=$urandom_range(0,2);
        row=$urandom_range(0,3); col=$urandom;
        ctl_full=($urandom_range(0,8)==0); cmd_full=($urandom_range(0,8)==0);
        data_full=($urandom_range(0,8)==0); rd_busy=($urandom_range(0,8)==0);
        if (i%149==0) ref_req=1;
        if (i%311==0) zq_req=1;
        if (i%233==0) prd_req=1;
      end else col=i;
    end
    @(negedge clk); #1000;
    use_addr=0; ctl_full=0;cmd_full=0;data_full=0;rd_busy=0;
    repeat(500) @(negedge clk);
    if (issued!=accepted || !refs || !zqs || !prds) $fatal(1,"incomplete drain/coverage");
    if (REUSE && stream_acts>=32) $fatal(1,"no row reuse");
    $display("RESULT: PASS REUSE=%0d accepted=%0d issued=%0d stream_cycles=%0d stream_ACT=%0d REF=%0d ZQ=%0d periodic_cols=%0d",REUSE,accepted,issued,stream_end,stream_acts,refs,zqs,prds);
    $finish;
  end
  initial begin #100000000; $fatal(1,"timeout"); end
endmodule
