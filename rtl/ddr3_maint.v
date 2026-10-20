// Refresh, ZQCS, and periodic-read scheduling.
`timescale 1ps/1ps

module ddr3_maint #(
    parameter TCQ = 100,
    parameter PRESC_DIV = 16,
    parameter REF_TICKS = 38,
    parameter ZQ_TICKS = 640000,
    parameter PRD_TICKS = 5,
    parameter USER_REFRESH = "OFF"
  )(
    input clk,
    input rst,
    input init_calib_complete,

    input app_ref_req,
    input app_zq_req,
    input app_periodic_rd_req,
    output app_ref_ack,
    output app_zq_ack,

    input fire_ref,
    input fire_zq,
    input take_prd,
    input idle_ns,
    input rd_empty,

    output ref_req,
    output reg zq_pend,
    output reg prd_pend,
    output any_maint,
    output mc_ref_zq_wip
  );

  localparam [15:0] PRESC_LOAD = PRESC_DIV - 1;
  localparam [15:0] REF_LOAD = REF_TICKS - 1;
  localparam [23:0] ZQ_LOAD = (ZQ_TICKS == 0) ? 0 : ZQ_TICKS - 1;
  localparam [15:0] PRD_LOAD = (PRD_TICKS == 0) ? 0 : PRD_TICKS - 1;

  reg [15:0] presc;
  reg [15:0] ref_tmr;
  reg [23:0] zq_tmr;
  reg [15:0] prd_tmr;
  // Refresh debt saturates at eight; this counter does not enforce a service deadline.
  reg [3:0] ref_owed;
  reg ref_user, zq_user;
  reg ref_ack_r, zq_ack_r;
  reg maint_wip;
  reg mc_ref_zq_wip_r;

  wire tick = init_calib_complete & (presc == 16'd0);
  wire ref_due = (USER_REFRESH == "ON") ? 1'b0 : (tick & (ref_tmr == 16'd0));
  wire zq_due = (ZQ_TICKS == 0) ? 1'b0 : (tick & (zq_tmr == 24'd0));
  wire prd_due = (PRD_TICKS == 0) ? 1'b0 : (tick & (prd_tmr == 16'd0));
  wire ref_add = ref_due | app_ref_req;

  assign ref_req = (ref_owed != 4'd0);
  assign any_maint = ref_req | zq_pend | prd_pend;

  always @(posedge clk) begin
    if (rst || !init_calib_complete) begin
      presc <= PRESC_LOAD;
      ref_tmr <= REF_LOAD;
      zq_tmr <= ZQ_LOAD;
      prd_tmr <= PRD_LOAD;
    end else begin
      presc <= (presc == 16'd0) ? PRESC_LOAD : presc - 16'd1;
      if (tick) begin
        ref_tmr <= (ref_tmr == 16'd0) ? REF_LOAD : ref_tmr - 16'd1;
        zq_tmr <= (zq_tmr == 24'd0) ? ZQ_LOAD : zq_tmr - 24'd1;
        prd_tmr <= (prd_tmr == 16'd0) ? PRD_LOAD : prd_tmr - 16'd1;
      end
    end
  end

  always @(posedge clk) begin
    if (rst)
      ref_owed <= (USER_REFRESH == "ON") ? 4'd0 : 4'd1;
    else case ({ref_add, fire_ref})
      2'b10: if (ref_owed != 4'd8) ref_owed <= ref_owed + 4'd1;
      2'b01: ref_owed <= ref_owed - 4'd1;
      default: ref_owed <= ref_owed;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      zq_pend <= (ZQ_TICKS != 0);
      prd_pend <= (PRD_TICKS != 0);
    end else begin
      if (zq_due | app_zq_req) zq_pend <= 1'b1;
      else if (fire_zq) zq_pend <= 1'b0;
      if (prd_due | app_periodic_rd_req) prd_pend <= 1'b1;
      else if (take_prd) prd_pend <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      ref_user <= 1'b0; zq_user <= 1'b0;
      ref_ack_r <= 1'b0; zq_ack_r <= 1'b0;
    end else begin
      if (app_ref_req) ref_user <= 1'b1;
      else if (fire_ref) ref_user <= 1'b0;
      if (app_zq_req) zq_user <= 1'b1;
      else if (fire_zq) zq_user <= 1'b0;
      ref_ack_r <= fire_ref & ref_user;
      zq_ack_r <= fire_zq & zq_user;
    end
  end
  assign app_ref_ack = ref_ack_r;
  assign app_zq_ack = zq_ack_r;

  always @(posedge clk) begin
    if (rst) maint_wip <= 1'b0;
    else if (fire_ref | fire_zq) maint_wip <= 1'b1;
    else if (idle_ns) maint_wip <= 1'b0;
  end

  always @(posedge clk) begin
    if (rst) mc_ref_zq_wip_r <= 1'b0;
    else mc_ref_zq_wip_r <= maint_wip & rd_empty;
  end
  assign mc_ref_zq_wip = mc_ref_zq_wip_r;

endmodule
