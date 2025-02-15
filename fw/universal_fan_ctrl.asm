; Universal Fan Controller
; Attiny202 firmware
; by Tomek Szczęsny 2025
; Build with avra

; Fuse bits:
; - Set osc to 16MHz

.nolist
.include "tn202def.inc"
.list

; temperatures are stored as 16-bit signed integers
; representing temperature in units of (1/16) deg C
; [t11 t10 t9 t8 t7 t6 t5 t4] : [t3 t2 t1 t0 t-1 t-2 t-3 t-4]

.equ owp = 7				; One-Wire pin number on port A

.def arg1 = r25				; procedure io
.def arg0 = r24
.def tempminh = r23			; 25% PWM temperature
.def tempminl = r22
.def tmph = r21				; Temporary values
.def tmpl = r20
.def slope = r19			; The slope constant for PWM calculation
.def temph = r17			; Current temperature
.def templ = r16
.def tempmaxh = r9			; 100% PWM temperature
.def tempmaxl = r8
.def zero = r7				; Always zero

.macro wait12u
	push arg0		; 1 cycle
	ldi arg0, 1		; 1 cycle
	rcall delay		; 8 cycles in total
	pop arg0		; 2 cycles
.endm
.macro wait15u
	push arg0		; 1 cycle
	ldi arg0, 2		; 1 cycle
	rcall delay		; 11 cycles in total
	pop arg0		; 2 cycles
.endm
.macro wait60u
	push arg0		; 1 cycle
	ldi arg0, 17		; 1 cycle
	rcall delay		; 56 cycles in total
	pop arg0		; 2 cycles
.endm
.macro wait67u
	push arg0		; 1 cycle
	ldi arg0, 19		; 1 cycle
	rcall delay		; 62 cycles in total
	pop arg0		; 2 cycles
	nop			; 1 cycle
.endm
.macro wait480u
	push arg0		; 1 cycle
	ldi arg0, 157		; 1 cycle
	rcall delay		; 476 cycles in total
	pop arg0		; 2 cycles
.endm

; One Wire macros, may destroy r30 data

.macro owh				; One wire goes high
	sbi VPORTA_OUT, owp
.endm
.macro owl				; One wire goes low
	cbi VPORTA_OUT, owp
.endm
.macro owz				; One wire goes hi-Z (input)
	cbi VPORTA_DIR, owp
.endm
.macro owe				; One wire output enabled
	sbi VPORTA_DIR, owp
.endm
.macro owr				; One wire read input to flag T
	in r30, VPORTA_IN
	bst r30, owp
.endm

; ------------------------------------------------------------ 

.cseg
.org 000000				; Interrupt Vector
	rjmp Init			; Reset

.org TCB0_INT_vect			; The main loop at 5Hz
	rjmp Loop

.org INT_VECTORS_SIZE+1
Init:
	ldi tmpl, Low(RAMEND)		
	out CPU_SPL, tmpl		; Stack pointer init

	clr zero			; Populate "always zero" register

	ldi tmpl, CPU_CCP_IOREG_gc	; Unlocking Configuration Change Protection
	out CPU_CCP, tmpl
	ldi tmpl, 0b00000111		; Clock prescaler dividing by 16 -> 1MHz operation
	sts CLKCTRL_MCLKCTRLB, tmpl
	ldi tmpl, 0b00000001		; Enabling sleep mode "Idle"
	sts SLPCTRL_CTRLA, tmpl

