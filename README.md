YAMP-32 (Yet Another MIPS Processor)
---------------

### 项目背景
NSCSCC2020-个人赛

### 设计思路

* （1）建模：利用C++实现周期精确级模拟器（cpp-cpu-model）
* （2）通过暴力搜索优化参数<sup>[1]</sup>（自动调参）
* （3）根据优化结果进行RTL设计
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
五级流水、猜测执行、分支预测、Cache、Write Buffer

### Getting started

源码树：thinpad_top.srcs/sources_1/new 内各文件描述如下：

| 源文件 | 描述 | 详细 |
|---|---|---|
| yamp32_parameters.vh | parameters | CPU全局参数定义 |
| yamp32_biu.v | BIU（Bus Interface Unit）总线接口单元 | 实现数据/指令接口的仲裁，实现SRAM读写时序 |
| yamp32_core.v | CPU核心 | CPU顶层设计 |
| yamp32_bpu.v| BPU（Branching Prediction Unit）分支预测单元 | 目前只实现了最简单的动态分支预测 |
| yamp32_icache.v | I-Cache | 指令高速缓存（四路组相关、LRU置换、全流水化）|
| yamp32_ifu.v| IFU（Insn Fetching Unit）| 取指单元 |
| yamp32_idu.v| IDU（Insn Decoding Unit）| 译码单元 |
| yamp32_exu.v| EXU（Execution Unit）| 执行单元，包括ALU等子部件 |
| yamp32_lsu.v| LSU（Load & Store Unit）| 访存单元，包括Write Buffer |
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



#### 如何使用C++模型

这里的C++模型可模拟MIPS指令的运行，精确计算Cache Miss或分支预测失败带来的开销，在此基础上实现自动调参，从而为微架构设计与优化提供量化依据。

下面是编译运行该C++模型的指南。

#####  **Phase 1**: 编译

准备Linux环境（如果在Windows下，可以考虑使用Cygwin、WSL或MinGW），在源码根目录下运行如下命令：

```shell
cd cpp-cpu-model
mkdir build && cd ./build
cmake ..
make -j8
```
编译成功将在build目录生成可执行文件cpu（cpu.exe）。



##### **Phase 2**: 运行测试集

在build目录使用如下命令，模拟监控程序的运行。模拟器将自动发送终端命令，启动测试用例

```shell
./cpu kernel.bin STREAM
```

其中`kernel.bin`为监控程序supervisor的二进制映像。对于supervisor v2.01，可在其源码根目录中kernel/kernel.bin中找到。

`STREAM`为测试用例的名称，在NSCSCC2020中，共有STREAM、MATRIX、CRYPTONIGHT三个测试用例。

当检测到supervisor从终端返回的执行完毕状态后，模拟器将打印出各种统计信息，包括Cache命中率，分支预测命中率等，可为量化研究提供依据，如下为程序运行结果的一个实例：

```
Boot message:MONITOR for MIPS32 - initialized.
User program written
  Program Readback:

40 80 04 3c 41 80 05 3c 42 80 06 3c 60 00 07 24
25 18 00 00 1a 00 67 10 80 40 03 00 40 52 03 00
21 40 88 00 21 50 aa 00 25 48 00 00 12 00 27 11
40 12 09 00 00 00 0f 8d 21 10 c2 00 25 60 40 01
25 58 00 00 09 00 67 11 01 00 6b 25 00 00 8d 8d
00 00 4e 8c 02 68 ed 71 04 00 42 24 04 00 8c 25
21 68 cd 01 f7 ff 00 10 fc ff 4d ac 01 00 29 25
ee ff 00 10 00 02 08 25 e6 ff 00 10 01 00 63 24
08 00 e0 03 00 00 00 00
Program memory content verified
Data memory content verified
=======
Clks: 12516672
Secs: 0.125167
=======
-------clk: 12516672
DCache
Cache dump:
        Hit: 0
        Miss: 0
                Writeback: 0
        P(h) = -nan
ICache
Cache dump:
        Hit: 8962251
        Miss: 7
                Writeback: 0
        P(h) = 0.999999
==================
BPU dump:
        JR
        JR Hit:732
        JR Miss:2
        JR P(h):0.997275
        BCC
        BCC Hit:1788467
        BCC Miss:10015
        BCC P(h):0.994431
sb_hit =0 sb_miss=2
```



##### **Phase 3**：自动调参

  若要使用自动调参功能，请手动修改cpu.cc，找到main() 函数中的如下函数调用：

| 函数              | 功能                                     |
| ----------------- | ---------------------------------------- |
| optimise_icache() | 优化ICache参数（P_WAYS、P_SETS、P_LINE） |
| optimise_dcache() | 优化DCache参数（P_WAYS、P_SETS、P_LINE） |

取消cpu.cc中相应注释，重新编译运行，开始自动调参。

读取输出结果。对搜索得到的局部最优解做如下解释：Cache需要(1<<P_WAYS)路、(1<<P_SETS)行、每行(1<<P_LINE)字节。



##### 实现细节

##### 1. 自动调参目标函数

目前我们选取CPU运行三个测试用例所需时钟数之和作为目标函数。

##### 2. 自动调参搜索边界

ICache参数搜索边界：

| 参数   | 最小值 | 最大值 | 步进 |
| ------ | ------ | ------ | ---- |
| P_WAYS | 1      | 4      | 1    |
| P_SETS | 1      | 13     | 1    |
| P_LINE | 1      | 13     | 1    |

DCache 参数搜索边界：

| 参数   | 最小值 | 最大值 | 步进 |
| ------ | ------ | ------ | ---- |
| P_WAYS | 1      | 7      | 1    |
| P_SETS | 1      | 20     | 1    |
| P_LINE | 1      | 20     | 1    |

在BRAM资源占用和调参程序运行时间可接受的情况下，您可以可适当增大搜索边界的范围，以期寻到更优解。

##### 3. 自动调参局限性

自动调参只在有限的测试用例（STREAM、MATRIX和）中进行，只能确保这三个测试用例取得优化解。



##### **Phase 4: 如何设置断点，拿到感兴趣的数据**

请参考cpu.cc中cpu_clk()函数中”Set breakpoints here...“部分代码。



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

### 

### 联系作者
如有疑问，欢迎开issues，或发邮件：diyer175@hotmail.com

## Notes
- \[1\] 即：在给定参数区间内搜索最优解，使得基准程序运行时间之和最小。

- \[2\] 请参考清华监控程序supervisor_v2.01简化版 [https://github.com/z4yx/supervisor-mips32/tree/simplified](https://github.com/z4yx/supervisor-mips32/tree/simplified)

- \[3\] 数据来自NSCSCC在线实验平台

### 参考资料
* L. Hennessy, David A. Patterson. 计算机体系结构：量化方法（第5版）. 机械工业出版社
* D. Sweetman. See MIPS Run Linux (2nd Edition). 屈建勤译
