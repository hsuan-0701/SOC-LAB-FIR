module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter pCONFIG_REF = 8,
    parameter pTOTAL_WIDTH = pADDR_WIDTH + pDATA_WIDTH,
    parameter pCNT_WIDTH= pADDR_WIDTH - 1,

    parameter pCONFIG_ADDR = 12'b0000_0001_1001 
)
(
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n,

    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A

);

//----------------------------------------------------------------------------------------------------------------------------------------------------------//

reg  [(pDATA_WIDTH-1) :0]                       acc_coeff           , acc_coeff_nxt;
reg  [(pDATA_WIDTH-1) :0]                       x_data_i            , data_A_r,sm_tdata_r;
reg  [(pDATA_WIDTH-1):0]                        config_rdata        , y_buff;
reg  [(pDATA_WIDTH-1):0]                        compute_pointer     , compute_pointer_nxt;

reg  [(pDATA_WIDTH-1):0]                        tbuff_data          , tbuff_data_nxt ;
reg  [(pDATA_WIDTH-1):0]                        rtbuff_data         , rtbuff_data_nxt;
reg  [(pDATA_WIDTH + pADDR_WIDTH-1):0]          buff_data[0:1]      , buff_data_nxt[0:1];


reg  [(pADDR_WIDTH-1):0]                        cnt[0:2]            , cnt_nxt[0:2];
reg  [(pADDR_WIDTH-1):0]                        x_addr_i            , x_addr_num;
reg  [(pADDR_WIDTH-1):0]                        tbuff_addr          , tbuff_addr_nxt ;
reg  [(pADDR_WIDTH-1):0]                        coeff_pointer       ,coeff_pointer_nxt ; 
reg  [(pADDR_WIDTH-1):0]                        mul_coeff           , mul_coeff_nxt;
reg  [(pADDR_WIDTH-1):0]                        h_addr   ,x_pointer , coeff_pointer_tmp ,coeff_last ;
reg  [(pADDR_WIDTH-1):0]                        cnt_transfer,    cnt_transfer_nxt ,  check_cnt,x_pointer_tmp,    x_pointer_nxt , x_pointer_last;
wire [(pADDR_WIDTH-1):0] cnt_one;

reg  [(pCONFIG_REF-1):0]                        tap_A_r ;

wire [(pTOTAL_WIDTH-1):0]                       clear_buff;

reg  [3:0]                                      tap_WE_r            , tap_WE_r_nxt ,WE_h;
reg  [3:0]                                      WE_x;
reg                                             EN_x                , EN_x_nxt;
reg                                             ready[0:1]          , ready_nxt[0:1];
reg                                             buff_valid[0:1]     , buff_valid_nxt[0:1];
reg                                             sm_tvalid_r         , sm_tvalid_r_nxt;
reg                                             sm_stall            , fir_done;
reg                                             arready_nxt;
reg                                             ss_ready_r          , ss_ready_r_nxt;
reg                                             pop_x               , pop_x_last;
reg                                             EN_h                , EN_h_nxt;
reg                                             tbuff_data_v        , tbuff_data_v_nxt;
reg                                             tbuff_addr_v        , tbuff_addr_v_nxt;
reg                                             arready_r           , arready_r_nxt;
reg                                             rvalid_r            , rvalid_r_nxt;
reg                                             rtbuff_valid        , rtbuff_valid_nxt;
reg                                             fir_compute;

reg [2:0]                                       ap_reg              , ap_reg_nxt;
reg [39:0]                                      config_data_length  , config_data_length_nxt ;
reg [39:0]                                      config_tap_num      , config_tap_num_nxt ;
reg                                             awready_r           , awready_r_nxt;
reg                                             wready_r            , wready_r_nxt;

reg                                             fir_run             , fir_run_nxt;
reg                                             sm_last_r , sm_last_r_nxt;
reg                                             shift_nxt;
reg signed [63:0]                               acc_reg , acc_reg_nxt;
reg signed [63:0]                               mul_reg , mul_reg_nxt;
reg signed [63:0]                               x_dat   , h_dat;