; ------------------------------------------------------------ 

	; Sampling BOM settings set by resistor dividers

	ldi tmpl, 0x05			; Enable ADC, 10 bit
	sts ADC0_CTRLA, tmpl
	ldi tmpl, 0x02			; Accumulation of 4 results
	sts ADC0_CTRLB, tmpl
	ldi tmpl, 0b01010000		; Reduced sampling cap, Vref=Vdd, clk divided by 2
	sts ADC0_CTRLC, tmpl
	ldi tmpl, 0b01000000		; 32 clock cycles init delay
	sts ADC0_CTRLD, tmpl
	ldi tmpl, 31			; Sampling period of 32 clk cycles (maximum)
	sts ADC0_SAMPCTRL, tmpl
	ldi tmpl, 0x02			; Selects PA2 input (MT value)
	sts ADC0_MUXPOS, tmpl
	rcall ADCpoll			; Capture the value

	lds tmph, ADC0_RESH		; Load the ADC result, raw setting on lower nibble
	ldi tmpl, 80			; *16*5, shift and scale setting
	mul tmph, tmpl
	movw tempmaxl, r0
	ldi tmpl, 0xE0			; Offset the value by +30C (30*16)
	ldi tmph, 0x01
	add tempmaxl, tmpl
	adc tempmaxh, tmph

	ldi tmpl, 0x00			; Disable Accumulation
	sts ADC0_CTRLB, tmpl
	ldi tmpl, 0x03			; Selects PA3 input (TR value)
	sts ADC0_MUXPOS, tmpl
	rcall ADCpoll			; Capture the value

	lds tmph, ADC0_RESH		; Load the ADC result, raw setting on low 2 bits
	inc tmph			; Calculate the low threshold (tempmin)
	clr tempminh
	ldi tempminl, 0x14		; 1.25C constant, to be multiplied by 2 (TR+1) times
	ldi slope, 0x60			; 6*16 const, to be divided by 2 (TR+1) times
	tempminloop:			; (TR+1) loop
	lsl tempminl
	rol tempminh
	lsr slope
	dec tmph
	brne tempminloop
	movw tmpl, tempmaxl		; Calculate tempmin = tempmax - dT
	sub tmpl, tempminl
	sbc tmph, tempminh
	movw tempminl, tmpl		; move the result to tempmin

	sts ADC0_CTRLA, zero		; Disable ADC

; ------------------------------------------------------------ 

	; Set up the counters
	; TCA will generate the PWM signal at WO1 pin, at 100Hz or so
	; TCB will generate 5Hz interrupts for temperature acquisition

	; TCA setup
	ldi tmpl, 0x05			; TCA enabled, divider by 4 (=250kHz) 
	sts TCA0_SINGLE_CTRLA, tmpl
	ldi tmpl, 0b00100011		; WO1 enabled, Single Slope PWM mode 
	sts TCA0_SINGLE_CTRLB, tmpl
	ldi tmpl, 0x02			; Set PA1 as output
	sts PORTA_DIRSET, tmpl
	ldi tmpl, 0xC3			; Set the period to 100Hz (2499) 
	sts TCA0_SINGLE_TEMP, tmpl
	ldi tmpl, 0x09
	sts TCA0_SINGLE_PERH, tmpl

	; TCB Setup
	ldi tmpl, 0x07
	sts TCB0_CTRLA, tmpl		; TCB enabled, 250kHz ckock from TCA_CLK
	sts TCB0_CTRLB, zero		; Periodic interrupt mode
	ldi tmpl, 0xC3			; Set 5Hz period (49999)
	sts TCB0_CCMPH, tmpl
	ldi tmpl, 0x4F
	sts TCB0_CCMPL, tmpl
	ldi tmpl, 0x01			; Enable Interrupt on Capture
	sts TCB0_INTCTRL, tmpl

; ------------------------------------------------------------ 

	; Configuration of ADC for capturing AVR internal temperature

	ldi tmpl, 0x10			; Vref = 1.1V
	sts VREF_CTRLA, tmpl
	ldi tmpl, 0x01			; Enable ADC
	sts ADC0_CTRLA, tmpl
	ldi tmpl, 0x06			; Accumulation of 64 results
	sts ADC0_CTRLB, tmpl
	ldi tmpl, 0b01000000		; Reduced sampling cap, internal Vref, clk divided by 2
	sts ADC0_CTRLC, tmpl
	ldi tmpl, 0b00100000		; 16 clock cycles init delay (min 16 at this clk rate)
	sts ADC0_CTRLD, tmpl
	ldi tmpl, 14			; Sampling period of 2+14 clk cycles
	sts ADC0_SAMPCTRL, tmpl
	ldi tmpl, 0x1E			; Selects temperature sensor as the ADC input
	sts ADC0_MUXPOS, tmpl

	rcall AVRtemp			; Set up the temp registers with an initial value
	movw templ, tmpl
	rcall PWMset

; ------------------------------------------------------------------------------

	sei				; Enable interrupts
				
	; Fall through to the Oblivion, awaiting interrupts

; ------------------------------------------------------------------------------ 

