# Supervisor kernel.elf at: https://dl.bintray.com/z4yx/supervisor-mips32/v2.0/kernel.elf
#=# oj.resources.kernel_bin = https://dl.bintray.com/z4yx/supervisor-mips32/v2.0/kernel.bin
#=# oj.resources.matrix_bin = https://dl.bintray.com/z4yx/supervisor-mips32/build0602/matrix.bin
#=# oj.resources.crypto_bin = https://dl.bintray.com/z4yx/supervisor-mips32/build0602/crypto.bin
#=# oj.board.n = 3
#=# oj.run_time.max = 20000

from TestcaseBase import *
import random
import traceback
import enum
import time
import struct
import binascii
import base64
from timeit import default_timer as timer


class Testcase(TestcaseBase):
    class State(enum.Enum):
        WaitBoot = enum.auto()
        RunA = enum.auto()
        RunD = enum.auto()
        RunG = enum.auto()
        WaitG = enum.auto()
        Verify = enum.auto()
        Done = enum.auto()

    bootMessage = b'MONITOR for MIPS32 - initialized.'
    runTimeLimit = 15000 # 15s
    recvBuf = b''
    elapsed = -1

    @staticmethod
    def int2bytes(val):
        return struct.pack('<I', val)

    @staticmethod
    def bytes2int(val):
        return struct.unpack('<I', val)[0]

    def endTest(self, timeout=False) -> bool:
        if self.state == self.State.WaitBoot:
            score = 0
        elif self.state == self.State.RunD:
            score = 0.1
        elif self.state in (self.State.RunG, self.State.WaitG):
            score = 0.3
        elif self.state == self.State.Verify:
            score = 0.5
        if self.state == self.State.Done:
            score = 1

        if self.state in (self.State.WaitG, self.State.Verify, self.State.Done):
            if self.elapsed < 0:
                self.elapsed = timer() - self.time_start
            self.log(
                f"Test {self.utest[0]} run for {self.elapsed:.3f}s {'(Timeout)' if timeout else ''}")

        self.finish(score, {
            'details': {
                'name': self.utest[0],
                'max': self.runTimeLimit//1000,
                'elapsed': self.elapsed
            }
        })
        return True

    def stateChange(self, received: bytes) -> bool:
        addr = 0x80100000
        if self.state == self.State.WaitBoot:
            bootMsgLen = len(self.bootMessage)
            self.log(f"Boot message: {str(self.recvBuf)[1:]}")
            if received != self.bootMessage:
                self.log('ERROR: incorrect message')
                return self.endTest()
            elif len(self.recvBuf) > bootMsgLen:
                self.log('WARNING: extra bytes received')
            self.recvBuf = b''

            self.state = self.State.RunA
            for i in range(0, len(self.test_bin), 4):
                Serial << b'A'
                Serial << self.int2bytes(addr+i)
                Serial << self.int2bytes(4)
                Serial << self.test_bin[i:i+4]
            self.log("User program written")

            self.state = self.State.RunD
            self.expectedLen = len(self.test_bin)
            Serial << b'D'
            Serial << self.int2bytes(addr)
            Serial << self.int2bytes(len(self.test_bin))

        elif self.state == self.State.RunD:
            self.log(f"  Program Readback:\n  {binascii.hexlify(self.recvBuf).decode('ascii')}")
            if received != self.test_bin:
                self.log('ERROR: corrupted user program')
                return self.endTest()
            elif len(self.recvBuf) > len(self.test_bin):
                self.log('WARNING: extra bytes received')
            self.recvBuf = b''
            self.log("Program memory content verified")

            self.state = self.State.RunG
            Serial << b'G'
            Serial << self.int2bytes(addr)
            self.expectedLen = 1

        elif self.state == self.State.RunG:
            if received == b'\x80':
                self.log('ERROR: exception occurred')
                return self.endTest()
            elif received != b'\x06':
                self.log('ERROR: start mark should be 0x06')
                return self.endTest()
            self.recvBuf = self.recvBuf[1:]
            self.time_start = timer()
            self.state = self.State.WaitG
            self.expectedLen = 1
            Timer.oneshot(self.runTimeLimit)

        elif self.state == self.State.WaitG:
            self.recvBuf = self.recvBuf[1:]
            if received == b'\x80':
                self.log('ERROR: exception occurred')
                return self.endTest()
            elif received == b'\x07':
                self.elapsed = timer() - self.time_start
                self.state = self.State.Verify

                if self.verifyTestData():
                    self.log("Data memory content verified")
                    self.state = self.State.Done
                else:
                    self.log("ERROR: Data memory content mismatch")
                return self.endTest()
            else:
                self.log(f"ERROR: Invalid byte 0x{received[0]:x} received")
                return self.endTest()

    @Serial # On receiving from serial port
    def recv(self, dataBytes):
        self.recvBuf += dataBytes
        while len(self.recvBuf) >= self.expectedLen:
            end = self.stateChange(self.recvBuf[:self.expectedLen])
            if end:
                break

    @Timer
    def timeout(self):
        self.log(f"ERROR: timeout during {self.state.name}")
        self.endTest(True)

    @started
    def initialize(self):
        self.utest = UTEST_ENTRY[IBOARD]
        self.state = self.State.WaitBoot
        self.expectedLen = len(self.bootMessage)
        self.log(f"=== Test {self.utest[0]} ===")
        kernel_bin = base64.b64decode(RESOURCES['kernel_bin'])
        off, size = self.utest[1], self.utest[2]
        self.test_bin = kernel_bin[off : off+size]
        DIP << 0
        +Reset
        self.preloadTestData()
        BaseRAM[:] = kernel_bin
        Serial.open(1, baud=9600) # NSCSCC
        -Reset
        # booting timeout in 2 seconds
        Timer.oneshot(2000)

    def preloadTestData(self):
        if self.utest[0] == 'STREAM':
            self.testdata = bytes(random.getrandbits(8) for _ in range(0x300000))
            BaseRAM[0x100000::False] = self.testdata
        elif self.utest[0] == 'MATRIX':
            self.testdata = base64.b64decode(RESOURCES['matrix_bin'])
            ExtRAM[:0x30000:False] = self.testdata[:0x30000]
        elif self.utest[0] == 'CRYPTONIGHT':
            self.testdata = base64.b64decode(RESOURCES['crypto_bin'])

    def verifyTestData(self) -> bool:
        if self.utest[0] == 'STREAM':
            return ExtRAM[0x40:0x300000:False] == self.testdata[0x40:0x300000]
        elif self.utest[0] == 'MATRIX':
            return ExtRAM[0x20000:0x30000:False] == self.testdata[0x30000:]
        elif self.utest[0] == 'CRYPTONIGHT':
            return ExtRAM[:0x200000:False] == self.testdata

# > make ON_FPGA=y
# 1:80003000 <UTEST_SIMPLE>:
# 2:8000300c <UTEST_STREAM>:
# 3:8000303c <UTEST_MATRIX>:
# 4:800030c4 <UTEST_CRYPTONIGHT>:
# 5:8000315c <UTEST_1PTB>:
# 6:80003190 <UTEST_2DCT>:
# 7:800031d8 <UTEST_3CCT>:
# 8:80003204 <UTEST_4MDCT>:

#              name, offset in kernel.bin, length
UTEST_ENTRY = [('STREAM', 0x300c, 0x30),
                ('MATRIX', 0x303c, 0x88),
                ('CRYPTONIGHT', 0x30c4, 0x98)]
