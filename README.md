YAMP-32 (Yet Another MIPS Processor)
---------------

### 项目背景
NSCSCC2020-个人赛

### 项目思路

* （1）建模，利用C++实现周期精确的微体系结构仿真模型（cpp-cpu-model）
* （2）通过暴力搜索优化参数<sup>[1]</sup>
* （3）进行RTL设计
* （4）若RTL无法满足模型假设，回到（1）修正模型
* （5）若RTL满足设计要求，进行FPGA验证。

### 性能

在 120MHz时钟主频下，运行三组高负载基准程序<sup>[2]</sup>，结果如下

| 测试名称 | 用时<sup>[3]</sup> |
|---|---|
| UTEST_STREAM | 0.055s |
| UTEST_MATRIX | 0.114s |
| UTEST_CRYPTONIGHT| 0.245s |

### 关键词
五级流水、猜测执行、分支预测、Cache、Store Buffer

## Getting started

源码树：thinpad_top.srcs/sources_1/new 内各文件描述如下：

| 源文件 | 描述 | 详细 |
|---|---|---|
| yamp32_parameters.vh | parameters | CPU全局参数定义 |
| yamp32_biu.v | BIU（Bus Interface Unit）总线接口单元 | 实现数据/指令接口的仲裁，实现SRAM读写时序 |
| yamp32_core.v | CPU核心 | CPU顶层设计 |
| yamp32_bpu.v| BPU（Branching Prediction Unit）分支预测单元 | 目前只实现了静态分支预测 |
| yamp32_icache.v | I-Cache | 指令高速缓存（四路组相关、LRU置换、全流水化）|
| yamp32_ifu.v| IFU（Insn Fetching Unit）| 取指单元 |
| yamp32_idu.v| IDU（Insn Decoding Unit）| 译码单元 |
| yamp32_exu.v| EXU（Execution Unit）| 执行单元，包括ALU等子部件 |
| yamp32_lsu.v| LSU（Load & Store Unit）| 访存单元，包括Store Buffer |
| yamp32_wb_mux.v| WB（Writing Back）| 回写单元。实际上为寄存器写入端口提供仲裁 |
| yamp32_regfile.v| Regfile | 寄存器堆 |
| yamp32_ctrl.v| Controller | 流水线控制器。决定各级流水线暂停状态 |
| yamp32_segmap.v | Segment mapping | 完成段映射 |
| bypass_net.v | 旁路网络 | 实现流水线操作数旁路 |

| 源文件 | 描述 | 详细 |
|---|---|---|
| uart.v | UART | 带FIFO的通用异步收发器 |
| fifo_fwft_sclk.v | FWFT（First-word-Fall-Through）| 实现FWFT模式的FIFO（无需读指令，而自动将操作数放到输出端口） |
| xpm_sdpram_bypass.v | xpm简单双口RAM | Xilinx参数化内存封装，增加一层旁路逻辑 |


### 指令集

实现MIPS isa32指令集的一个子集：

1. `ADDIU` 001001ssssstttttiiiiiiiiiiiiiiii
1. `ADDU` 000000ssssstttttddddd00000100001
1. `AND` 000000ssssstttttddddd00000100100
1. `ANDI` 001100ssssstttttiiiiiiiiiiiiiiii
1. `BEQ` 000100ssssstttttoooooooooooooooo
1. `BGTZ` 000111sssss00000oooooooooooooooo
1. `BNE` 000101ssssstttttoooooooooooooooo
1. `J` 000010iiiiiiiiiiiiiiiiiiiiiiiiii
1. `JAL` 000011iiiiiiiiiiiiiiiiiiiiiiiiii
1. `JR` 000000sssss0000000000hhhhh001000
1. `LB` 100000bbbbbtttttoooooooooooooooo
1. `LUI` 00111100000tttttiiiiiiiiiiiiiiii
1. `LW` 100011bbbbbtttttoooooooooooooooo
1. `MUL` 011100ssssstttttddddd00000000010
1. `OR` 000000ssssstttttddddd00000100101
1. `ORI` 001101ssssstttttiiiiiiiiiiiiiiii
1. `SB` 101000bbbbbtttttoooooooooooooooo
1. `SLL` 00000000000tttttdddddaaaaa000000
1. `SRL` 00000000000tttttdddddaaaaa000010
1. `SW` 101011bbbbbtttttoooooooooooooooo
1. `XOR` 000000ssssstttttddddd00000100110
1. `XORI` 001110ssssstttttiiiiiiiiiiiiiiii

延迟槽，无CP0、HI、LO寄存器，无异常、中断，无TLB

### 联系作者
如有疑问，请开issues，或发邮件：diyer175@hotmail.com

## Notes
- \[1\] 即：在给定参数区间内搜索最优解，使得基准程序运行时间之和最小。

- \[2\] 请参考清华监控程序supervisor_v2.01简化版 [https://github.com/z4yx/supervisor-mips32/tree/simplified](https://github.com/z4yx/supervisor-mips32/tree/simplified)

- \[3\] 数据来自NSCSCC在线实验平台

### 参考资料
* L. Hennessy, David A. Patterson. 计算机体系结构：量化方法（第5版）. 机械工业出版社
* D. Sweetman. See MIPS Run Linux (2nd Edition). 屈建勤译