Oblivion:
	sleep
	rjmp Oblivion

; ------------------------------------------------------------------------------

Loop:					; The main loop with periodic temperature captures
					; and PWM updates
	; Goes like this:
	; Collect the result of DS18 temp conversion
	; - If not responsing, go to Fallback
	; Configure DS18
	; Launch DS18 conversion
	; Set PWM
	; Return, where it's doomed to sleep
	; Launch a new conversion

	; Collect the result of DS18 temp conversion
	rcall OWresetpulse
	brts Fallback			; If no response, fall back to AVR sensor
	ldi arg0, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi arg0, 0xBE			; Send "Read Scratchpad"
	rcall OWsendbyte

	rcall OWreadbyte		; the first byte read is the lower half
	push arg0			; We store these results for later
	rcall OWreadbyte
	push arg0

	; Configure DS18
	rcall OWresetpulse
	brts Fallback			; If no response, fall back to AVR sensor

	ldi arg0, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi arg0, 0x4E			; Send "Write Scratchpad" (the third byte is config)	
	rcall OWsendbyte
	;ldi arg0, 0x00			; Send two dummy bytes	
	rcall OWsendbyte
	;ldi arg0, 0x00			; Send two dummy bytes	
	rcall OWsendbyte
	ldi arg0, 0x3F			; Configuration byte 0x3F (10-bit result, conv. time 187.5ms)
	rcall OWsendbyte

	; Launch DS18 conversion
	rcall OWresetpulse
	brts Fallback			; If no response, fall back to AVR sensor
	
	ldi arg0, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi arg0, 0x44			; Send "Convert Temperature"
	rcall OWsendbyte

	; We assume the conversion should be complete at the next 5Hz cycle

	pop arg1
	pop arg0
	;andi arg1, 0b11111111		; Sanitizing raw data from DS18B20 stored in tmp
	andi arg0, 0b11111100		; For 10-bit readouts
	rcall Facc			; Accumulate the result into temp registers
	rcall PWMset			; Compute and update PWM setting
	reti

Fallback:				; Read AVR temperature sensor instead
	rcall AVRtemp			; Get the AVR temperature to tmp registers
	rcall Facc			; Accumulate the result into temp registers
	rcall PWMset			; Compute and update PWM setting
	reti

; ------------------------------------------------------------------------------

PWMset:					; Compute and update PWM setting
	; TCA period is 2499 ticks
	; Input value is within 0-319 range
	; let's set CMP = 579 + (6*IN)
	; This gives 23.16% minimum PWM

	push tmpl
	push tmph

	cp  templ, tempminl		; Check if temperature below the low threshold
	cpc temph, tempminh
	brsh pwm1			; If not, skip to the next stage
	clr tmpl
	clr tmph
	rjmp pwmfinal

	pwm1:
	cp  tempmaxl, templ		; Check if temperature above the high threshold
	cpc tempmaxh, temph
	brsh pwm2			; If not, skip to the next stage
	ser tmpl
	ser tmph
	rjmp pwmfinal

	pwm2:				; The "linear region"
	; tmp is at most 9 bits long (0-319)
	; slope fits into 6 bits (6 - 6*8)
	; The result is 15 bits long
	movw tmpl, templ		; Calculate the difference against the tempmin
	sub tmpl, tempminl
	sbc tmph, tempminh
	mul tmpl, slope			; Multiply it by slope (scale depending on TR)
	sbrc tmph, 0			; Multiply the 9th temp bit by slope
	add r1, slope

	ldi tmpl, 0x44			; Add a constant 580
	ldi tmph, 0x02			; And move result to tmp
	add tmpl, r0
	adc tmph, r1

	pwmfinal:
	sts TCA0_SINGLE_TEMP, tmpl	; Set the PWM 
	sts TCA0_SINGLE_CMP1BUFH, tmph
	ldi tmpl, 0x04			; Apply CMP1BUF
	sts TCA0_SINGLE_CTRLFSET, tmpl

	pop tmph
	pop tmpl
	ret

; ------------------------------------------------------------------------------

