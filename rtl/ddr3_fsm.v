// Command sequencing with optional same-row reuse. K_* delays are in fabric clocks.
`timescale 1ps/1ps

module ddr3_fsm #(
    parameter TCQ = 100,
    parameter REUSE_ROWS = 0,
    parameter K_RCD = 1,
    parameter K_RTP = 1,
    parameter K_WR = 4,
    parameter K_RAS = 3,
    parameter K_RP = 2,
    parameter K_RFC = 13,
    parameter K_ZQ = 16
  )(
    input clk,
    input rst,
    input init_calib_complete,

    input req_valid,
    input next_hit,
    input ref_req,
    input zq_req,
    input prd_req,

    input cur_rd,
    input req_prd,
    input col_ok,
    input col2_ok,

    output reg fire_act,
    output reg fire_col,
    output reg fire_pre,
    output reg fire_ref,
    output reg fire_zq,
    output reg take_req,
    output reg take_prd,
    output idle_ns
  );

  localparam [3:0] S_INIT = 4'd0,
                   S_IDLE = 4'd1,
                   S_ACT = 4'd2,
                   S_COL = 4'd3,
                   S_COL2 = 4'd4,
                   S_PRE = 4'd5,
                   S_REF = 4'd6,
                   S_ZQ = 4'd7,
                   S_WAIT = 4'd8;

  // PRE/REF/ZQ waits exclude the idle cycle before the next ACT.
  localparam [7:0] W_RCD = K_RCD;
  localparam [7:0] W_RP = K_RP - 1;
  localparam [7:0] W_RFC = K_RFC - 1;
  localparam [7:0] W_ZQ = K_ZQ - 1;
  localparam [7:0] RAS_LOAD = K_RAS - 1;
  localparam [7:0] RTP_LOAD = K_RTP - 1;
  localparam [7:0] WR_LOAD = K_WR - 1;

  reg [3:0] state, state_ns;
  reg [3:0] wait_next, wait_next_ns;
  reg [7:0] wait_cnt, wait_cnt_ns;

  reg [7:0] ras_cnt;
  reg [7:0] pre_cnt;

  // Seven reuses plus the initial request give at most eight bursts per ACT.
  reg [3:0] row_reuse_count;
  wire maintenance_pending = ref_req || zq_req || prd_req;
  wire can_reuse_row = REUSE_ROWS && next_hit && !req_prd &&
                       !maintenance_pending && (row_reuse_count < 4'd7);

  always @(posedge clk) begin
    if (rst || fire_act) row_reuse_count <= 4'd0;
    else if (take_req && state == S_PRE)
      row_reuse_count <= row_reuse_count + 4'd1;
  end

  // k=1 enters nxt on the next cycle; longer delays spend k-1 cycles in S_WAIT.
  task goto_after (input [3:0] nxt, input [7:0] k);
    begin
      if (k <= 8'd1) state_ns = nxt;
      else begin
        state_ns = S_WAIT;
        wait_next_ns = nxt;
        wait_cnt_ns = k - 8'd2;
      end
    end
  endtask

  always @(*) begin
    state_ns = state;
    wait_next_ns = wait_next;
    wait_cnt_ns = wait_cnt;
    fire_act = 1'b0; fire_col = 1'b0; fire_pre = 1'b0; fire_ref = 1'b0; fire_zq = 1'b0;
    take_req = 1'b0; take_prd = 1'b0;

    case (state)
      S_INIT:
        if (init_calib_complete) state_ns = S_IDLE;

      S_IDLE:
        if (req_valid) begin
          take_req = 1'b1;
          state_ns = S_ACT;
        end
        else if (ref_req) state_ns = S_REF;
        else if (zq_req) state_ns = S_ZQ;
        else if (prd_req) begin
          take_prd = 1'b1;
          state_ns = S_ACT;
        end

      S_ACT: begin
        fire_act = 1'b1;
        goto_after(S_COL, W_RCD);
      end

      S_COL:
        if (col_ok) begin
          fire_col = 1'b1;
          state_ns = req_prd ? S_COL2 : S_PRE;
        end

      S_COL2:
        if (col2_ok) begin
          fire_col = 1'b1;
          state_ns = S_PRE;
        end

      S_PRE:
        if (pre_cnt == 8'd0 && ras_cnt == 8'd0) begin
          // Keep the recovery waits before loading another same-row request.
          if (can_reuse_row) begin
            take_req = 1'b1;
            state_ns = S_COL;
          end else begin
            fire_pre = 1'b1;
            goto_after(S_IDLE, W_RP);
          end
        end

      S_REF: begin
        fire_ref = 1'b1;
        goto_after(S_IDLE, W_RFC);
      end

      S_ZQ: begin
        fire_zq = 1'b1;
        goto_after(S_IDLE, W_ZQ);
      end

      S_WAIT:
        if (wait_cnt == 8'd0) state_ns = wait_next;
        else wait_cnt_ns = wait_cnt - 8'd1;

      default: state_ns = S_INIT;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= S_INIT;
      wait_next <= S_IDLE;
      wait_cnt <= 8'd0;
    end else begin
      state <= state_ns;
      wait_next <= wait_next_ns;
      wait_cnt <= wait_cnt_ns;
    end
  end

  assign idle_ns = (state_ns == S_IDLE);

  always @(posedge clk) begin
    if (rst) ras_cnt <= 8'd0;
    else if (fire_act) ras_cnt <= RAS_LOAD;
    else if (ras_cnt != 8'd0) ras_cnt <= ras_cnt - 8'd1;
  end

  always @(posedge clk) begin
    if (rst) pre_cnt <= 8'd0;
    else if (fire_col) pre_cnt <= cur_rd ? RTP_LOAD : WR_LOAD;
    else if (pre_cnt != 8'd0) pre_cnt <= pre_cnt - 8'd1;
  end

endmodule