//-------------------------------------   PARAMETER SET  -----------------------------------------------------//
assign clear_buff   = { pTOTAL_WIDTH{1'b0} };
assign cnt_one      = { {pCNT_WIDTH{1'b0}}, 1'b1 };

integer i;
//-------------------------------------------------------------------------------------------------------------//
//                                  AXI-STREAM INTERFACE (X input)                          
//-------------------------------------------------------------------------------------------------------------//
assign ss_tready    = ss_ready_r;
assign data_A       = data_A_r; 
assign data_Di      = x_data_i;
assign data_EN      = EN_x;
assign data_WE      = WE_x;

always @(*) begin           //--- data_A_r
    if(!fir_run)begin
        data_A_r = x_addr_i;
    end else begin
        data_A_r = x_pointer ;
    end
end

always @(*)begin            //--- pop_x
    if((buff_valid[0]) && (buff_valid[1]))begin
        if(buff_data[0][(pDATA_WIDTH + pADDR_WIDTH-1) : (pADDR_WIDTH)] < buff_data[1][(pDATA_WIDTH + pADDR_WIDTH-1) : (pADDR_WIDTH)])begin
            pop_x = 1'b0;
        end else begin
            pop_x = 1'b1;
        end
    end else begin
        if(buff_valid[0])begin
            pop_x = 1'b0;
        end else begin
            pop_x = 1'b1;
        end
    end
end

always @(*) begin           //--- WE_x
    if(buff_valid[0] || buff_valid[1])begin
        WE_x[3:0] = 4'b1111;
    end else begin
        WE_x[3:0] = 4'b0000;
    end
end

always @(*) begin           //--- x_data_i
    if(cnt[0] == 32'd0)begin
        x_data_i = 32'd0; 
    end else begin
            x_data_i = buff_data[pop_x][(pDATA_WIDTH-1):0];
    end
end

always @(*) begin           //--- x_addr_i
    if(cnt[0] == 32'd0)begin
        x_addr_i = 32'd0;
    end else begin
        x_addr_i = buff_data[pop_x][(pDATA_WIDTH + pADDR_WIDTH-1): pDATA_WIDTH];
    end
end

always @(*)begin            //--- buff valid[0]  
    if(ss_tvalid && ss_ready_r)begin
            if(!buff_valid[0])begin
                buff_valid_nxt[0] = 1'b1;
            end else if(!buff_valid[1])begin
                if((WE_x[0]) && (!pop_x_last) )begin //write finish signal and check last one(addr)
                    buff_valid_nxt[0] = 1'b0;
                end else begin
                    buff_valid_nxt[0] = buff_valid[0];
                end
            end else if((WE_x[0]) && (!pop_x_last) ) begin //write finish signal and check last one(addr)
                buff_valid_nxt[0] = 1'b0;
            end else begin
                buff_valid_nxt[0] = buff_valid[0];
            end
    end else if ((WE_x[0]) && (!pop_x_last)) begin  // write finish signal and chexk last one(addr)
        buff_valid_nxt[0] = 1'b0;
    end else begin
        buff_valid_nxt[0] = buff_valid[0];
    end
end

always @(*)begin            //--- buff valid[1]  
    if(ss_tvalid && ss_ready_r)begin
        if(!buff_valid[0])begin
            if((WE_x[0]) && (pop_x_last))begin    //write finish signal
                buff_valid_nxt[1] = 1'b0;
            end else begin
                buff_valid_nxt[1] = buff_valid[1];
            end
        end else if(!buff_valid[1])begin
            buff_valid_nxt[1] = 1'b1;
        end else if((WE_x[0]) && (pop_x_last) ) begin // write finish signal and check last one(addr)
            buff_valid_nxt[1] = 1'b0; 
        end else begin
            buff_valid_nxt[1] = buff_valid[1];
        end
    end else if ((WE_x[0]) && (pop_x_last)) begin  // write finish signal and check last one(addr)
        buff_valid_nxt[1] = 1'b0;
    end else begin
        buff_valid_nxt[1] = buff_valid[1];
    end
end

always @(*)begin            //----x_addr_num
   x_addr_num = cnt_nxt[0]- cnt_one ; 
end

always @(*) begin           //--- buff data[0]
    if(ss_tvalid && ss_ready_r)begin
            if(!buff_valid[0])begin
                buff_data_nxt[0] = {(x_addr_num*4), ss_tdata};
            end else begin
                buff_data_nxt[0] = buff_data[0]; 
            end
    end else begin
        buff_data_nxt[0] = buff_data[0];
    end
end

always @(*) begin           //--- buff data[1]
    if(ss_tvalid && ss_ready_r)begin
            if(!buff_valid[0])begin
                buff_data_nxt[1] = buff_data[1];
            end else if(!buff_valid[1])begin
                buff_data_nxt[1] = {(x_addr_num*4), ss_tdata}; 
            end else begin
                buff_data_nxt[1] = buff_data[1];
            end
    end else begin
        buff_data_nxt[1] = buff_data[1];
    end
end

always @(*)begin            //--- ss_ready_r
    if(ss_tvalid)begin
        if(ss_ready_r)begin
            ss_ready_r_nxt = 1'b0;
        end else begin
            if(buff_valid[0] && buff_valid[1])begin
                ss_ready_r_nxt = 1'b0;
            end else begin
                ss_ready_r_nxt = 1'b1;
            end
        end
    end else begin
        ss_ready_r_nxt = 1'b0;
    end
end

always @(*)begin           //--- x_cnt[0]                             
    if(ss_tready && ss_tvalid )begin
        cnt_nxt[0] = cnt[0]+ cnt_one; 
    end else begin
        cnt_nxt[0] = cnt[0];
    end
end

always @(*) begin            //---EN_x
    if(WE_x[0])begin
        EN_x = 1'b1;
    end else if(ap_reg[0])begin
        EN_x = 1'b1;
    end else if(fir_run)begin   
        EN_x = 1'b1;
    end else begin
        EN_x = 1'b0;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin      //---buff valid[0、1]   
   if(!axis_rst_n)begin
        buff_valid[0] <= 1'b0;
        buff_valid[1] <= 1'b0;
   end else begin
        buff_valid[0] <= buff_valid_nxt[0];
        buff_valid[1] <= buff_valid_nxt[1];
   end 
end

always @(posedge axis_clk or negedge axis_rst_n) begin        //--- buff_data[0、1]
    if(!axis_rst_n)begin
        buff_data[0] <= 32'd0;
        buff_data[1] <= 32'd0;
    end else begin
        buff_data[0] <= buff_data_nxt[0] ;
        buff_data[1] <= buff_data_nxt[1] ;
    end    
end

always @(posedge axis_clk or negedge axis_rst_n) begin       //---ss_ready_r
    if(!axis_rst_n)begin
        ss_ready_r <= 1'b0;
    end else begin
        ss_ready_r <= ss_ready_r_nxt; 
    end    
end

always @(posedge axis_clk or negedge axis_rst_n) begin        //---x_cnt[0]
    if(!axis_rst_n)begin
        cnt[0] <= {pADDR_WIDTH{1'd0}};
    end else begin
        cnt[0] <= cnt_nxt[0] ; 
    end    
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---pop_x_last
    if(!axis_rst_n)begin
        pop_x_last <= 1'b0;
    end else begin
        pop_x_last <= pop_x;
    end
end


//-------------------------------------------------------------------------------------------------------//
//                                     AXI-LITE INTERFACE (H input)
//-------------------------------------------------------------------------------------------------------//
assign tap_WE = WE_h;
assign tap_EN = EN_h;
assign tap_Di = tbuff_data;
assign tap_A  = tap_A_r;
assign rdata = rtbuff_data;
assign rvalid = rvalid_r;
assign awready = awready_r;
assign wready  = wready_r;
assign arready = arready_r;

always @(*) begin           //---wready
    if(wready)begin
        wready_r_nxt = 1'b0;
    end else if((!tbuff_data_v)&& wvalid)begin
        wready_r_nxt = 1'b1;
    end else begin
        wready_r_nxt = 1'b0;
    end
end

always @(*)begin            //--- awready
    if(awready)begin
        awready_r_nxt = 1'b0;
    end if((!tbuff_addr_v) && awvalid)begin
        awready_r_nxt = 1'b1;
    end else begin
        awready_r_nxt = 1'b0;
    end
end

always @(*) begin           //---tap_A_r
    if(WE_h)begin
        tap_A_r = tbuff_addr-12'h80;
    end else if(ap_reg[2] && (arvalid && arready_r_nxt)) begin
        tap_A_r = araddr-12'h80;
    end else begin
        if(fir_run)begin
            tap_A_r = coeff_pointer-12'h80;        /////////////////////////////////compute fir
        end else begin
            tap_A_r = clear_buff[(pADDR_WIDTH-1):0];
        end
    end
end

always @(*) begin           //*---rtbuff_data
    if(arvalid) begin
        if(!rvalid)begin
            if(arready_r)begin
                if(araddr[(pCONFIG_REF-1):0] < 8'h19)begin
                    rtbuff_data_nxt = config_rdata;
                end else begin 
                    if(ap_reg[2])begin
                        rtbuff_data_nxt = tap_Do;
                    end else begin
                        rtbuff_data_nxt = 32'hffff_ffff;
                    end
                end
            end else begin
                rtbuff_data_nxt = rtbuff_data;
            end
        end else begin
            rtbuff_data_nxt = rtbuff_data;
        end
    end else begin
        rtbuff_data_nxt = rtbuff_data;
    end
end

always @(*) begin           //*---rtbuff_valid
    if(arready_r)begin
        rtbuff_valid_nxt = 1'b1;
    end else if(rready)begin
        rtbuff_valid_nxt = 1'b0;
    end else begin
        rtbuff_valid_nxt = rtbuff_valid;
    end
end

always @(*) begin           //*---arready_r
    if(arready)begin
        arready_r_nxt = 1'b0;
    end else if(arvalid)begin
        if(((!tbuff_addr_v) && (!tbuff_data_v)) && ((!tbuff_addr_v_nxt) && (!tbuff_data_v_nxt)))begin
            arready_r_nxt = 1'b1;
        end else begin
            arready_r_nxt = 1'b0;
        end
    end else begin
        arready_r_nxt = 1'b0;
    end
end

always @(*) begin           //*---EN_h        
    if(!ap_reg[1])begin
        EN_h_nxt = 1'b1;;        //ap iddle
    end else begin        
        EN_h_nxt = 1'b0;    //ap  iddle
    end
end

always @(*) begin           //*---rvalid_r
    if(rvalid && rready)begin
        rvalid_r_nxt = 1'b0;
    end else if(rtbuff_valid)begin
        rvalid_r_nxt = 1'b1;
    end else begin
        rvalid_r_nxt = 1'b0;
    end
end

always @(*) begin           //*---WE_h
    if(ap_reg[2])begin
        if(tbuff_addr_v && tbuff_data_v)begin
            if(tbuff_addr>12'h18)begin
                WE_h = 4'b1111;
            end else begin
                WE_h = 4'b0000;
            end
        end else begin
            WE_h = 4'b0000;
        end
    end else begin
        WE_h = 4'b0000;
    end
end

always @(*) begin           //*---tbuff_data_v
    if(!WE_h)begin
        if(wvalid && (!tbuff_data_v))begin
            tbuff_data_v_nxt = 1'b1; 
        end else begin
            if(tbuff_addr_v && tbuff_data_v)begin
                if(tbuff_addr <12'h19)begin
                    tbuff_data_v_nxt = 1'b0; 
                end else begin
                    tbuff_data_v_nxt = tbuff_addr_v; 
                end
            end else begin
                tbuff_data_v_nxt = tbuff_data_v;
            end
        end
    end else begin
        tbuff_data_v_nxt = 1'b0;
    end
end

always @(*) begin           //*---tbuff_data
    if(wvalid && (!tbuff_data_v))begin
        tbuff_data_nxt = wdata; 
    end else begin
        tbuff_data_nxt = tbuff_data;
    end
end

always @(*) begin           //*---tbuff_addr_v
    if(!WE_h)begin
        if(awvalid && (!tbuff_addr_v))begin
            tbuff_addr_v_nxt = 1'b1; 
        end else begin
            if(tbuff_addr_v && tbuff_data_v)begin
                if(tbuff_addr <12'h19)begin
                    tbuff_addr_v_nxt = 1'b0; 
                end else begin
                    tbuff_addr_v_nxt = tbuff_addr_v; 
                end
            end else begin
                tbuff_addr_v_nxt = tbuff_addr_v;
            end
        end
    end else begin
        tbuff_addr_v_nxt = 1'b0;
    end
end

always @(*) begin           //*---tbuff_addr
    if(awvalid && (!tbuff_addr_v))begin
        tbuff_addr_nxt = awaddr; 
    end else begin
        tbuff_addr_nxt = tbuff_addr ;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //*---tbuff_data_v
    if(!axis_rst_n)begin
        tbuff_data_v <= 1'b0;
    end else begin
        tbuff_data_v <= tbuff_data_v_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*--- tbuff_data
    if(!axis_rst_n)begin
        tbuff_data <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        tbuff_data <= tbuff_data_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---tbuff_addr_v
    if(!axis_rst_n)begin
        tbuff_addr_v <= 1'b0;
    end else begin
        tbuff_addr_v <= tbuff_addr_v_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*--- tbuff_addr
    if(!axis_rst_n)begin
        tbuff_addr <= clear_buff[(pADDR_WIDTH-1):0];
    end else begin
        tbuff_addr <= tbuff_addr_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---EN_h
    if(!axis_rst_n)begin
        EN_h <= 1'b0 ;
    end else begin
        EN_h <= EN_h_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---arready_r
    if(!axis_rst_n)begin
        arready_r <= 1'b0;
    end else begin
        arready_r <= arready_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---rvalid_r
    if(!axis_rst_n)begin
        rvalid_r <= 1'b0;
    end else begin
        rvalid_r <= rvalid_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //*---rtbuff_valid
    if(!axis_rst_n)begin
        rtbuff_valid <= 1'b0;
    end else begin
        rtbuff_valid <= rtbuff_valid_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*---rtbuff_data
    if(!axis_rst_n)begin
        rtbuff_data <= clear_buff[(pDATA_WIDTH-1):0];
    end else begin
        rtbuff_data <= rtbuff_data_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---wready
    if(!axis_rst_n)begin
        wready_r <= 1'b0;
    end else begin
        wready_r <= wready_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---awready
    if(!axis_rst_n)begin
        awready_r <= 1'b0;
    end else begin
        awready_r <= awready_r_nxt;
    end
end


//--------------------------------------------------------------------------------------------------//
//                                  CONFIGURATION REG 
//-------------------------------------------------------------------------------------------------//

always @(*)begin            //*---config_rdata
    if(arvalid)begin
        if(araddr < 12'h19)begin
            if(araddr == 12'h000)begin //read ap
                config_rdata = {clear_buff[(pDATA_WIDTH-1):3] ,ap_reg};
            end else if(araddr < 12'h0f)begin
                config_rdata = clear_buff[(pDATA_WIDTH-1):0] ;
            end else if(araddr < 12'h15)begin //read data length
                config_rdata = config_data_length[31:0];
            end else if(araddr < 12'h19)begin //read tap num
                config_rdata = config_tap_num[31:0];
            end else begin
                config_rdata = clear_buff[(pDATA_WIDTH-1):0];
            end
        end else begin
            config_rdata = clear_buff[(pDATA_WIDTH-1):0];
        end
    end else begin
        config_rdata = clear_buff[(pDATA_WIDTH-1):0];
    end 
end 

always @(*) begin           //*---ap_reg
    if(fir_done)begin
        ap_reg_nxt = 3'b110;           
    end else if(!ap_reg[2])begin // * ap not idle
        ap_reg_nxt = 3'b000;
    end else begin // * ap idle
        if(ap_reg[0]==1'b1)begin
            ap_reg_nxt = 3'b000;
        end else begin  
            if(tbuff_data_v && tbuff_addr_v)begin // 
                if(tbuff_addr == 12'b0000_0000_0000)begin
                    case(tap_Di[2:0])
                        3'b000: ap_reg_nxt = 3'b100; 
                        3'b001: ap_reg_nxt = 3'b001; 
                        3'b010: ap_reg_nxt = ap_reg; 
                        3'b011: ap_reg_nxt = 3'b001;
                        3'b100: ap_reg_nxt = 3'b100;
                        3'b101: ap_reg_nxt = 3'b001;
                        3'b110: ap_reg_nxt = ap_reg;
                        3'b111: ap_reg_nxt = 3'b001;   
                    endcase
                end else begin
                    ap_reg_nxt = ap_reg;
                end
            end else begin
                ap_reg_nxt = ap_reg;
            end
        end
    end
end

always @(*) begin           //*---config_data_length
    if(!ap_reg[2])begin //* ap not iddle 
        config_data_length_nxt = config_data_length;
    end else begin    //* ap iddle
        if(tbuff_addr_v && tbuff_data_v)begin 
            case(tbuff_addr)
                12'h10: config_data_length_nxt = {8'd0 , tbuff_data};
                12'h11: config_data_length_nxt = {8'd0 , tbuff_data};
                12'h12: config_data_length_nxt = {8'd0 , tbuff_data};
                12'h13: config_data_length_nxt = {8'd0 , tbuff_data};
                12'h14: config_data_length_nxt = {8'd0 , tbuff_data};
                default:  config_data_length_nxt = config_data_length;
            endcase
        end else begin
            config_data_length_nxt = config_data_length;
        end
    end
end

always @(*)begin            //*---tap_num
    if(!ap_reg[2])begin //* ap not idle
        config_tap_num_nxt = config_tap_num ;
    end else begin
        if(tbuff_addr_v && tbuff_data_v)begin 
            case(tbuff_addr)
                12'h14 : config_tap_num_nxt = {8'd0 , tbuff_data};
                12'h15 : config_tap_num_nxt = {8'd0 , tbuff_data};
                12'h16 : config_tap_num_nxt = {8'd0 , tbuff_data};
                12'h17 : config_tap_num_nxt = {8'd0 , tbuff_data};
                12'h18 : config_tap_num_nxt = {8'd0 , tbuff_data};
                default: config_tap_num_nxt = config_tap_num ;
            endcase
        end else begin
            config_tap_num_nxt = config_tap_num ;
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin            //*---ap_reg
    if(!axis_rst_n)begin
        ap_reg <= 3'b100;
    end else begin
        ap_reg <= ap_reg_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //*-- config_data_length
    if(!axis_rst_n)begin
        config_data_length <= 40'd0;
    end else begin
        config_data_length <= config_data_length_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin            //*---tap_num
    if(!axis_rst_n)begin
        config_tap_num <= 40'd0; 
    end else begin
        config_tap_num <= config_tap_num_nxt;
    end
end

//-------------------------------------------------------------------------------------------------//
//                                  FIR_ENGINE (WITH OUTPUT Y) 
//-------------------------------------------------------------------------------------------------//

assign sm_tvalid = sm_tvalid_r;
assign sm_tdata  = sm_tdata_r;
assign sm_last   = sm_last_r;

always @(*) begin       //--- h_dat/x_dat
    x_dat = {{32{data_Do[(pDATA_WIDTH-1)]}}, data_Do};
    h_dat = {{32{tap_Do[(pDATA_WIDTH-1)]}}, tap_Do}; 
end

always @(*) begin           //---fir run
    if(!ap_reg_nxt[2])begin
        fir_run_nxt = 1'b1;
    end else begin
        fir_run_nxt = 1'b0;
    end
end

always @(*) begin            //---x_pointer
    if(cnt[0]<cnt_one)begin
        x_pointer_nxt = x_pointer;
    end else begin            
        if(x_pointer==12'd0)begin
            x_pointer_nxt = h_addr + 12'd4;
        end else begin
            x_pointer_nxt = x_pointer -12'd4;
        end
    end
end

always @(*) begin           //---h_addr
   h_addr = coeff_pointer - 12'h80;
end

always @(*) begin           //---coeff_pointer
    if(x_pointer == 12'd0)begin
        coeff_pointer_nxt = 12'h80;
    end else if(h_addr==12'h7f)begin
        coeff_pointer_nxt = 12'h80;
    end else begin
        coeff_pointer_nxt = coeff_pointer + (cnt_one <<2 );
    end
end

always @(*) begin
        sm_tdata_r = y_buff;
end

always @(*) begin           //---sm_last_r
    if(sm_tvalid_r_nxt)begin
        if(check_cnt == cnt[0])begin
            sm_last_r_nxt = 1'b0;
        end else begin
            sm_last_r_nxt = 1'b0; 
        end
    end else begin
        sm_last_r_nxt = sm_last_r;
    end
end

always @(*) begin           //--- mul_coeff_reg
    if(fir_run)begin
        mul_coeff_nxt = x_pointer_last;
    end else begin
        mul_coeff_nxt = 12'd0;
    end
end

always @(*) begin           //--- mul_coeff_reg
    if(fir_run)begin
        acc_coeff_nxt = mul_coeff;
    end else begin
        acc_coeff_nxt = 12'd0;
    end
end

always @(*)begin            //--- sm_stall
    if(fir_done)begin
        sm_stall = 1'b1;
    end else begin
        sm_stall = 1'b0;
    end
end

always @(*) begin           //--- sm_tvalid
    if(sm_tvalid && sm_tready)begin
        sm_tvalid_r_nxt = 1'b0;
    end else if(acc_coeff == 12'd0)begin
            sm_tvalid_r_nxt = 1'b1;
    end else begin
            sm_tvalid_r_nxt = sm_tvalid;
    end
end

always @(*) begin           //--- acc_reg
    if(ap_reg[0])begin
        acc_reg_nxt = 64'd0;
    end else if(acc_coeff == 12'd0)begin
        acc_reg_nxt = mul_reg;
    end else  begin
        acc_reg_nxt = acc_reg + mul_reg;
    end
end

always @(*) begin           //--- cnt_transfer
    if(sm_tready && sm_tvalid_r_nxt)begin
        cnt_transfer_nxt = cnt_transfer + cnt_one;
    end else begin
        cnt_transfer_nxt = cnt_transfer;
    end
end

always @(*)begin            //--- check_cnt
    check_cnt = cnt_transfer + cnt_one;
end

always @(*) begin           //--- fir_done
    if(fir_run)begin
        if(cnt_transfer==cnt[0])begin
            fir_done = 1'b1;
        end else begin
            fir_done = 1'b0;
        end
    end else begin
        fir_done = 1'b0;
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---acc_reg
    if(!axis_rst_n)begin
        acc_reg     <= 64'd0;
        acc_coeff   <= 12'h80;
    end else if(fir_run && (!sm_stall)) begin
        if(cnt[1] > 12'd1)begin  
            acc_reg     <= acc_reg_nxt;
            acc_coeff   <= acc_coeff_nxt;
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- cnt_transfer
    if(!axis_rst_n)begin
        cnt_transfer <= {(pADDR_WIDTH-1){1'b0}}; 
    end else begin
        cnt_transfer <= cnt_transfer_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- cnt_transfer
    if(!axis_rst_n)begin
        cnt[1] <= cnt_one;
    end else if(fir_run && sm_stall)begin
        cnt[1] <= {(pADDR_WIDTH-1){1'b0}};
    end else if(fir_run)begin
        cnt[1] <= cnt[1]+cnt_one;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- sm_tvalid      
    if(!axis_rst_n)begin
        sm_tvalid_r <= 1'b0;
    end else if(!fir_run)begin
        sm_tvalid_r <= 1'b0;
    end else begin
        sm_tvalid_r <= sm_tvalid_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //--- mul_reg 、 mul_coeff_reg
    if(!axis_rst_n)begin
        mul_reg   <= 64'd0;
        mul_coeff <= 12'h80;
    end else if(fir_run && (!sm_stall))begin
        if(cnt[1] > 12'd1)begin  
            mul_reg  <= (x_dat * h_dat);
            mul_coeff <= mul_coeff_nxt;
        end
    end 
end

always @(posedge axis_clk or negedge axis_rst_n ) begin         //---cieff_last
    if(!axis_rst_n)begin
        coeff_last <= 12'd0;
    end else if(!sm_stall)begin
        coeff_last <= coeff_pointer;
    end
end

always @(posedge axis_clk or negedge axis_rst_n ) begin     //---x_pointer
    if(!axis_rst_n)begin
        x_pointer_last <= 12'd0;
    end else if(!sm_stall) begin
        x_pointer_last <= x_pointer;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---sm_last_r
    if(!axis_rst_n)begin
        sm_last_r <= 1'b0;
    end else if(ap_reg[0])begin
        sm_last_r <= 1'b0;
    end else begin
        sm_last_r <= sm_last_r_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---x_pointer
    if(!axis_rst_n)begin
        x_pointer <= 12'd0;
    end else if(ap_reg[0])begin
        x_pointer <= 12'd0;
    end else if(fir_run)begin
        if(!sm_stall)begin
            x_pointer <= x_pointer_nxt;
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---coeff_pointer
    if(!axis_rst_n)begin
        coeff_pointer <= 12'h80;
    end else if(fir_run) begin
        if(!sm_stall)begin
            coeff_pointer <= coeff_pointer_nxt ;    
        end
    end
end

always @(posedge axis_clk or negedge axis_rst_n)begin           //---fir run
    if(!axis_rst_n)begin
        fir_run <= 1'b0; 
    end else begin
        fir_run <= fir_run_nxt;
    end
end

always @(posedge axis_clk or negedge axis_rst_n) begin          //---y_buff
    if(!axis_rst_n)begin
        y_buff <= 32'd0;
    end else if(acc_coeff==12'd0)begin
        y_buff <= acc_reg;
    end
end
///////////////////////////////////////////////////////////////////////////////////////////////////






endmodule