AVRtemp:				; Capture temperature from the AVR internal sensor
					; Returns it to arg[1:0]
	rcall ADCpoll			
	push tmpl
	push tmph

	lds arg0, ADC0_RESH		; Load ADC results, reversed reg order for a reason
	lds arg1, ADC0_RESL
	ldi tmpl, 0x40			; Dividing by 64 with appropriate rounding
	add arg1, tmpl			; Because 64x accumulation has been enabled
	adc arg0, zero
	rol arg1			; Rotate both registers, 2 positions 
	rol arg0
	rol arg1
	rol arg0
	rol arg1
	andi arg1, 0x03

	; Temperature readout compensation, as per datasheet instructions
	; However it's not clear whether the expected input value is 8 or 10 bit
	; Assuming 10 bit for now

	lds tmpl, SIGROW_TEMPSENSE1	; Read offset
	clr tmph			; expanding signed tmpl to tmph:tmpl
	sbrc tmpl, 7
	ser tmph
	sub arg0, tmpl			; Applying offset
	sbc arg1, tmph

	lds tmpl, SIGROW_TEMPSENSE0	; Read slope
	mul tmpl, arg1			; Multiply the HS half of arg
	movw arg0, r0
	mul tmpl, arg0			; Multiplying the LS half
	add arg0, r1			; Add LS to the final result (assuming no overflow)
	adc arg1, zero

					; Shift data into a proper position (<<4)
	rol r0
	rol arg0
	rol arg1
	rol r0
	rol arg0
	rol arg1
	rol r0
	rol arg0
	rol arg1
	rol r0
	rol arg0
	rol arg1

	; At this point, arg1:arg0 contains temperature in Kelvins. 
	; The maximum value is 2^12 K, so no overflow is expected
	; No negative values are expected either because physics.

	subi arg0, 0b00010010		; Converting to deg C
	sbci arg1, 0b00010001
	
	pop tmph
	pop tmpl

	ret

; ------------------------------------------------------------------------------

Facc:					; Filtered accumulation of arg in temp
					; Performs temp = (3/4)*temp + (1/4)*arg[1:0]

	sub arg0, templ			; tmp -= temp;
	sbc arg1, temph

	adiw arg0, 0x02			; Correct division rounding error
	asr arg1			; tmp /= 4; (Preserving the sign)
	ror arg0
	asr arg1
	ror arg0
	add templ, arg0			; temp += tmp
	adc temph, arg1
	ret

; ------------------------------------------------------------------------------

ADCpoll:				; Wait for the ADC conversion to complete
	push tmpl
	ldi tmpl, 0x01			; Start a conversion
	sts ADC0_COMMAND, tmpl
	pollloop:
	lds tmpl, ADC0_COMMAND		; when ADC_COMMAND is all zeroes
	tst tmpl			; The conversion is complete
	breq pollloop
	pop tmpl
	ret

; ------------------------------------------------------------------------------

OWsendbyte:				; Sends arg0 byte
	push tmpl
	ldi tmpl, 8
	owz
	owl
	owsbloop:
	owe
	sbrc arg0, 0			; Zero is the 60+us pull
	owz				; Skip shortening the pull if zero
	wait60u
	owz
	lsr arg0			; Shift data right
	dec tmpl			
	brne owsbloop			; Loop it
	pop tmpl
	ret

; ------------------------------------------------------------------------------

OWreadbyte:				; Reads a byte to arg0
	push tmpl
	ldi tmpl, 8
	owz
	owl
	owrbloop:
	owe				; Pull low for 2us (>1us)
	lsl arg0			; shift register 
	owz
	wait12u
	owr
	bld arg0, 0			; Store received bit in arg0
	wait60u
	dec tmpl			
	brne owrbloop			; Loop it
	pop tmpl
	ret

; ------------------------------------------------------------------------------

OWresetpulse:				; Sends a reset pulse
	owl				; returns "1" in T flag if no response
	owe
	wait480u
	wait15u
	owz				; Delaying for DS' response
	wait67u				; the safe read window is 60-75us
	owr				; Reading presence response (T flag)
	brtc PC + 2			; If there is a response, skip early return
	ret
	wait480u
	ret

; ------------------------------------------------------------------------------

; Delay loop used by the delay macros
; including rcall, it wastes (arg0*3)+5 cycles
; arg0 > 0!
delay:
	dec arg0		; 1 cycle
	brne delay		; 2 cycles (1 if not true)
	ret			; 4 cycles

; ------------------------------------------------------------------------------

