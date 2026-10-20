// Registered command encoding for the four-slot MIG PHY interface.
`timescale 1ps/1ps

module ddr3_cmd_out #(
    parameter TCQ = 100,
    parameter nCK_PER_CLK = 4,
    parameter BANK_WIDTH = 3,
    parameter ROW_WIDTH = 14,
    parameter COL_WIDTH = 10,
    parameter CS_WIDTH = 1,
    parameter nCS_PER_RANK = 1,
    parameter RANKS = 1,
    parameter ROW_SLOT = 0,
    parameter COL_SLOT = 1,
    parameter PRE_SLOT = 2,
    parameter WR_OFFSET = 8
  )(
    input clk,

    input fire_act,
    input fire_col,
    input fire_pre,
    input fire_ref,
    input fire_zq,

    input cur_rd,
    input [BANK_WIDTH-1:0] req_bank,
    input [ROW_WIDTH-1:0] req_row,
    input [COL_WIDTH-1:0] req_col,

    input [6*RANKS-1:0] calib_rd_data_offset,
    input [6*RANKS-1:0] calib_rd_data_offset_1,
    input [6*RANKS-1:0] calib_rd_data_offset_2,

    output reg [nCK_PER_CLK-1:0] mc_ras_n,
    output reg [nCK_PER_CLK-1:0] mc_cas_n,
    output reg [nCK_PER_CLK-1:0] mc_we_n,
    output reg [nCK_PER_CLK*ROW_WIDTH-1:0] mc_address,
    output reg [nCK_PER_CLK*BANK_WIDTH-1:0] mc_bank,
    output reg [CS_WIDTH*nCS_PER_RANK*nCK_PER_CLK-1:0] mc_cs_n,
    output reg [nCK_PER_CLK-1:0] mc_cke,
    output reg [2:0] mc_cmd,
    output reg [5:0] mc_data_offset,
    output reg [5:0] mc_data_offset_1,
    output reg [5:0] mc_data_offset_2,
    output reg [1:0] mc_cas_slot,
    output reg [3:0] mc_aux_out0,
    output reg [3:0] mc_aux_out1,
    output reg [1:0] mc_rank_cnt
  );

  localparam CSW = CS_WIDTH * nCS_PER_RANK;
  localparam [1:0] COL_SLOT_V = COL_SLOT;
  localparam [5:0] RD_OFF_ADD = COL_SLOT;
  localparam [5:0] WR_OFF_V = WR_OFFSET;

  // Column encoding reserves A10 for auto-precharge and drives A12 high for BL8.
  reg [15:0] col_a;
  always @(*) begin
    col_a = 16'd0;
    col_a[9:0] = req_col[9:0];
    col_a[10] = 1'b0;
    col_a[11] = (COL_WIDTH > 10) ? req_col[(COL_WIDTH > 10) ? 10 : 0] : 1'b0;
    col_a[12] = 1'b1;
    col_a[13] = (COL_WIDTH > 11) ? req_col[(COL_WIDTH > 11) ? 11 : 0] : 1'b0;
  end

  reg [nCK_PER_CLK-1:0] ras_ns, cas_ns, we_ns;
  reg [nCK_PER_CLK*ROW_WIDTH-1:0] addr_ns;
  reg [nCK_PER_CLK*BANK_WIDTH-1:0] bank_ns;
  reg [CSW*nCK_PER_CLK-1:0] cs_ns;
  reg [2:0] cmd_ns;
  reg [5:0] off_ns, off1_ns, off2_ns;

  wire [CSW-1:0] cs_rank0 = ~{{(CSW-nCS_PER_RANK){1'b0}}, {nCS_PER_RANK{1'b1}}};

  always @(*) begin

    ras_ns = {nCK_PER_CLK{1'b1}};
    cas_ns = {nCK_PER_CLK{1'b1}};
    we_ns = {nCK_PER_CLK{1'b1}};
    addr_ns = {nCK_PER_CLK*ROW_WIDTH{1'b1}};
    bank_ns = {nCK_PER_CLK*BANK_WIDTH{1'b1}};
    cs_ns = {CSW*nCK_PER_CLK{1'b1}};
    cmd_ns = 3'b100;
    off_ns = 6'd0; off1_ns = 6'd0; off2_ns = 6'd0;

    if (fire_act) begin
      ras_ns[ROW_SLOT] = 1'b0;
      addr_ns[ROW_SLOT*ROW_WIDTH +: ROW_WIDTH] = req_row;
      bank_ns[ROW_SLOT*BANK_WIDTH +: BANK_WIDTH] = req_bank;
      cs_ns[ROW_SLOT*CSW +: CSW] = cs_rank0;
    end

    if (fire_ref) begin
      ras_ns[ROW_SLOT] = 1'b0;
      cas_ns[ROW_SLOT] = 1'b0;
      addr_ns[ROW_SLOT*ROW_WIDTH +: ROW_WIDTH] = {ROW_WIDTH{1'b0}};
      bank_ns[ROW_SLOT*BANK_WIDTH +: BANK_WIDTH] = {BANK_WIDTH{1'b0}};
      cs_ns[ROW_SLOT*CSW +: CSW] = cs_rank0;
    end

    if (fire_zq) begin
      we_ns[ROW_SLOT] = 1'b0;
      addr_ns[ROW_SLOT*ROW_WIDTH +: ROW_WIDTH] = {ROW_WIDTH{1'b0}};
      bank_ns[ROW_SLOT*BANK_WIDTH +: BANK_WIDTH] = {BANK_WIDTH{1'b0}};
      cs_ns[ROW_SLOT*CSW +: CSW] = cs_rank0;
    end

    if (fire_col) begin
      cas_ns[COL_SLOT] = 1'b0;
      we_ns[COL_SLOT] = cur_rd;
      addr_ns[COL_SLOT*ROW_WIDTH +: ROW_WIDTH] = col_a[ROW_WIDTH-1:0];
      bank_ns[COL_SLOT*BANK_WIDTH +: BANK_WIDTH] = req_bank;
      cs_ns[COL_SLOT*CSW +: CSW] = cs_rank0;
      if (cur_rd) begin
        cmd_ns = 3'b011;
        off_ns = calib_rd_data_offset[5:0] + RD_OFF_ADD;
        off1_ns = calib_rd_data_offset_1[5:0] + RD_OFF_ADD;
        off2_ns = calib_rd_data_offset_2[5:0] + RD_OFF_ADD;
      end else begin
        cmd_ns = 3'b001;
        off_ns = WR_OFF_V;
        off1_ns = WR_OFF_V;
        off2_ns = WR_OFF_V;
      end
    end

    if (fire_pre) begin
      ras_ns[PRE_SLOT] = 1'b0;
      we_ns[PRE_SLOT] = 1'b0;
      addr_ns[PRE_SLOT*ROW_WIDTH +: ROW_WIDTH] = {ROW_WIDTH{1'b0}};
      bank_ns[PRE_SLOT*BANK_WIDTH +: BANK_WIDTH] = req_bank;
      cs_ns[PRE_SLOT*CSW +: CSW] = cs_rank0;
    end
  end

  // All PHY command outputs have one fabric-cycle latency.
  always @(posedge clk) begin
    mc_ras_n <= ras_ns;
    mc_cas_n <= cas_ns;
    mc_we_n <= we_ns;
    mc_address <= addr_ns;
    mc_bank <= bank_ns;
    mc_cs_n <= cs_ns;
    mc_cmd <= cmd_ns;
    mc_data_offset <= off_ns;
    mc_data_offset_1 <= off1_ns;
    mc_data_offset_2 <= off2_ns;
    mc_cas_slot <= COL_SLOT_V;
    mc_cke <= {nCK_PER_CLK{1'b1}};
    mc_aux_out0 <= {2'b00, (fire_col & ~cur_rd), 1'b0};
    mc_aux_out1 <= 4'b0000;
    mc_rank_cnt <= 2'b00;
  end

endmodule
