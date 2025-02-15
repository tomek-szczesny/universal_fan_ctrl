; Universal Fan Controller
; Attiny202 firmware
; by Tomek Szczęsny 2025
; Build with avra

; Fuse bits:
; - Set osc to 16MHz

.nolist
.include "tn202def.inc"
.list

.equ CONSTANT_VALUE = 128

; temperatures are stored as 16-bit signed integers
; representing temperature in units of (1/16) deg C

.equ owp = 7				; One-Wire pin number on port A

.def zero = r13				; Always zero
.def ow = r12				; Bit corresponding to 1-Wire pin
.def temph = r17			; Current temperature
.def templ = r16
.def tempmaxh = r19			; 100% PWM temperature
.def tempmaxl = r18
.def tempminh = r21			; 25% PWM temperature
.def tempminl = r20
.def slope = r26			; The slope constant for PWM calculation
.def tmph = r25				; Temporary values
.def tmpl = r24
.def tmp2h = r23			; Temporary values
.def tmp2l = r22

.macro wait12u
	push tmpl		; 1 cycle
	ldi tmpl, 1		; 1 cycle
	rcall delay		; 8 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait15u
	push tmpl		; 1 cycle
	ldi tmpl, 2		; 1 cycle
	rcall delay		; 11 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait45u
	push tmpl		; 1 cycle
	ldi tmpl, 12		; 1 cycle
	rcall delay		; 41 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait60u
	push tmpl		; 1 cycle
	ldi tmpl, 17		; 1 cycle
	rcall delay		; 56 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait67u
	push tmpl		; 1 cycle
	ldi tmpl, 19		; 1 cycle
	rcall delay		; 62 cycles in total
	pop tmpl		; 2 cycles
	nop			; 1 cycle
.endm
.macro wait120u
	push tmpl		; 1 cycle
	ldi tmpl, 37		; 1 cycle
	rcall delay		; 116 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait240u
	push tmpl		; 1 cycle
	ldi tmpl, 77		; 1 cycle
	rcall delay		; 236 cycles in total
	pop tmpl		; 2 cycles
.endm
.macro wait480u
	push tmpl		; 1 cycle
	ldi tmpl, 157		; 1 cycle
	rcall delay		; 476 cycles in total
	pop tmpl		; 2 cycles
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
	ldi tmpl, (1 << owp)		; Pin PA7 
	mov ow, tmpl
	;ldi tmpl, 0x08			; Enable PA7 pull-up when configured as input
	;sts PORTA_PIN1CTRL, tmpl	; May overload the 1W bus with the existing pull-up

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
	rcall ADCpoll			; Discard the first sample
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
	rcall ADCpoll			; Discard the first sample
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
	ldi tmpl, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi tmpl, 0xBE			; Send "Read Scratchpad"
	rcall OWsendbyte

	rcall OWreadbyte		; the first byte read is the lower half
	mov tmp2l, tmpl
	rcall OWreadbyte
	mov tmph, tmpl
	mov tmpl, tmp2l

	andi tmph, 0b10000111		; Sanitizing raw data from DS18B20 stored in tmp
	andi tmpl, 0b11111100		; For 10-bit readouts
	rcall Facc			; Accumulate the result into temp registers

	; Configure DS18
	rcall OWresetpulse
	brts Fallback			; If no response, fall back to AVR sensor

	ldi tmpl, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi tmpl, 0x4E			; Send "Write Scratchpad" (the third byte is config)	
	rcall OWsendbyte
	ldi tmpl, 0x00			; Send two dummy bytes	
	rcall OWsendbyte
	rcall OWsendbyte
	ldi tmpl, 0x3F			; Configuration byte 0x3F (10-bit result, conv. time 187.5ms)
	rcall OWsendbyte

	; Launch DS18 conversion
	rcall OWresetpulse
	brts Fallback			; If no response, fall back to AVR sensor
	
	ldi tmpl, 0xCC			; Send "Skip ROM" (we expect only one 1w device)	
	rcall OWsendbyte
	ldi tmpl, 0x44			; Send "Convert Temperature"
	rcall OWsendbyte

	; We assume the conversion should be complete at the next 5Hz cycle

	rcall PWMset			; Compute and update PWM setting
	reti

Fallback:				; Read AVR temperature sensor instead
	rcall AVRtemp			; Get the AVR temperature to tmp registers
	rcall Facc			; Accumulate the result into temp registers
	rcall PWMset			; Compute and update PWM setting
	reti

