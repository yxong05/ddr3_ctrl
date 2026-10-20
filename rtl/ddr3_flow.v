// Column-command admission using registered PHY FIFO status.
`timescale 1ps/1ps

module ddr3_flow #(
    parameter TCQ = 100
  )(
    input clk,
    input rst,
    input phy_mc_ctl_full,
    input phy_mc_cmd_full,
    input phy_mc_data_full,
    input rd_fifo_busy,
    input cur_rd,
    input req_prd,
    output col_ok,
    output col2_ok
  );

  reg ctl_full_r, cmd_full_r, ofs_rdy_r;
  wire ofs_rdy_ns = ~cmd_full_r & ~ctl_full_r & ~(phy_mc_data_full & ~cur_rd);

  always @(posedge clk) begin
    if (rst) begin
      ctl_full_r <= 1'b0;
      cmd_full_r <= 1'b0;
      ofs_rdy_r <= 1'b0;
    end else begin
      ctl_full_r <= phy_mc_ctl_full;
      cmd_full_r <= phy_mc_cmd_full;
      ofs_rdy_r <= ofs_rdy_ns;
    end
  end

  // The first periodic READ checks both readiness stages; the second uses the registered stage.
  assign col_ok = ofs_rdy_r & ~(cur_rd & rd_fifo_busy) & (~req_prd | ofs_rdy_ns);
  assign col2_ok = ofs_rdy_r;

endmodule
