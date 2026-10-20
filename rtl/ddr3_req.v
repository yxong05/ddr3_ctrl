// Single-request capture with the MIG UI address/tag handshake.
`timescale 1ps/1ps

module ddr3_req #(
    parameter TCQ = 100,
    parameter BANK_WIDTH = 3,
    parameter ROW_WIDTH = 14,
    parameter COL_WIDTH = 10,
    parameter TAGW = 5
  )(
    input clk,
    input rst,

    input [2:0] cmd,
    input [BANK_WIDTH-1:0] bank,
    input [ROW_WIDTH-1:0] row,
    input [COL_WIDTH-1:0] col,
    input [TAGW-1:0] data_buf_addr,
    input use_addr,
    output accept,
    output accept_ns,

    input init_calib_complete,
    input idle_ns,
    input any_maint,
    input take_req,
    input take_prd,

    output req_valid,
    output reg req_rd,
    output reg req_prd,
    output reg [BANK_WIDTH-1:0] req_bank,
    output reg [ROW_WIDTH-1:0] req_row,
    output reg [COL_WIDTH-1:0] req_col,
    output reg [TAGW-1:0] req_tag,
    output cur_rd
  );

  reg accept_r;

  // Block new requests while maintenance is pending so it can run at the next idle boundary.
  assign accept_ns = init_calib_complete & idle_ns & ~any_maint;
  assign accept = accept_r;
  assign req_valid = accept_r & use_addr;
  assign cur_rd = req_rd | req_prd;

  always @(posedge clk) begin
    if (rst) accept_r <= 1'b0;
    else accept_r <= accept_ns;
  end

  // Address and command precede use_addr by one cycle; data_buf_addr accompanies use_addr.
  reg [2:0] cmd_d1;
  reg [BANK_WIDTH-1:0] bank_d1;
  reg [ROW_WIDTH-1:0] row_d1;
  reg [COL_WIDTH-1:0] col_d1;

  always @(posedge clk) begin
    cmd_d1 <= cmd;
    bank_d1 <= bank;
    row_d1 <= row;
    col_d1 <= col;
  end

  always @(posedge clk) begin
    if (rst) begin
      req_rd <= 1'b0;
      req_prd <= 1'b0;
      req_bank <= {BANK_WIDTH{1'b0}};
      req_row <= {ROW_WIDTH{1'b0}};
      req_col <= {COL_WIDTH{1'b0}};
      req_tag <= {TAGW{1'b0}};
    end else if (take_req) begin
      req_rd <= (cmd_d1[1:0] == 2'b01);
      req_prd <= 1'b0;
      req_bank <= bank_d1;
      req_row <= row_d1;
      req_col <= col_d1;
      req_tag <= data_buf_addr;
    end else if (take_prd) begin
      req_prd <= 1'b1;
    end
  end

endmodule
