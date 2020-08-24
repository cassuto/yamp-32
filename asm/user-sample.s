.set noreorder
.set noat
.globl __start
.section text

__start:
.text
    lui $a0, 0x8040       # a0 = 0x80400000
	li $t0, 1			  # t0 = i
	li $t1, 0x31111
	li $t2, 0			  # t2 = sum
	
	# for(; t0 <= t1; ++t0)	
MAIN_LOOP:
	li $t3, 32
	move $t4, $t0 		 # t4 = i

	# Loop expanding to 32
#define SRL_4() 		\
	and $t5, $t4, 0x1 	;\
	addu $t2, $t5 		;\
	srl $t4, 1 			;\
	and $t5, $t4, 0x1 	;\
	addu $t2, $t5 		;\
	srl $t4, 1 			;\
	and $t5, $t4, 0x1 	;\
	addu $t2, $t5 		;\
	srl $t4, 1 			;\
	and $t5, $t4, 0x1 	;\
	addu $t2, $t5
#   srl

#define SRL_8() 		\
	SRL_4() 			;\
	srl $t4, 1 			;\
	SRL_4() 			;\
	srl $t4, 1
	
#define SRL_32() \
	SRL_8() ;\
	SRL_8() ;\
	SRL_8() ;\
	SRL_4() ;\
	srl $t4, 1 ;\
	SRL_4()
#   srl
	
	SRL_32()
	
	beq $t0, $t1, DONE
	addu $t0, 1				# ++t0
	b MAIN_LOOP				# continue
	nop
	
DONE:
	sw $t2, 0($a0)
	
    jr    $ra
    ori   $zero, $zero, 0 # nop
