// Write-data request pipeline and ODT control.
`timescale 1ps/1ps

module ddr3_wr_data #(
    parameter TCQ = 100,
    parameter TAGW = 5
  )(
    input clk,
    input rst,

    input wr_fire,
    input [TAGW-1:0] req_tag,

    output reg wr_data_en,
    output reg [TAGW-1:0] wr_data_addr,

    output reg mc_wrdata_en,
    // Rank-0 ODT covers the command cycle and the following fabric cycle.
    output reg [1:0] mc_odt
  );

  // Relative to wr_fire: PHY command +1 cycle, UI data request +2, PHY data enable +3.
  reg wr_p1, wr_p2;

  reg [TAGW-1:0] wr_tag_p1;

  always @(posedge clk) begin

    if (rst) begin

      wr_p1 <= 1'b0;
      wr_p2 <= 1'b0;
      wr_data_en <= 1'b0;
      mc_wrdata_en <= 1'b0;
    end else begin
      wr_p1 <= wr_fire;
      wr_p2 <= wr_p1;
      wr_data_en <= wr_p1;
      mc_wrdata_en <= wr_p2;
    end

    // Tag registers need no reset; wr_data_en qualifies their contents.
    wr_tag_p1 <= req_tag;
    wr_data_addr <= wr_tag_p1;

    mc_odt <= {1'b0, (wr_fire | wr_p1)};
  end

endmodule