; ------------------------------------------------------------------------------

PWMset:					; Compute and update PWM setting
					; Destroys tmp
	; TCA period is 2499 ticks
	; Input value is within 0-319 range
	; let's set CMP = 579 + (6*IN)
	; This gives 23.16% minimum PWM

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
	; temp is at most 9 bits long
	; slope fits into 7 bits
	; The result is 16 bits long tops
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
	ret

; ------------------------------------------------------------------------------

AVRtemp:				; Capture temperature from the AVR internal sensor

	rcall ADCpoll			

	lds tmpl, ADC0_RESH		; Load ADC results, reversed reg order for a reason
	lds tmph, ADC0_RESL
	ldi tmp2h, 0x40			; Dividing by 64 with appropriate rounding
	add tmph, tmp2h			; Because 64x accumulation has been enabled
	adc tmpl, zero
	rol tmph			; Rotate both registers, 2 positions 
	rol tmpl
	rol tmph
	rol tmpl
	rol tmph
	andi tmph, 0x03

	; Temperature readout compensation, as per datasheet instructions
	; However it's not clear whether the expected input value is 8 or 10 bit
	; Assuming 10 bit for now

	lds tmp2l, SIGROW_TEMPSENSE1	; Read offset
	clr tmp2h			; expanding signed tmp2l to tmp2h:tmp2l
	sbrc tmp2l, 7
	ser tmp2h
	sub tmpl, tmp2l			; Applying offset
	sbc tmph, tmp2h

	adiw tmpl, 0x08			; Dividing by 16 with appropriate rounding
	;add tmpl, tmp2h
	;adc tmph, zero			; WTF is this?
	lsr tmph
	ror tmpl
	lsr tmph
	ror tmpl
	lsr tmph
	ror tmpl
	lsr tmph
	ror tmpl

	lds tmp2l, SIGROW_TEMPSENSE0	; Read slope
	mul tmp2l, tmph			; Multiply MS half of tmp
	push r0				; Stash the result (we assume r1 = 0)
	mul tmp2l, tmpl			; Multiplying the LS half
	movw tmpl, r0
	pop r0				; Restore the MS multiplication
	add temph, r0			; Add LS to the final result (assuming no overflow)

	; At this point, temph:templ contains a temperature in Kelvins. 
	; The maximum value is 2^12 K, so no overflow is expected
	; No negative values are expected either because physics.

	subi tmpl, 0b00010010		; Converting to deg C
	sbci tmph, 0b00010001

	ret

; ------------------------------------------------------------------------------

Facc:					; Filtered accumulation of tmp in temp
					; Performs temp = (3/4)*temp + (1/4)*tmp
					; Destroys tmp data

	sub tmpl, templ			; tmp -= temp;
	sbc tmph, temph

	adiw tmpl, 0x02			; Correct division rounding error
	asr tmph			; tmp /= 4; (Preserving the sign)
	ror tmpl
	asr tmph
	ror tmpl
	add templ, tmpl			; temp += tmp
	adc temph, tmph
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

OWsendbyte:				; Sends tmpl byte
	push tmph
	ldi tmph, 8
	owz
	owl
	owsbloop:
	owe
	sbrc tmpl, 0			; Zero is the 60+us pull
	owz				; Skip shortening the pull if zero
	wait60u
	owz
	lsr tmpl			; Shift data right
	dec tmph			
	brne owsbloop			; Loop it
	pop tmph
	ret

; ------------------------------------------------------------------------------

OWreadbyte:				; Reads a byte to tmpl
	push tmph
	ldi tmph, 8
	owz
	owl
	owrbloop:
	owe				; Pull low for 2us (>1us)
	lsl tmpl			; shift register 
	owz
	wait12u
	owr
	bld tmpl, 0			; Store received bit in tmpl
	wait60u
	dec tmph			
	brne owrbloop			; Loop it
	pop tmph
	ret

; ------------------------------------------------------------------------------

OWresetpulse:				; Sends a reset pulse
	owl				; returns "1" in T register if no response
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
; including rcall, it wastes (tmpl*3)+5 cycles
; tmpl > 0!
delay:
	dec tmpl		; 1 cycle
	brne delay		; 2 cycles (1 if not true)
	ret			; 4 cycles

; ------------------------------------------------------------------------------

