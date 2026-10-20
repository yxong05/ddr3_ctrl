// cmd_out regression.
`timescale 1ps/1ps
module tb_cmd_out;
  parameter ROW_SLOT = 0, COL_SLOT = 1, PRE_SLOT = 2, WR_OFFSET = 8;
  localparam RW = 14, BW = 3;

  reg clk = 0;
  always #5000 clk = ~clk;

  reg [4:0] fire = 0;
  reg cur_rd = 0;
  reg [BW-1:0] bank = 0; reg [RW-1:0] row = 0; reg [9:0] col = 0;
  reg [5:0] calib = 6'd9;
  wire [3:0] ras_n, cas_n, we_n, cs_n, cke;
  wire [4*RW-1:0] addr; wire [4*BW-1:0] ba;
  wire [2:0] mc_cmd; wire [5:0] off, off1, off2; wire [1:0] cas_slot, rank_cnt;
  wire [3:0] aux0, aux1;

  ddr3_cmd_out #(.TCQ(100), .nCK_PER_CLK(4), .BANK_WIDTH(BW), .ROW_WIDTH(RW), .COL_WIDTH(10),
                 .CS_WIDTH(1), .nCS_PER_RANK(1), .RANKS(1),
                 .ROW_SLOT(ROW_SLOT), .COL_SLOT(COL_SLOT), .PRE_SLOT(PRE_SLOT),
                 .WR_OFFSET(WR_OFFSET)) dut (
    .clk(clk),
    .fire_act(fire[0]), .fire_col(fire[1]), .fire_pre(fire[2]), .fire_ref(fire[3]), .fire_zq(fire[4]),
    .cur_rd(cur_rd), .req_bank(bank), .req_row(row), .req_col(col),
    .calib_rd_data_offset(calib), .calib_rd_data_offset_1(calib), .calib_rd_data_offset_2(calib),
    .mc_ras_n(ras_n), .mc_cas_n(cas_n), .mc_we_n(we_n), .mc_address(addr), .mc_bank(ba),
    .mc_cs_n(cs_n), .mc_cke(cke), .mc_cmd(mc_cmd),
    .mc_data_offset(off), .mc_data_offset_1(off1), .mc_data_offset_2(off2),
    .mc_cas_slot(cas_slot), .mc_aux_out0(aux0), .mc_aux_out1(aux1), .mc_rank_cnt(rank_cnt));

  localparam [2:0] NOP = 3'b111, ACT = 3'b011, RD = 3'b101, WR = 3'b100,
                   PRE = 3'b010, REF = 3'b001, ZQCS = 3'b110;

  reg [4:0] fire_p = 0; reg rd_p; reg [BW-1:0] bank_p; reg [RW-1:0] row_p; reg [9:0] col_p;
  always @(posedge clk) begin fire_p <= fire; rd_p <= cur_rd; bank_p <= bank; row_p <= row; col_p <= col; end

  integer errors = 0, n = 0, s, i;
  reg [2:0] code, e_code;
  reg [RW-1:0] a;
  reg [BW-1:0] b;
  integer e_slot;

  task bad (input [255:0] msg);
    begin errors = errors + 1; $display("ERROR %0s (fire = %b)", msg, fire_p); end
  endtask

  always @(negedge clk) if (fire_p !== 5'bx && n > 0) begin

    e_code = NOP; e_slot = -1;
    if (fire_p[0]) begin e_code = ACT; e_slot = ROW_SLOT; end
    if (fire_p[1]) begin e_code = rd_p ? RD : WR; e_slot = COL_SLOT; end
    if (fire_p[2]) begin e_code = PRE; e_slot = PRE_SLOT; end
    if (fire_p[3]) begin e_code = REF; e_slot = ROW_SLOT; end
    if (fire_p[4]) begin e_code = ZQCS; e_slot = ROW_SLOT; end

    for (s = 0; s < 4; s = s + 1) begin
      code = {ras_n[s], cas_n[s], we_n[s]};
      a = addr[s*RW +: RW];
      b = ba[s*BW +: BW];
      if (s != e_slot) begin
        if (code !== NOP || cs_n[s] !== 1'b1) bad("slot is not NOP");
      end else begin
        if (code !== e_code) bad("wrong command code");
        if (cs_n[s] !== 1'b0) bad("chip select is not on");
        case (e_code)
          ACT: if (a !== row_p || b !== bank_p) bad("ACT row/bank");
          RD, WR: if (a[9:0] !== col_p || a[10] !== 1'b0 || b !== bank_p) bad("READ/WRITE column/A10/bank");
          PRE: if (a[10] !== 1'b0 || b !== bank_p) bad("PRE A10/bank");
          ZQCS: if (a[10] !== 1'b0) bad("ZQCS A10");
          default: ;
        endcase
      end
    end

    if (mc_cmd !== (fire_p[1] ? (rd_p ? 3'b011 : 3'b001) : 3'b100)) bad("mc_cmd");
    if (fire_p[1] && rd_p && off !== calib + COL_SLOT) bad("read data offset");
    if (fire_p[1] && !rd_p && off !== WR_OFFSET) bad("write data offset");
    if (cke !== 4'b1111) bad("CKE");
    if (cas_slot !== COL_SLOT) bad("mc_cas_slot");
  end

  initial begin
    for (i = 0; i < 5000; i = i + 1) begin
      @(posedge clk); #1000;
      fire = 5'd0;
      if ($urandom_range(0, 1)) fire[$urandom_range(0, 4)] = 1'b1;
      cur_rd = $urandom; bank = $urandom; row = $urandom; col = $urandom;
      n = n + 1;
    end
    $display("cycles checked = %0d, errors = %0d", n, errors);
    if (errors == 0) $display("RESULT: PASS"); else $display("RESULT: FAIL");
    $finish;
  end
endmodule
