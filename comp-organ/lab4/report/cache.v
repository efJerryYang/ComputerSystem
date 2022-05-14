`timescale 1ns / 1ps

module cache (
    // ȫ���ź�
    input             clk,
    input             reset,
    // ��CPU���ķ����ź�
    input wire [12:0] addr_from_cpu,    // CPU��ĵ�ַ
    input wire        rreq_from_cpu,    // CPU���Ķ�����
    input wire        wreq_from_cpu,    // CPU����д����
    input wire [ 7:0] wdata_from_cpu,   // CPU����д����
    // ���²��ڴ�ģ�������ź�
    input wire [31:0] rdata_from_mem,   // �ڴ��ȡ������
    input wire        rvalid_from_mem,  // �ڴ��ȡ���ݿ��ñ�־
    // �����CPU���ź�
    output wire [7:0] rdata_to_cpu,     // �����CPU������
    output wire       hit_to_cpu,       // �����CPU�����б�־
    // ������²��ڴ�ģ����ź�
    output reg        rreq_to_mem,      // ������²��ڴ�ģ��Ķ�����
    output reg [12:0] raddr_to_mem,     // ������²�ģ���ͻ�������׵�ַ
    output reg        wreq_to_mem,      // ������²��ڴ�ģ���д����
    output reg [12:0] waddr_to_mem,     // ������²��ڴ�ģ���д��ַ
    output reg [ 7:0] wdata_to_mem      // ������²��ڴ�ģ���д����
);

reg [3:0] current_state, next_state;
localparam READY           = 4'b0000,
           TAG_CHECK_READ  = 4'b0010,
           TAG_CHECK_WRITE = 4'b0100,
           REFILL          = 4'b0001,
           WR_DATA         = 4'b0011;

wire        wea;                                  // Cacheдʹ���ź�
wire [37:0] cache_line_r;                         // ��д��Cache��Cache������
wire [37:0] cache_line;                           // ��Cache�ж�����Cache������

wire [ 5:0] cache_index    = addr_from_cpu[7:2];  // �����ַ�е�Cache����/Cache��ַ
wire [ 4:0] tag_from_cpu   = addr_from_cpu[12:8]; // �����ַ��Tag
wire [ 1:0] offset         = addr_from_cpu[1:0];  // Cache���ڵ��ֽ�ƫ��
wire        valid_bit      = cache_line[37];      // Cache�е���Чλ
wire [ 4:0] tag_from_cache = cache_line[36:32];   // Cache�е�Tag

wire hit  = (tag_from_cache == tag_from_cpu) && valid_bit && (current_state == TAG_CHECK_READ || current_state == TAG_CHECK_WRITE);
wire miss = (tag_from_cache != tag_from_cpu) | (~valid_bit);

// ����Cache�е��ֽ�ƫ�ƣ���Cache����ѡȡCPU������ֽ�����
assign rdata_to_cpu = (offset == 2'b00) ? cache_line[7:0] :
                      (offset == 2'b01) ? cache_line[15:8] :
                      (offset == 2'b10) ? cache_line[23:16] : cache_line[31:24];

assign hit_to_cpu = hit;

// ʹ��Block RAM IP����ΪCache������洢��
blk_mem_gen_0 u_cache (
    .clka   (clk         ),
    .wea    (wea         ),
    .addra  (cache_index ),
    .dina   (cache_line_r),
    .douta  (cache_line  )
);

always @(posedge clk) begin
    if (reset) begin
        current_state <= READY;
    end else begin
        current_state <= next_state;
    end
end

// ����ָ����/PPT��״̬ת��ͼ��ʵ�ֿ���Cache��ȡ��״̬ת��
always @(*) begin
    case(current_state)
        READY: begin
            if (rreq_from_cpu) begin
                next_state = TAG_CHECK_READ;
            end else if(wreq_from_cpu) begin
                next_state = TAG_CHECK_WRITE;
            end else begin
                next_state = READY; 
            end
        end
        TAG_CHECK_READ: begin
            if (miss && rreq_from_cpu) begin
                next_state = REFILL;
            end else begin
                next_state = READY; 
            end
        end
        TAG_CHECK_WRITE: begin
            if (hit) begin
                next_state = WR_DATA;
            end else begin
                next_state = READY; 
            end
        end
        REFILL: begin
            if (rvalid_from_mem) begin 
                next_state = TAG_CHECK_READ;
            end else begin 
                next_state = REFILL;
            end
        end
        WR_DATA: begin
            if (wea) begin
                next_state = TAG_CHECK_WRITE;
            end else begin
                next_state = WR_DATA;
            end
        end
        default: begin
            next_state = READY;
        end
    endcase
end

// ����Block RAM��дʹ���ź�
assign wea = (current_state == REFILL && rvalid_from_mem) || current_state == WR_DATA; 

// ���ɶ�ȡ����������źţ����������ź�rreq_to_mem�Ͷ���ַ�ź�raddr_to_mem
always @(posedge clk) begin
    if (reset) begin
        raddr_to_mem <= 0;
        rreq_to_mem  <= 0;
    end else begin
        case (next_state)
            READY: begin
                raddr_to_mem <= 0;
                rreq_to_mem  <= 0;
            end
            TAG_CHECK_READ: begin
                raddr_to_mem <= 0;
                rreq_to_mem  <= 0;
            end
            REFILL: begin
                raddr_to_mem <= addr_from_cpu;
                rreq_to_mem  <= rreq_from_cpu;
            end
            default: begin
                raddr_to_mem <= 0;
                rreq_to_mem  <= 0;
            end
        endcase
    end
end

// д���д���дֱ�﷨����д����ʱ����Ҫ����Cache�飬ҲҪ�����ڴ�����
wire [31:0] wdata_to_cache = offset == 2'b00 ? {1'b1, tag_from_cpu, cache_line[31: 8], wdata_from_cpu} :
                             offset == 2'b01 ? {1'b1, tag_from_cpu, cache_line[31:16], wdata_from_cpu, cache_line[ 7:0]} :
                             offset == 2'b10 ? {1'b1, tag_from_cpu, cache_line[31:24], wdata_from_cpu, cache_line[15:0]} :
                             offset == 2'b11 ? {1'b1, tag_from_cpu, wdata_from_cpu, cache_line[23:0]} :
                             rdata_from_mem;
assign cache_line_r = wreq_from_cpu ? {1'b1, tag_from_cpu, wdata_to_cache} : {1'b1, tag_from_cpu, rdata_from_mem};

// ���״̬����ʵ���Ժ�������Ǹ�״̬���ϲ���һ������Ϊ��ʵ�Ͼ���ͬһ��״̬���Ĳ�ͬ���֣�����������Ϊ���Ķ�����
always @(posedge clk) begin
    if (reset) begin
        wreq_to_mem  <= 0;
        waddr_to_mem <= 0;
        wdata_to_mem <= 0;
    end else begin
        case (next_state)
            READY: begin
                wreq_to_mem  <= 0;
                waddr_to_mem <= 0;
                wdata_to_mem <= 0;
            end
            TAG_CHECK_WRITE: begin
                wreq_to_mem  <= 0;
                waddr_to_mem <= 0;
                wdata_to_mem <= 0;
            end
            WR_DATA: begin
                wreq_to_mem  <= wreq_from_cpu;
                waddr_to_mem <= addr_from_cpu;
                wdata_to_mem <= wdata_from_cpu;
            end
            default: begin
                wreq_to_mem  <= 0;
                waddr_to_mem <= 0;
                wdata_to_mem <= 0;
            end
        endcase
    end
end

endmodule
