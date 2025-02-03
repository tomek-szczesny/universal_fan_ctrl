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

.def temph = r17			; Current temperature
.def templ = r16
.def tempmaxh = r19			; 100% PWM temperature
.def tempmaxl = r18
.def tempminh = r21			; 25% PWM temperature
.def tempminl = r20
.def tmph = r23				; Temporary values
.def tmpl = r22

.cseg
.org 000000				; Interrupt Vector
	rjmp Init			; Reset

.org INT_VECTORS_SIZE+1
Init:
	ldi tmpl, Low(RAMEND)		
	out CPU_SPL, tmpl		; Stack pointer init

	;ldi tmpl,0b11100011		; Internal 2.56V, Left Adjust, ADC3
	;out ADMUX,tmpl
	;ldi tmpl,0b11110000		; Enable, free running, prescaler 2
	;out ADCSRA,tmpl
	

	;ldi tmpl, (1 << DDB3)		; B3 jest wyjściem (pin od OC2)
	;out DDRB,tmpl

Oblivion:

	rjmp Oblivion

; ------------------------------------------------------------------------------

DSsanit:				; Sanitizing raw data from DS18B20 stored in tmp
	andi tmph, 0b10000111
	andi tmpl, 0b11111000		; For 9-bit readouts
	ret

; ------------------------------------------------------------------------------

Facc:					; Filtered accumulation of tmp in temp
					; Performs temp = (7/8)*temp + (1/8)*tmp
					; Destroys tmp data

	sub tmpl, templ			; tmp -= temp;
	sbc tmph, temph
	asr tmph			; tmp /= 8; (Preserving the sign)
	ror tmpl
	asr tmph
	ror tmpl
	asr tmph
	ror tmpl
	add templ, tmpl			; temp += tmp
	adc temph, tmph
	ret

; ------------------------------------------------------------------------------
