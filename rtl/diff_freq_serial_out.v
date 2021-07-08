/* Filename : diff_freq_serial_out.v
 * Simulator: ModelSim - Intel FPGA Edition vsim 2020.1
 * Complier : Quartus Prime - Standard Edition 20.1.1
 *
 * Serially output 32-bit data by different frequency
 */

`include "user_cmd.vh"

module diff_freq_serial_out #(
  parameter       DATA_BIT    = 32,
  parameter       PACK_NUM    = 5,
  parameter       OUTPUT_NUM  = 16,
  parameter [7:0] SLOW_PERIOD = 20,
  parameter [7:0] FAST_PERIOD = 5
) (
  input                   clk_i,
  input                   rst_ni,
  input  [7:0]            data_i,
  input                   rx_done_tick_i,
  output [OUTPUT_NUM-1:0] serial_out_o
);

// Define the states
localparam [2:0] S_IDLE   = 3'b000;
localparam [2:0] S_DATA   = 3'b001;
localparam [2:0] S_CTRL   = 3'b010;
localparam [2:0] S_REPEAT = 3'b011;
localparam [2:0] S_DONE   = 3'b100;

// Signal declaration
// to load the decoder output
reg [2:0]          state_reg,   state_next;
reg [DATA_BIT-1:0] output_reg,  output_next;
reg [DATA_BIT-1:0] freq_reg,    freq_next;
reg [7:0]          sel_out_reg, sel_out_next;
reg                enable_reg,  enable_next;
reg                stop_reg,    stop_next;
reg [1:0]          mode_reg,    mode_next;
reg [7:0]          slow_period_reg, slow_period_next;
reg [7:0]          fast_period_reg, fast_period_next;
reg [7:0]          repeat_reg, repeat_next;
reg                update_tick;

// Decoder signal
wire [DATA_BIT-1:0] decode_output;
wire [DATA_BIT-1:0] decode_freq;
wire [7:0]          decode_sel_out;
wire                decode_enable;
wire                decode_stop;
wire [1:0]          decode_mode;
wire [7:0]          decode_slow_period;
wire [7:0]          decode_fast_period;
wire [7:0]          decode_repeat;
wire [7:0]          decode_cmd;
wire                decode_done_tick;

// Signal to serial out entity
reg [DATA_BIT-1:0]   channel_output[OUTPUT_NUM-1:0];
reg [DATA_BIT-1:0]   channel_output_next[OUTPUT_NUM-1:0];
reg [OUTPUT_NUM-1:0] channel_enable, channel_enable_next;
reg [OUTPUT_NUM-1:0] channel_stop,  channel_stop_next;
reg [1:0]            channel_mode[OUTPUT_NUM-1:0];
reg [1:0]            channel_mode_next[OUTPUT_NUM-1:0];
reg [7:0]            channel_repeat[OUTPUT_NUM-1:0];
reg [7:0]            channel_repeat_next[OUTPUT_NUM-1:0];

// Wire assignment
// Create enable_tick for one-shot
wire [OUTPUT_NUM-1:0] enable_tick;
assign enable_tick = channel_enable & {OUTPUT_NUM{update_tick}};

// for loop variable
integer i;

// Body
// FSMD state & data register
always @(posedge clk_i,  negedge rst_ni) begin
  if (~rst_ni)
    begin
      state_reg       <= S_IDLE;
      output_reg      <= 0;
      sel_out_reg     <= 0;
      enable_reg      <= 0;
      stop_reg        <= 0;
      mode_reg        <= 0;
      freq_reg        <= 0;
      slow_period_reg <= SLOW_PERIOD; // 5MHz
      fast_period_reg <= FAST_PERIOD; // 20MHz
      repeat_reg      <= 0;
      // control bit pattern
      channel_enable  <= 0;
      channel_stop    <= 0;

      for (i = 0; i < OUTPUT_NUM; i = i + 1)
        begin
          channel_mode[i] <= 0;
          channel_repeat[i] <= 0;
          channel_output[i] <= 0;
        end
    end
  else
    begin
      state_reg       <= state_next;
      output_reg      <= output_next;
      sel_out_reg     <= sel_out_next;
      enable_reg      <= enable_next;
      stop_reg        <= stop_next;
      mode_reg        <= mode_next;
      freq_reg        <= freq_next;
      slow_period_reg <= slow_period_next;
      fast_period_reg <= fast_period_next;
      repeat_reg      <= repeat_next;
      // control bit pattern
      channel_enable  <= channel_enable_next;
      channel_stop    <= channel_stop_next;
      
      for (i = 0; i < OUTPUT_NUM; i = i + 1'b1)
        begin
          channel_mode[i] <= channel_mode_next[i];
          channel_repeat[i] <= channel_repeat_next[i];
          channel_output[i] <= channel_output_next[i];
        end
    end
end

// FSMD next-state logic, to update the output pattern
always @(*) begin
  state_next       = state_reg;
  output_next      = output_reg;
  sel_out_next     = sel_out_reg;
  enable_next      = enable_reg;
  stop_next        = stop_reg;
  mode_next        = mode_reg;
  freq_next        = freq_reg;
  slow_period_next = slow_period_reg;
  fast_period_next = fast_period_reg;
  repeat_next      = repeat_reg;
  // control bit pattern
  channel_enable_next = channel_enable;
  channel_stop_next = channel_stop;
  update_tick = 0;
  
  for (i = 0; i < OUTPUT_NUM; i = i + 1'b1)
    begin
      channel_mode_next[i] = channel_mode[i];
      channel_repeat_next[i] = channel_repeat[i];
      channel_output_next[i] = channel_output[i];
    end

  case (state_reg)
    S_IDLE: begin
      if (decode_done_tick)
        begin
          if (decode_cmd == `CMD_DATA)
            begin
              sel_out_next = decode_sel_out;
              output_next  = decode_output;
              state_next   = S_DATA;
            end
          else if (decode_cmd == `CMD_FREQ)
            begin
              freq_next = decode_freq;
            end
          else if (decode_cmd == `CMD_PERIOD)
            begin
              slow_period_next = decode_slow_period;
              fast_period_next = decode_fast_period;
            end
          else if (decode_cmd == `CMD_CTRL)
            begin
              sel_out_next = decode_sel_out;
              enable_next = decode_enable;
              stop_next = decode_stop;
              mode_next = decode_mode;
              state_next = S_CTRL;
            end
          else if (decode_cmd == `CMD_REPEAT)
            begin
              sel_out_next = decode_sel_out;
              repeat_next = decode_repeat;
              state_next = S_REPEAT;
            end
        end
    end

    S_DATA: begin
      state_next = S_IDLE;
      channel_output_next[sel_out_reg] = output_reg;
    end

    S_CTRL: begin
      if (sel_out_reg == OUTPUT_NUM - 1'b1)
        state_next = S_DONE;
      else
        state_next = S_IDLE;

      channel_enable_next[sel_out_reg] = enable_reg;
      channel_stop_next[sel_out_reg] = stop_reg;
      channel_mode_next[sel_out_reg] = mode_reg;
    end

    S_REPEAT: begin
      state_next = S_IDLE;
      channel_repeat_next[sel_out_reg] = repeat_reg;
    end

    S_DONE: begin
      state_next  = S_IDLE;
      update_tick = 1'b1;
    end

    default: state_next = S_IDLE;
  endcase
end

decoder #(
  .DATA_BIT        (DATA_BIT),
  .PACK_NUM        (PACK_NUM)
) decoder_dut (
  .clk_i           (clk_i),
  .rst_ni          (rst_ni),
  .data_i          (data_i),
  .rx_done_tick_i  (rx_done_tick_i),
  .output_pattern_o(decode_output),
  .freq_pattern_o  (decode_freq),
  .sel_out_o       (decode_sel_out),
  .enable_o        (decode_enable),
  .stop_o          (decode_stop),
  .mode_o          (decode_mode),
  .slow_period_o   (decode_slow_period),
  .fast_period_o   (decode_fast_period),
  .repeat_o        (decode_repeat),
  .cmd_o           (decode_cmd),
  .done_tick_o     (decode_done_tick)
);

// Use generate loop to create instances
genvar j;
generate for (j = 0; j < OUTPUT_NUM; j = j + 1'b1)
  begin: serial_out_entity
    serial_out #(
    .DATA_BIT          (DATA_BIT)
    ) channel (
      .clk_i           (clk_i),
      .rst_ni          (rst_ni),
      .enable_i        (enable_tick[j]),
      .stop_i          (channel_stop[j]),
      .mode_i          (channel_mode[j]), // one-shot, repeat
      .output_pattern_i(channel_output[j]),
      .freq_pattern_i  (freq_reg),
      .slow_period_i   (slow_period_reg),
      .fast_period_i   (fast_period_reg),
      .repeat_i        (channel_repeat[j]),
      .serial_out_o    (serial_out_o[j]), // idle state is low
      .done_tick_o     ()
    );
  end
endgenerate

endmodule
