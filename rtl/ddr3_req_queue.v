// Four pending requests plus one active request; requests remain in arrival order.
`timescale 1ps/1ps

module ddr3_req_queue #(
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
  input any_maint,
  
  input take_req,
  input take_prd,
  output req_valid,
  output next_hit,
  
  output reg req_rd,
  output reg req_prd,
  output reg [BANK_WIDTH-1:0] req_bank,
  output reg [ROW_WIDTH-1:0] req_row,
  output reg [COL_WIDTH-1:0] req_col,
  output reg [TAGW-1:0] req_tag,
  output cur_rd
);

  
  localparam QUEUE_DEPTH = 4;
  localparam ENTRY_WIDTH = 1 + BANK_WIDTH + ROW_WIDTH + COL_WIDTH + TAGW;

  reg [ENTRY_WIDTH-1:0] queue [0:QUEUE_DEPTH-1];
  reg [1:0] write_ptr;
  reg [1:0] read_ptr;
  reg [2:0] count;
  reg accept_r;

  reg [2:0] cmd_d1;
  reg [BANK_WIDTH-1:0] bank_d1;
  reg [ROW_WIDTH-1:0] row_d1;
  reg [COL_WIDTH-1:0] col_d1;

  wire enqueue = accept_r && use_addr;
  wire dequeue = take_req && req_valid;
  wire [3:0] count_next = {1'b0, count} + enqueue - dequeue;

  
  wire [ENTRY_WIDTH-1:0] next_request = queue[read_ptr];
  wire next_read;
  wire [BANK_WIDTH-1:0] next_bank;
  wire [ROW_WIDTH-1:0] next_row;
  wire [COL_WIDTH-1:0] next_col;
  wire [TAGW-1:0] next_tag;

  assign {next_read, next_bank, next_row, next_col, next_tag} = next_request;
  assign req_valid = (count != 0);

  
  
  wire same_bank = (next_bank == req_bank);
  wire same_row = (next_row == req_row);
  wire same_direction = (next_read == req_rd);

  assign next_hit = req_valid && !req_prd && same_bank && same_row && same_direction;

  
  
  assign cur_rd = req_rd | req_prd;

  
  
  
  // Registered acceptance reserves space using occupancy after this cycle.
  assign accept_ns = !rst && init_calib_complete && !any_maint &&
                     (count_next < QUEUE_DEPTH);
  assign accept = accept_r;

  // Address precedes use_addr by one cycle; the tag arrives with use_addr.
  always @(posedge clk) begin
    cmd_d1 <= cmd;
    bank_d1 <= bank;
    row_d1 <= row;
    col_d1 <= col;
  end

  always @(posedge clk) begin
    if (rst) begin
      write_ptr <= 2'd0;
      read_ptr <= 2'd0;
      count <= 3'd0;
      accept_r <= 1'b0;
    end else begin
      accept_r <= accept_ns;
      count <= count_next[2:0];

      if (enqueue) begin
        queue[write_ptr] <= {
          (cmd_d1[1:0] == 2'b01), bank_d1, row_d1, col_d1, data_buf_addr
        };
        write_ptr <= write_ptr + 2'd1;
      end

      if (dequeue)
        read_ptr <= read_ptr + 2'd1;
    end
  end

  
  
  always @(posedge clk) begin
    if (rst) begin
      req_rd <= 1'b0;
      req_prd <= 1'b0;
      req_bank <= {BANK_WIDTH{1'b0}};
      req_row <= {ROW_WIDTH{1'b0}};
      req_col <= {COL_WIDTH{1'b0}};
      req_tag <= {TAGW{1'b0}};
    end else if (dequeue) begin
      req_rd <= next_read;
      req_bank <= next_bank;
      req_row <= next_row;
      req_col <= next_col;
      req_tag <= next_tag;
      req_prd <= 1'b0;
    end else if (take_prd) begin
      
      req_prd <= 1'b1;
    end
  end
endmodule
