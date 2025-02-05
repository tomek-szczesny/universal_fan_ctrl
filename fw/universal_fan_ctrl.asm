; Universal Fan Controller
; Attiny202 firmware
; by Tomek Szczęsny 2025
; Build with avra

.nolist
.include "tn202def.inc"
.list

.equ CONSTANT_VALUE = 128

; temperatures are stored as 16-bit signed integers
; representing temperature in units of (1/16) deg C

.def zero = r13				; Always zero
.def temph = r17			; Current temperature
.def templ = r16
.def tempmaxh = r19			; 100% PWM temperature
.def tempmaxl = r18
.def tempminh = r21			; 25% PWM temperature
.def tempminl = r20
.def tmph = r25				; Temporary values
.def tmpl = r24
.def tmp2h = r23			; Temporary values
.def tmp2l = r22

; ------------------------------------------------------------ 

.cseg
.org 000000				; Interrupt Vector
	rjmp Init			; Reset

.org INT_VECTORS_SIZE+1
Init:
	ldi tmpl, Low(RAMEND)		
	out CPU_SPL, tmpl		; Stack pointer init

	clr zero			; Populate "always zero" register

	ldi tmpl, CPU_CCP_IOREG_gc	; Unlocking Configuration Change Protection
	out CPU_CCP, tmpl
	ldi tmpl, 0b00010011		; Clock prescaler dividing by 10 -> 2MHz operation
	sts CLKCTRL_MCLKCTRLB, tmpl

; ------------------------------------------------------------ 

	; Sampling BOM settings set by resistor dividers

	ldi tmpl, 0x05			; Enable ADC, 10 bit
	sts ADC0_CTRLA, tmpl
	ldi tmpl, 0x02			; Accumulation of 4 results
	sts ADC0_CTRLB, tmpl
	ldi tmpl, 0b01010000		; Reduced sampling cap, Vref=Vdd, clk divided by 2 (=1MHz)
	sts ADC0_CTRLC, tmpl
	ldi tmpl, 0b01000000		; 32 clock cycles init delay
	sts ADC0_CTRLD, tmpl
	ldi tmpl, 31			; Sampling period of 32 clk cycles (maximum)
	sts ADC0_SAMPCTRL, tmpl
	ldi tmpl, 0x02			; Selects PA2 input (MT value)
	sts ADC0_MUXPOS, tmpl
	call ADCpoll			; Discard the first sample
	call ADCpoll			; Capture the value

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
	call ADCpoll			; Discard the first sample
	call ADCpoll			; Capture the value

	lds tmph, ADC0_RESH		; Load the ADC result, raw setting on low 2 bits
	inc tmph
	ldi tmpl, 80			; *16*5, shift and scale setting
	mul tmph, tmpl
	movw tempminl, tempmaxl		; Copy the max value and subtract TR
	sub tempminl, r0
	sbc tempminh, r1

	sts ADC0_CTRLA, zero		; Disable ADC

; ------------------------------------------------------------ 

	; Set up the counters
	; TCA will generate the PWM signal at WO1 pin, at 100Hz or so
	; TCB will generate 5Hz interrupts for temperature acquisition

	ldi tmpl, 0x07			; TCA enabled, divider by 8 (=250kHz) 
	sts TCA0_SINGLE_CTRLA, tmpl
	ldi tmpl, 0b00100011		; WO1 enabled, Single Slope PWM mode 
	sts TCA0_SINGLE_CTRLB, tmpl
	; TODO: Set this pin as output
	ldi tmpl, 0xC3			; Set the period to 100Hz (2499) 
	sts TCA0_SINGLE_TEMP, tmpl
	ldi tmpl, 0x09
	sts TCA0_SINGLE_PERH, tmpl
	ldi tmpl, 0xFF			; Set the initial PWM to max 
	sts TCA0_SINGLE_TEMP, tmpl
	sts TCA0_SINGLE_CMP1BUF, tmpl
	ldi tmpl, 0x04
	sts TCA0_SINGLE_CTRLFSET, tmpl


	; TCB setup
	; Source: CLK_TCA (250kHz)



	;ldi tmpl, (1 << DDB3)		; B3 jest wyjściem (pin od OC2)
	;out DDRB,tmpl

Oblivion:

	rjmp Oblivion

; ------------------------------------------------------------------------------

AVRTempSetup:				; Configuration of ADC for capturing AVR internal temperature
	ldi tmpl, 0x10			; Vref = 1.1V
	sts VREF_CTRLA, tmpl
	ldi tmpl, 0x01			; Enable ADC
	sts ADC0_CTRLA, tmpl
	ldi tmpl, 0x06			; Accumulation of 64 results
	sts ADC0_CTRLB, tmpl
	 ldi tmpl, 0b01000000		; Reduced sampling cap, internal Vref, clk divided by 2 (=1MHz)
	sts ADC0_CTRLC, tmpl
	ldi tmpl, 0b01000000		; 32 clock cycles init delay
	sts ADC0_CTRLD, tmpl
	ldi tmpl, 31			; Sampling period of 32 clk cycles (maximum)
	sts ADC0_SAMPCTRL, tmpl
	ldi tmpl, 0x1E			; Selects temperature sensor as the ADC input
	sts ADC0_MUXPOS, tmpl
	ret

; ------------------------------------------------------------------------------

AVRTemp:				; Capture temperature from the AVR internal sensor

	call ADCpoll			

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
	add tmpl, tmp2h
	adc tmph, zero
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


DSsanit:				; Sanitizing raw data from DS18B20 stored in tmp
	andi tmph, 0b10000111
	andi tmpl, 0b11111100		; For 10-bit readouts
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

