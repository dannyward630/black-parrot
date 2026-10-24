
/**
 * Directed regression for the LCE request FIFO after a block clean.
 */

`include "bp_common_defines.svh"
`include "bp_me_defines.svh"

`ifndef BP_CFG_FLOWVAR
"BSG-ERROR BP_CFG_FLOWVAR must be set"
`endif

module testbench
  import bp_common_pkg::*;
 #(
   parameter bp_params_e bp_params_p = `BP_CFG_FLOWVAR
   `declare_bp_proc_params(bp_params_p)

   , parameter assoc_p = dcache_assoc_p
   , parameter sets_p = dcache_sets_p
   , parameter block_width_p = dcache_block_width_p
   , parameter fill_width_p = dcache_fill_width_p
   , parameter data_width_p = dcache_data_width_p
   , parameter tag_width_p = dcache_tag_width_p
   , parameter id_width_p = dcache_req_id_width_p
   , parameter sim_clock_period_p = 0
   , parameter sim_reset_cycles_lo_p = 0
   , parameter sim_reset_cycles_hi_p = 0
   , parameter tb_clock_period_p = 0
   , parameter tb_reset_cycles_lo_p = 0
   , parameter tb_reset_cycles_hi_p = 0

   `declare_bp_bedrock_if_widths(paddr_width_p, lce_id_width_p, cce_id_width_p, did_width_p, lce_assoc_p)
   `declare_bp_cache_engine_generic_if_widths(paddr_width_p, tag_width_p, sets_p, assoc_p, data_width_p, block_width_p, fill_width_p, id_width_p, cache)
  );

  `declare_bp_bedrock_if(paddr_width_p, lce_id_width_p, cce_id_width_p, did_width_p, lce_assoc_p);
  `declare_bp_cache_engine_generic_if(paddr_width_p, tag_width_p, sets_p, assoc_p, data_width_p, block_width_p, fill_width_p, id_width_p, cache);

  logic clk_i, reset_i;
  logic [did_width_p-1:0] did_i;
  logic [lce_id_width_p-1:0] lce_id_i;
  bp_lce_mode_e lce_mode_i;
  logic cache_init_done_i, sync_done_i;
  logic busy_o;

  bp_cache_req_s cache_req;
  logic cache_req_v_i, cache_req_yumi_o;
  logic [cache_req_width_lp-1:0] cache_req_i;
  bp_cache_req_metadata_s cache_req_metadata;
  logic [cache_req_metadata_width_lp-1:0] cache_req_metadata_i;
  logic cache_req_metadata_v_i;
  logic cache_req_credits_full_o, cache_req_credits_empty_o;
  logic credit_return_i, cache_req_done_i;

  logic [lce_req_header_width_lp-1:0] lce_req_header_bits;
  bp_bedrock_lce_req_header_s lce_req_header;
  logic [bedrock_fill_width_p-1:0] lce_req_data_o;
  logic lce_req_v_o, lce_req_ready_and_i;

  assign cache_req_i = cache_req;
  assign cache_req_metadata_i = cache_req_metadata;
  assign lce_req_header = lce_req_header_bits;

  always #5 clk_i = ~clk_i;

  bp_lce_req
   #(.bp_params_p(bp_params_p)
     ,.assoc_p(assoc_p)
     ,.sets_p(sets_p)
     ,.block_width_p(block_width_p)
     ,.fill_width_p(fill_width_p)
     ,.data_width_p(data_width_p)
     ,.tag_width_p(tag_width_p)
     ,.id_width_p(id_width_p)
     )
   dut
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.did_i(did_i)
     ,.lce_id_i(lce_id_i)
     ,.lce_mode_i(lce_mode_i)
     ,.cache_init_done_i(cache_init_done_i)
     ,.sync_done_i(sync_done_i)
     ,.busy_o(busy_o)
     ,.cache_req_i(cache_req_i)
     ,.cache_req_v_i(cache_req_v_i)
     ,.cache_req_yumi_o(cache_req_yumi_o)
     ,.cache_req_metadata_i(cache_req_metadata_i)
     ,.cache_req_metadata_v_i(cache_req_metadata_v_i)
     ,.cache_req_credits_full_o(cache_req_credits_full_o)
     ,.cache_req_credits_empty_o(cache_req_credits_empty_o)
     ,.credit_return_i(credit_return_i)
     ,.cache_req_done_i(cache_req_done_i)
     ,.lce_req_header_o(lce_req_header_bits)
     ,.lce_req_data_o(lce_req_data_o)
     ,.lce_req_v_o(lce_req_v_o)
     ,.lce_req_ready_and_i(lce_req_ready_and_i)
     );

  task automatic send_cache_request
    (input bp_cache_req_msg_type_e msg_type, input logic [paddr_width_p-1:0] addr);
    bit accepted;
    begin
      @(negedge clk_i);
      cache_req = '0;
      cache_req.msg_type = msg_type;
      cache_req.addr = addr;
      cache_req.size = e_size_8B;
      cache_req.subop = e_req_store;
      cache_req_v_i = 1'b1;

      accepted = 1'b0;
      for (int cycle = 0; cycle < 20; cycle++)
        begin
          @(posedge clk_i);
          if (cache_req_yumi_o)
            begin
              accepted = 1'b1;
              break;
            end
        end

      if (!accepted)
        $fatal(1, "cache request %0d was not accepted", msg_type);

      @(negedge clk_i);
      cache_req_v_i = 1'b0;
    end
  endtask

  task automatic expect_lce_request
    (input bp_bedrock_req_type_e req_type, input logic [paddr_width_p-1:0] addr);
    bit observed;
    begin
      observed = 1'b0;
      for (int cycle = 0; cycle < 32; cycle++)
        begin
          @(posedge clk_i);
          if (lce_req_v_o && lce_req_ready_and_i)
            begin
              if (lce_req_header.msg_type.req !== req_type)
                $fatal(1, "expected BedRock request %0d, got %0d",
                       req_type, lce_req_header.msg_type.req);
              if (lce_req_header.addr !== addr)
                $fatal(1, "expected address %h, got %h", addr, lce_req_header.addr);
              observed = 1'b1;
              break;
            end
        end

      if (!observed)
        $fatal(1, "timed out waiting for BedRock request %0d", req_type);
    end
  endtask

  task automatic complete_blocking_request;
    begin
      @(negedge clk_i);
      cache_req_done_i = 1'b1;
      credit_return_i = 1'b1;
      @(negedge clk_i);
      cache_req_done_i = 1'b0;
      credit_return_i = 1'b0;
    end
  endtask

  initial
    begin
      clk_i = 1'b0;
      reset_i = 1'b1;
      did_i = '0;
      lce_id_i = '0;
      lce_mode_i = e_lce_mode_normal;
      cache_init_done_i = 1'b0;
      sync_done_i = 1'b0;
      cache_req = '0;
      cache_req_v_i = 1'b0;
      cache_req_metadata = '0;
      cache_req_metadata_v_i = 1'b0;
      credit_return_i = 1'b0;
      cache_req_done_i = 1'b0;
      lce_req_ready_and_i = 1'b1;

      repeat (3) @(negedge clk_i);
      reset_i = 1'b0;
      cache_init_done_i = 1'b1;
      sync_done_i = 1'b1;
      repeat (2) @(negedge clk_i);

      send_cache_request(e_cache_bclean, paddr_width_p'(64'h1000));
      expect_lce_request(e_bedrock_req_uc_wr, paddr_width_p'(64'h1000));

      send_cache_request(e_miss_load, paddr_width_p'(64'h2000));
      expect_lce_request(e_bedrock_req_rd_miss, paddr_width_p'(64'h2000));
      complete_blocking_request();

      send_cache_request(e_cache_bflush, paddr_width_p'(64'h3000));
      expect_lce_request(e_bedrock_req_uc_wr, paddr_width_p'(64'h3000));

      send_cache_request(e_miss_load, paddr_width_p'(64'h4000));
      expect_lce_request(e_bedrock_req_rd_miss, paddr_width_p'(64'h4000));
      complete_blocking_request();

      $display("[BSG-PASS] block clean and flush drain before following misses");
      $finish;
    end

endmodule
