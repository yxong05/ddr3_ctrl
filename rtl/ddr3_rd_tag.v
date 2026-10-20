// FIFO associating issued READs with UI buffer tags.
`timescale 1ps/1ps

module ddr3_rd_tag #(
    parameter TCQ = 100,
    parameter TAGW = 5
  )(
    input clk,
    input rst,
    input init_calib_complete,

    input push,
    input [TAGW-1:0] push_tag,
    input push_drop,

    input phy_rddata_valid,
    output rd_data_en,
    output [TAGW-1:0] rd_data_addr,

    output busy,
    output empty,
    output mc_read_idle
  );

  // Each entry is {drop, tag}; drop marks maintenance data that must not reach the UI.
  reg [TAGW:0] rdq [0:15];
  reg [4:0] rd_head, rd_tail;
  reg [TAGW:0] rd_out;
  reg mc_read_idle_r;

  wire [4:0] rd_level = rd_head - rd_tail;
  wire rd_pop = phy_rddata_valid & ~empty;
  wire [4:0] rd_tail_ns = rd_pop ? rd_tail + 5'd1 : rd_tail;
  wire [TAGW:0] rd_din = {push_drop, push_tag};

  assign empty = (rd_head == rd_tail);
  assign busy = (rd_level >= 5'd12);

  always @(posedge clk) begin
    if (rst) begin
      rd_head <= 5'd0;
      rd_tail <= 5'd0;
      // Bypass the memory when an enqueue supplies the new oldest entry.
      rd_out <= {(TAGW+1){1'b0}};
    end else begin
      if (push) begin
        rdq[rd_head[3:0]] <= rd_din;
        rd_head <= rd_head + 5'd1;
      end
      rd_tail <= rd_tail_ns;

      rd_out <= (push && (rd_head == rd_tail_ns)) ? rd_din : rdq[rd_tail_ns[3:0]];
    end
  end

  assign rd_data_en = rd_pop & ~rd_out[TAGW];
  assign rd_data_addr = rd_out[TAGW-1:0];

  always @(posedge clk) begin
    if (rst) mc_read_idle_r <= 1'b0;
    else mc_read_idle_r <= empty & init_calib_complete;
  end
  assign mc_read_idle = mc_read_idle_r;

endmodule
