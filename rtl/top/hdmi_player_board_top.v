// HX4S20: SW1 resets, SW2 reloads; external J1 buttons select previous/next.
// The application core keeps its reusable configuration/status interface.
module hdmi_player_board_top #(
    parameter integer CLK_HZ=50000000,
    parameter integer DIAGNOSTIC_LEDS=0,
    parameter integer POWERUP_CYCLES=CLK_HZ/50,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50
)(
    input wire SYS_CLK,
    input wire Reset_n,
    input wire KEY_LOAD_N,
    input wire KEY_PREV_N,
    input wire KEY_NEXT_N,
    input wire SW_AUDIO_N,SW_MUTE_N,
    input wire [3:0] key_img,
    output wire [3:0] LED,
    output wire sd_cs_n,
    output wire sd_sck,
    output wire sd_mosi,
    input wire sd_miso,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P
);
    localparam integer POWER_BITS=POWERUP_CYCLES>1?$clog2(POWERUP_CYCLES):1;
    localparam integer DEBOUNCE_BITS=DEBOUNCE_CYCLES>1?$clog2(DEBOUNCE_CYCLES):1;
    // Explicit FPGA initialization also supplies reset when KEY1 is not held
    // during configuration. After any reset, wait 20 ms at the default clock.
    reg [POWER_BITS-1:0] power_count=0;
    reg power_ready=0;
    always @(posedge SYS_CLK or negedge Reset_n) begin
        if(!Reset_n) begin power_count<=0;power_ready<=0;end
        else if(!power_ready) begin
            if(power_count==POWERUP_CYCLES-1) power_ready<=1;
            else power_count<=power_count+1'b1;
        end
    end
    wire reset_request=!Reset_n || !power_ready;
    reg [1:0] reset_release;
    always @(posedge SYS_CLK or posedge reset_request) begin
        if(reset_request)reset_release<=0;
        else reset_release<={reset_release[0],1'b1};
    end
    wire board_reset_n=reset_release[1];

    reg key_meta,key_sync,key_stable,key_previous;
    reg [DEBOUNCE_BITS-1:0] key_count;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n) begin
            key_meta<=1;key_sync<=1;key_stable<=1;key_previous<=1;key_count<=0;
        end else begin
            key_meta<=KEY_LOAD_N;
            key_sync<=key_meta;
            key_previous<=key_stable;
            if(key_sync==key_stable)key_count<=0;
            else if(key_count==DEBOUNCE_CYCLES-1)begin
                key_stable<=key_sync;key_count<=0;
            end else key_count<=key_count+1'b1;
        end
    end
    wire key_press=key_previous && !key_stable;
    // Two external active-low buttons: independent synchronization and
    // debounce. A held button produces only one press event.
    reg [1:0] nav_meta, nav_sync, nav_stable, nav_previous;
    reg [DEBOUNCE_BITS-1:0] nav_count [0:1];
    integer nav_i;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n) begin
            nav_meta<=2'b11;nav_sync<=2'b11;nav_stable<=2'b11;nav_previous<=2'b11;
            for(nav_i=0;nav_i<2;nav_i=nav_i+1)nav_count[nav_i]<=0;
        end else begin
            nav_meta<={KEY_NEXT_N,KEY_PREV_N};nav_sync<=nav_meta;
            nav_previous<=nav_stable;
            for(nav_i=0;nav_i<2;nav_i=nav_i+1)begin
                if(nav_sync[nav_i]==nav_stable[nav_i])nav_count[nav_i]<=0;
                else if(nav_count[nav_i]==DEBOUNCE_CYCLES-1)begin
                    nav_stable[nav_i]<=nav_sync[nav_i];nav_count[nav_i]<=0;
                end else nav_count[nav_i]<=nav_count[nav_i]+1'b1;
            end
        end
    end
    wire [1:0] nav_press=nav_previous & ~nav_stable;
    // SW3/SW4 are active-low level controls, independently debounced at 20ms.
    reg [1:0] audio_meta,audio_sync,audio_stable;
    reg [DEBOUNCE_BITS-1:0] audio_count[0:1];
    integer audio_i;
    always @(posedge SYS_CLK or negedge board_reset_n)begin
        if(!board_reset_n)begin
            audio_meta<=3;audio_sync<=3;audio_stable<=3;
            for(audio_i=0;audio_i<2;audio_i=audio_i+1)audio_count[audio_i]<=0;
        end else begin
            audio_meta<={SW_MUTE_N,SW_AUDIO_N};audio_sync<=audio_meta;
            for(audio_i=0;audio_i<2;audio_i=audio_i+1)begin
                if(audio_sync[audio_i]==audio_stable[audio_i])audio_count[audio_i]<=0;
                else if(audio_count[audio_i]==DEBOUNCE_CYCLES-1)begin
                    audio_stable[audio_i]<=audio_sync[audio_i];audio_count[audio_i]<=0;
                end else audio_count[audio_i]<=audio_count[audio_i]+1'b1;
            end
        end
    end
    wire audio_error;
    wire request_pending;
    wire load_ready,load_done,load_error,card_initialized,memory_ready;
    wire [7:0] load_error_code;
    wire display_ready,display_underflow;
    wire load_start, navigation_error;
    wire [15:0] selected_file_index, current_file_index, opened_file_index;
    wire select_last;
    image_navigation_ctrl u_navigation (
        .clk(SYS_CLK),.reset_n(board_reset_n),.reload_press(key_press),
        .previous_press(nav_press[0]),.next_press(nav_press[1]),
        .load_ready(load_ready),.load_done(load_done),.load_error(load_error),
        .load_error_code(load_error_code),.start(load_start),
        .select_last(select_last),.opened_index(opened_file_index),
        .file_index(selected_file_index),.current_index(current_file_index),
        .request_pending(request_pending),.report_load_error(navigation_error)
    );

    // These two independent indicators originate in the pixel domain.
    reg [1:0] display_status_meta,display_status_sync;
    reg error_seen;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n)begin
            display_status_meta<=0;display_status_sync<=0;error_seen<=0;
        end else begin
            display_status_meta<={display_ready,display_underflow};
            display_status_sync<=display_status_meta;
            if(navigation_error || audio_error || display_status_sync[0])error_seen<=1;
        end
    end
    // Four discrete LEDs are active high (not the multiplexed digit LEDs).
    // Diagnostic build only: LED1=memory ready, LED2=FIFO underflow,
    // LED3=read-response timeout, LED4=load/refresh error. Reset clears all.
    wire [3:0] debug_error_flags;
    reg [3:0] debug_meta, debug_sync, debug_seen;
    always @(posedge SYS_CLK or negedge board_reset_n) begin
        if(!board_reset_n) begin debug_meta<=0; debug_sync<=0; debug_seen<=0; end
        else begin
            debug_meta<={navigation_error | audio_error,debug_error_flags[2:0]};
            debug_sync<=debug_meta;
            debug_seen<=debug_seen | debug_sync;
        end
    end
    assign LED=DIAGNOSTIC_LEDS ?
        {(|debug_seen[3:2]),debug_seen[1],debug_seen[0],memory_ready} :
        {error_seen,display_status_sync[1],card_initialized,memory_ready};

    hdmi_player_top #(.CLK_HZ(CLK_HZ),.ENABLE_AUDIO(1)) u_player (
        .SYS_CLK(SYS_CLK),.Reset_n(board_reset_n),
        .audio_enable(!audio_stable[0]),.audio_mute(!audio_stable[1]),.audio_error(audio_error),.audio_error_code(),
        .start(load_start),.file_index(selected_file_index),
        .select_last(select_last),.opened_file_index(opened_file_index),.frame_base_addr(21'd0),
        .key_img(key_img),
        .debug_error_flags(debug_error_flags),
        .load_ready(load_ready),.load_busy(),.load_done(load_done),
        .load_error(load_error),.load_error_code(load_error_code),.card_initialized(card_initialized),
        .sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
        .memory_frame_write_done(),.LED(memory_ready),
        .display_ready(display_ready),.display_underflow(display_underflow),
        .HDMI_CLK_P(HDMI_CLK_P),.HDMI_D2_P(HDMI_D2_P),
        .HDMI_D1_P(HDMI_D1_P),.HDMI_D0_P(HDMI_D0_P)
    );
endmodule
