// DDR3 controller for the 7-series MIG PHY. 4:1 mode, rank 0, BL8; no ECC or self-refresh.
`timescale 1ps/1ps

module ddr3_ctrl #(
    parameter TCQ = 100, // unused; retained for MIG parameter compatibility
    parameter ADDR_CMD_MODE = "1T",
    parameter BANK_WIDTH = 3,
    parameter BM_CNT_WIDTH = 2,
    parameter BURST_MODE = "8",
    parameter CL = 5,
    parameter CMD_PIPE_PLUS1 = "ON",
    parameter COL_WIDTH = 12,
    parameter CS_WIDTH = 4,
    parameter CWL = 5,
    parameter DATA_BUF_ADDR_WIDTH = 8,
    parameter DATA_BUF_OFFSET_WIDTH = 1,
    parameter DATA_WIDTH = 64,
    parameter DQ_WIDTH = 64,
    parameter DQS_WIDTH = 8,
    parameter DRAM_TYPE = "DDR3",
    parameter ECC = "OFF",
    parameter ECC_WIDTH = 8,
    parameter MAINT_PRESCALER_PERIOD = 200000,
    parameter MC_ERR_ADDR_WIDTH = 31,
    parameter nBANK_MACHS = 4,
    parameter nCK_PER_CLK = 4,
    parameter nCS_PER_RANK = 1,
    parameter nREFRESH_BANK = 1,
    parameter nSLOTS = 1,
    parameter ORDERING = "NORM",
    parameter PAYLOAD_WIDTH = 64,
    parameter RANK_WIDTH = 2,
    parameter RANKS = 4,
    parameter REG_CTRL = "ON",
    parameter ROW_WIDTH = 16,
    parameter RTT_NOM = "40",
    parameter RTT_WR = "120",
    parameter SLOT_0_CONFIG = 8'b0000_0101,
    parameter SLOT_1_CONFIG = 8'b0000_1010,
    parameter STARVE_LIMIT = 2,
    parameter tCK = 2500,
    parameter tCKE = 10000,
    parameter tFAW = 40000,
    parameter tRAS = 37500,
    parameter tRCD = 12500,
    parameter tREFI = 7800000,
    parameter CKE_ODT_AUX = "FALSE",
    parameter tRFC = 110000,
    parameter tRP = 12500,
    parameter tRRD = 10000,
    parameter tRTP = 7500,
    parameter tWTR = 7500,
    parameter tZQCS = 64,
    parameter tZQI = 128_000_000,
    parameter tPRDI = 1_000_000,
    parameter USER_REFRESH = "OFF",
    parameter ROW_REUSE = 1
  )(
    input clk,
    input rst,
    input [7:0] slot_0_present,
    input [7:0] slot_1_present,

    input [2:0] cmd,
    input [DATA_BUF_ADDR_WIDTH-1:0] data_buf_addr,
    input hi_priority,
    input size,
    input [BANK_WIDTH-1:0] bank,
    input [COL_WIDTH-1:0] col,
    input [RANK_WIDTH-1:0] rank,
    input [ROW_WIDTH-1:0] row,
    input use_addr,
    input [2*nCK_PER_CLK*PAYLOAD_WIDTH-1:0] wr_data,
    input [2*nCK_PER_CLK*DATA_WIDTH/8-1:0] wr_data_mask,
    output accept,
    output accept_ns,
    output [BM_CNT_WIDTH-1:0] bank_mach_next,
    output wire [2*nCK_PER_CLK*PAYLOAD_WIDTH-1:0] rd_data,
    output [DATA_BUF_ADDR_WIDTH-1:0] rd_data_addr,
    output rd_data_en,
    output rd_data_end,
    output [DATA_BUF_OFFSET_WIDTH-1:0] rd_data_offset,
    output wire [DATA_BUF_ADDR_WIDTH-1:0] wr_data_addr,
    output wire wr_data_en,
    output wire [DATA_BUF_OFFSET_WIDTH-1:0] wr_data_offset,
    output mc_read_idle,
    output mc_ref_zq_wip,

    input correct_en,
    input [2*nCK_PER_CLK-1:0] raw_not_ecc,
    input [DQS_WIDTH-1:0] fi_xor_we,
    input [DQ_WIDTH-1:0] fi_xor_wrdata,
    output [MC_ERR_ADDR_WIDTH-1:0] ecc_err_addr,
    output [2*nCK_PER_CLK-1:0] ecc_single,
    output [2*nCK_PER_CLK-1:0] ecc_multiple,

    input app_periodic_rd_req,
    input app_ref_req,
    input app_zq_req,
    input app_sr_req,
    output app_sr_active,
    output app_ref_ack,
    output app_zq_ack,

    output wire [nCK_PER_CLK-1:0] mc_ras_n,
    output wire [nCK_PER_CLK-1:0] mc_cas_n,
    output wire [nCK_PER_CLK-1:0] mc_we_n,
    output wire [nCK_PER_CLK*ROW_WIDTH-1:0] mc_address,
    output wire [nCK_PER_CLK*BANK_WIDTH-1:0] mc_bank,
    output wire [CS_WIDTH*nCS_PER_RANK*nCK_PER_CLK-1:0] mc_cs_n,
    output wire [1:0] mc_odt,
    output wire [nCK_PER_CLK-1:0] mc_cke,
    output wire mc_reset_n,
    output wire [2*nCK_PER_CLK*DQ_WIDTH-1:0] mc_wrdata,
    output wire [2*nCK_PER_CLK*DQ_WIDTH/8-1:0] mc_wrdata_mask,
    output wire mc_wrdata_en,
    output wire mc_cmd_wren,
    output wire mc_ctl_wren,
    output wire [2:0] mc_cmd,
    output wire [5:0] mc_data_offset,
    output wire [5:0] mc_data_offset_1,
    output wire [5:0] mc_data_offset_2,
    output wire [1:0] mc_cas_slot,
    output wire [3:0] mc_aux_out0,
    output wire [3:0] mc_aux_out1,
    output wire [1:0] mc_rank_cnt,
    input phy_mc_ctl_full,
    input phy_mc_cmd_full,
    input phy_mc_data_full,
    input [2*nCK_PER_CLK*DQ_WIDTH-1:0] phy_rd_data,
    input phy_rddata_valid,
    input init_calib_complete,
    input [6*RANKS-1:0] calib_rd_data_offset,
    input [6*RANKS-1:0] calib_rd_data_offset_1,
    input [6*RANKS-1:0] calib_rd_data_offset_2
  );

  function integer cdiv (input integer num, input integer div);
    begin
      if (num <= 0) cdiv = 0;
      else cdiv = (num / div) + (((num % div) > 0) ? 1 : 0);
    end
  endfunction

  function integer at_least (input integer v, input integer lo);
    begin
      at_least = (v < lo) ? lo : v;
    end
  endfunction

  // Timing parameters are in ps unless specified otherwise; tZQI is ns and tZQCS is memory clocks.
  localparam CWL_M = (REG_CTRL == "ON") ? CWL + 1 : CWL;
  localparam nRCD = cdiv(tRCD, tCK);
  localparam nRP = cdiv(tRP, tCK);
  localparam nRAS = cdiv(tRAS, tCK);
  localparam nRFC = cdiv(tRFC, tCK);
  localparam nWR = cdiv(15000, tCK);
  localparam nRTP = at_least(cdiv(tRTP, tCK), 4);

  localparam COL_SLOT = ((CWL_M % 2) == 1) ? 1 : 0;
  localparam ROW_SLOT = ((CWL_M % 2) == 1) ? 0 : 1;
  localparam PRE_SLOT = 2;

  // Convert memory-clock delays to fabric cycles, including the source/destination slot offset.
  localparam K_RCD = at_least(cdiv(nRCD - (COL_SLOT - ROW_SLOT), 4), 1);
  localparam K_RTP = at_least(cdiv(nRTP - (PRE_SLOT - COL_SLOT), 4), 1);
  localparam K_WR = at_least(cdiv(CWL_M + 4 + nWR - (PRE_SLOT - COL_SLOT), 4), 1);
  localparam K_RAS = at_least(cdiv(nRAS - (PRE_SLOT - ROW_SLOT), 4), 1);
  localparam K_RP = at_least(cdiv(nRP + (PRE_SLOT - ROW_SLOT), 4), 2);
  localparam K_RFC = at_least(cdiv(nRFC, 4), 2);
  localparam K_ZQ = at_least(cdiv(tZQCS, 4), 2);

  localparam PRESC_DIV = at_least(MAINT_PRESCALER_PERIOD / (tCK * nCK_PER_CLK), 1);
  localparam REF_TICKS = at_least(tREFI / MAINT_PRESCALER_PERIOD - 1, 1);
  localparam ZQ_TICKS = tZQI / (MAINT_PRESCALER_PERIOD / 1000);
  localparam PRD_TICKS = tPRDI / MAINT_PRESCALER_PERIOD;

  localparam CSW = CS_WIDTH * nCS_PER_RANK;
  localparam TAGW = DATA_BUF_ADDR_WIDTH;

  localparam WR_OFFSET = CWL_M + 2 + COL_SLOT;

  // synthesis translate_off
  initial begin
    if (nCK_PER_CLK != 4) begin
      $display("ddr3_ctrl ERROR: only nCK_PER_CLK = 4 is supported");
      $finish;
    end
    $display("ddr3_ctrl: tCK=%0d ps CL=%0d CWL=%0d | slots row/col/pre = %0d/%0d/%0d | K_RCD=%0d K_RTP=%0d K_WR=%0d K_RAS=%0d K_RP=%0d K_RFC=%0d K_ZQ=%0d | ticks ref/zq/prd = %0d/%0d/%0d",
             tCK, CL, CWL, ROW_SLOT, COL_SLOT, PRE_SLOT, K_RCD, K_RTP, K_WR, K_RAS, K_RP, K_RFC, K_ZQ,
             REF_TICKS, ZQ_TICKS, PRD_TICKS);
  end
  // synthesis translate_on

  assign mc_reset_n = 1'b1;
  assign mc_cmd_wren = 1'b1;
  assign mc_ctl_wren = 1'b1;
  // Bank-machine allocation remains fixed at index 0; verify against the generated MIG UI.
  assign bank_mach_next = {BM_CNT_WIDTH{1'b0}};
  assign ecc_err_addr = {MC_ERR_ADDR_WIDTH{1'b0}};
  assign ecc_single = {2*nCK_PER_CLK{1'b0}};
  assign ecc_multiple = {2*nCK_PER_CLK{1'b0}};
  assign app_sr_active = 1'b0;
  assign rd_data_end = 1'b1;
  assign rd_data_offset = {DATA_BUF_OFFSET_WIDTH{1'b0}};
  assign wr_data_offset = {DATA_BUF_OFFSET_WIDTH{1'b0}};

  assign rd_data = phy_rd_data;
  assign mc_wrdata = wr_data;
  assign mc_wrdata_mask = wr_data_mask;

  wire fire_act, fire_col, fire_pre, fire_ref, fire_zq;
  wire take_req, take_prd, idle_ns;
  wire req_valid, req_rd, req_prd, cur_rd;
  wire next_hit;
  wire [BANK_WIDTH-1:0] req_bank;
  wire [ROW_WIDTH-1:0] req_row;
  wire [COL_WIDTH-1:0] req_col;
  wire [TAGW-1:0] req_tag;
  wire ref_req, zq_pend, prd_pend, any_maint;
  wire col_ok, col2_ok;
  wire rd_fifo_busy, rd_empty;

  ddr3_req_queue #(
    .TCQ (TCQ), .BANK_WIDTH (BANK_WIDTH), .ROW_WIDTH (ROW_WIDTH),
    .COL_WIDTH (COL_WIDTH), .TAGW (TAGW)
  ) u_req (
    .clk (clk), .rst (rst),
    .cmd (cmd), .bank (bank), .row (row), .col (col),
    .data_buf_addr (data_buf_addr), .use_addr (use_addr),
    .accept (accept), .accept_ns (accept_ns),
    .init_calib_complete (init_calib_complete),
    .any_maint (any_maint),
    .take_req (take_req), .take_prd (take_prd),
    .req_valid (req_valid), .next_hit (next_hit),
    .req_rd (req_rd), .req_prd (req_prd),
    .req_bank (req_bank), .req_row (req_row), .req_col (req_col),
    .req_tag (req_tag), .cur_rd (cur_rd)
  );

  ddr3_fsm #(
    .REUSE_ROWS (ROW_REUSE),
    .TCQ (TCQ), .K_RCD (K_RCD), .K_RTP (K_RTP), .K_WR (K_WR), .K_RAS (K_RAS),
    .K_RP (K_RP), .K_RFC (K_RFC), .K_ZQ (K_ZQ)
  ) u_fsm (
    .clk (clk), .rst (rst), .init_calib_complete (init_calib_complete),
    .req_valid (req_valid), .next_hit (next_hit),
    .ref_req (ref_req), .zq_req (zq_pend), .prd_req (prd_pend),
    .cur_rd (cur_rd), .req_prd (req_prd), .col_ok (col_ok), .col2_ok (col2_ok),
    .fire_act (fire_act), .fire_col (fire_col), .fire_pre (fire_pre),
    .fire_ref (fire_ref), .fire_zq (fire_zq),
    .take_req (take_req), .take_prd (take_prd), .idle_ns (idle_ns)
  );

  ddr3_flow #(.TCQ (TCQ)) u_flow (
    .clk (clk), .rst (rst),
    .phy_mc_ctl_full (phy_mc_ctl_full), .phy_mc_cmd_full (phy_mc_cmd_full),
    .phy_mc_data_full (phy_mc_data_full),
    .rd_fifo_busy (rd_fifo_busy), .cur_rd (cur_rd), .req_prd (req_prd),
    .col_ok (col_ok), .col2_ok (col2_ok)
  );

  ddr3_maint #(
    .TCQ (TCQ), .PRESC_DIV (PRESC_DIV), .REF_TICKS (REF_TICKS),
    .ZQ_TICKS (ZQ_TICKS), .PRD_TICKS (PRD_TICKS), .USER_REFRESH (USER_REFRESH)
  ) u_maint (
    .clk (clk), .rst (rst), .init_calib_complete (init_calib_complete),
    .app_ref_req (app_ref_req), .app_zq_req (app_zq_req),
    .app_periodic_rd_req (app_periodic_rd_req),
    .app_ref_ack (app_ref_ack), .app_zq_ack (app_zq_ack),
    .fire_ref (fire_ref), .fire_zq (fire_zq), .take_prd (take_prd),
    .idle_ns (idle_ns), .rd_empty (rd_empty),
    .ref_req (ref_req), .zq_pend (zq_pend), .prd_pend (prd_pend),
    .any_maint (any_maint), .mc_ref_zq_wip (mc_ref_zq_wip)
  );

  ddr3_cmd_out #(
    .TCQ (TCQ), .nCK_PER_CLK (nCK_PER_CLK), .BANK_WIDTH (BANK_WIDTH),
    .ROW_WIDTH (ROW_WIDTH), .COL_WIDTH (COL_WIDTH), .CS_WIDTH (CS_WIDTH),
    .nCS_PER_RANK (nCS_PER_RANK), .RANKS (RANKS),
    .ROW_SLOT (ROW_SLOT), .COL_SLOT (COL_SLOT), .PRE_SLOT (PRE_SLOT),
    .WR_OFFSET (WR_OFFSET)
  ) u_cmd_out (
    .clk (clk),
    .fire_act (fire_act), .fire_col (fire_col), .fire_pre (fire_pre),
    .fire_ref (fire_ref), .fire_zq (fire_zq),
    .cur_rd (cur_rd), .req_bank (req_bank), .req_row (req_row), .req_col (req_col),
    .calib_rd_data_offset (calib_rd_data_offset),
    .calib_rd_data_offset_1 (calib_rd_data_offset_1),
    .calib_rd_data_offset_2 (calib_rd_data_offset_2),
    .mc_ras_n (mc_ras_n), .mc_cas_n (mc_cas_n), .mc_we_n (mc_we_n),
    .mc_address (mc_address), .mc_bank (mc_bank), .mc_cs_n (mc_cs_n),
    .mc_cke (mc_cke), .mc_cmd (mc_cmd),
    .mc_data_offset (mc_data_offset), .mc_data_offset_1 (mc_data_offset_1),
    .mc_data_offset_2 (mc_data_offset_2), .mc_cas_slot (mc_cas_slot),
    .mc_aux_out0 (mc_aux_out0), .mc_aux_out1 (mc_aux_out1), .mc_rank_cnt (mc_rank_cnt)
  );

  ddr3_rd_tag #(.TCQ (TCQ), .TAGW (TAGW)) u_rd_tag (
    .clk (clk), .rst (rst), .init_calib_complete (init_calib_complete),
    .push (fire_col & cur_rd), .push_tag (req_tag), .push_drop (req_prd),
    .phy_rddata_valid (phy_rddata_valid),
    .rd_data_en (rd_data_en), .rd_data_addr (rd_data_addr),
    .busy (rd_fifo_busy), .empty (rd_empty), .mc_read_idle (mc_read_idle)
  );

  ddr3_wr_data #(.TCQ (TCQ), .TAGW (TAGW)) u_wr_data (
    .clk (clk), .rst (rst),
    .wr_fire (fire_col & ~cur_rd), .req_tag (req_tag),
    .wr_data_en (wr_data_en), .wr_data_addr (wr_data_addr),
    .mc_wrdata_en (mc_wrdata_en), .mc_odt (mc_odt)
  );

endmodule
