;Versuch den 2.4 Ghz Empfänger zu steuern
;Es müssen Bind-Daten gelesen und gesendet werden
;Es müssen Kanaldaten gelesen und in Kanalimpulse umgewandelt werden
;Da der 12F675 PIC nicht genügend Pins für Servoausgänge hat, wäre er nicht für einen größeren Empfänger zu verwenden.
;Aber die prinzipiellen Funktionen könnten damit entwickelt werden.
;Wobei aber die Frage ist, ob es sich dann lohnt oder ob nicht gleich mit einem entsprechenden Chip
;angefangen werden sollte.
;es ist ein 10 MHz Quarz vorzusehen

;Level change IR und Timer0 IR werden enabled
;Das Startbit löst einen LevelChange IR aus
;In der Ir Service Routine muß erst einmal housekeeping gemacht werden
;dasdauert 
;dann wird der Pegel eingelesen
;Dann wird der timer0 mit ca 12 usec neu gestartet
;der timer soll so lange laufen, daß er später kommt als eine eventuelle Flanke des Eingangssignals
;die interrupt flags werden gelöscht.
;Der Rest der Verarbeitung muß dann erledigt werden
;und dannwieder das housekeeping rückwärts
;und das alles in max 23 usec
;entweder der Timer0 timed aus oder es tritt eine neue Flanke (level change) auf und führt zum Interrupt.

;Mit Timer0 kann man die Zeit für die einzelnen Bits messen
;
;**********************************************************************
;                                                                     *
;    Filename:	    xxx.asm                                           *
;    Date:                                                            *
;    File Level:                                                      *
;                                                                     *
;    Author:                                                          *
;    Company:                                                         *
;                                                                     * 
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files required:                                                  *
;                    12F675.lkr                                       *
;                                                                     *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Notes:                                                           *
;    Pin1:       Vdd        + 5Volt                                   *
;    Channel-Output GPIO 0  Pin 7                                     *
;    Channel-Output GPIO 1  Pin 6                                     *
;    Signal-In/Out  GPIO 2  Pin 5 Dataline                            *
;    Signal-Input:  GPIO 3  Pin 4 Bind Pin                            *
;    Input:         GPIO 4  Pin 3 Oscillator Quarz                    *
;    Input:         GPIO 5  Pin 2 Oscillator Quarz                    *
;    Pin8:       Vss        Minus                                     *
;                                                                     *
;																	  *
;                                                                     *     
;                                                                     *     
;   _MCLRE_OFF muß gesetzt sein                                       *     
;   _BODEN_ON  weil der IC an der Spannung des Empfängers hängt       *
;**********************************************************************

	list      p=12f675		; list directive to define processor
	#include <p12f675.inc>	; processor specific variable definitions

	errorlevel  -302		; suppress message 302 from list file


;Quarz Oszillator mit mindestens 10 MHz (Höchstfrequenz bei 3.3 Volt Spannung) verwendet werden.
	__CONFIG   _CP_OFF & _CPD_OFF & _BODEN_ON & _MCLRE_OFF & _WDT_OFF & _PWRTE_ON & _HS_OSC  


;***** VARIABLE DEFINITIONS **********
#define		Positive			0			;Positive =1 ->  ----|_|------|_|-------|_|------------------------------|_|----

											;Posirive =0 ->  ____|-|______|-|_______|-|______________________________|-|____

#define		PPM_Fail_Safe		1			;PPM_Fail_Safe = 0  --> With signal loss, PPM signal is switched off
											;PPM_Fail_Safe = 1  --> With signal loss, PPM signal is switched to Failsafe setting									

#define		Max_Signal_Lost		.3			;number of contigous Signal_Lost conditions
											;before activating Fail_Safe position
										
										
;**************************************************************************************************************************			

#define		Prog_Level		"21PPM"	;Die Programmversion kenntlich machen
#define		Sample_Time		.176 		;Dieser Wert ist korrekt !!! Read (Bind)-Data check .178
#define 	Full_Bit_Time	.185		;Dieser Wert funktioniert!!!! Send Bind-Data  check .182
#define		Number_of_Channels	.8		;Number of servo channels to be supported (1 - 8)
#define 	Servo_Lines		GPIO		;Adress of GPIO for PIC12f675


;**************************************************************************************************************************


#define 	InputLevel	My_Status,0
#define		BitFound	My_Status,1
#define		Send_Bind	My_Status,2
#define		Send		My_Status,3
#define		StartBit	My_Status,4
#define		StopBit		My_Status,5
#define		With_Startbit	My_Status,6	
#define		Checksum_Ok	My_Status,7
;-------------------------------------------------------
#define 	Signal_Lost		Fail_Safe,0		
#define 	FS_Done			Fail_Safe,1
#define		Restored		Fail_Safe,2

;**************************************************************************************************************************						
#define		Channel3	    GPIO,0   		;Channel 3
#define		PPM_Out		Servo_Lines,1			;Ausgang für Kanal1
#define		DataLine		GPIO,2			;Auf diesen Eingang die Dataline des Receivers legen
#define 	BindLine		GPIO,3			;Auf diesen Pin den Bind-Plug stecken
;#define		LED				GPIO,0			;Anzeige LED "Bind complete" / "Online" / Debug

;---------------------------------------------------------------------------

; example of using Shared Uninitialized Data Section
INT_VAR		UDATA_SHR	0x20   
w_temp		RES     1		;0x20  variable used for context saving 
status_temp	RES     1		;0x21  variable used for context saving
My_Status	RES		1		;0x22
Bit_Count	RES		1		;0x23
Byte_Count	RES		1		;0x24
ShiftData	RES		1		;0x25
From_Adrs	RES		1		;0x26
To_Adrs		RES		1		;0x27
Inner		RES		1		;0x28
IInner		RES		1		;0x29
Outer		RES		1		;0x2a
Cksum_High	RES		1		;0x2b
Temp		RES		1		;0x2c
Byte1		RES		1		;0x2d
Byte2		RES		1		;0x2e
Byte3		RES		1		;0x2f
Byte4		RES		1		;0x30
Byte5		RES		1		;0x31
Byte6		RES		1		;0x32
Byte7		RES		1		;0x33
Byte8		RES		1		;0x34
Byte9		RES		1		;0x35
Byte10		RES		1		;0x36
Byte11		RES		1		;0x37
Byte12		RES		1		;0x38
Byte13		RES		1		;0x39
Byte14		RES		1		;0x3a
Byte15		RES		1		;0x3b
Byte16		RES		1		;0x3c
Byte17		RES		1		;0x3d
Byte18		RES		1		;0x3e
Copy_Byte1	RES		1		;0x3f
Copy_Byte2	RES		1		;0x40
Copy_Byte3	RES		1		;0x41
Copy_Byte4 	RES		1		;0x42
Copy_Byte5	RES		1		;0x43
Copy_Byte6	RES		1		;0x44
Copy_Byte7	RES		1		;0x45
Copy_Byte8	RES		1		;0x46
Copy_Byte9	RES		1		;0x47
Copy_Byte10	RES		1		;0x48
Copy_Byte11	RES		1		;0x49
Copy_Byte12	RES		1		;0x4a
Copy_Byte13	RES		1		;0x4b
Copy_Byte14	RES		1		;0x4c
Copy_Byte15	RES		1		;0x4d
Copy_Byte16	RES		1		;0x4e
My_Temp		RES		1
Selected_Channel	RES	1
Fail_Safe	RES		1		;0x51
SL_Counter	RES		1
CP_Low		RES		1		
CP_High		RES		1

;**********************************************************************
RESET_VECTOR	CODE	0x000	; processor reset vector
		goto    main			; go to beginning of program

;========================================================================
;************************************************************************
INT_VECTOR	CODE	0x004		; interrupt vector location
		movwf	w_temp			;copy W to temp-register
		swapf	STATUS,W		;swap status into W   Bank 0,1			
		bcf		STATUS,RP0		;change to Bank 0
		movwf	status_temp		; save STATUS to bank 0 register		

		;bsf		LED		;!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!mein Synch Impuls fürs Scope
		nop ;instead if LED
        nop						;don't change timing
		
		btfsc	Send_Bind
		goto	Send_Bit		;have to send binding information
		
		
;---------- Read Binding or channel Information ----------------------------
Read_Bit
	;bits are put into Shiftdata at bitposition 7 and shifted right with every sample. So first bit will become low order bit
	;Startbit will be shifted out of byte and stop bit (at bitcount 1) will skip shifting 
	;BitFound signals the waiting outside routine, that we had a sampling time.
	
		bsf		BitFound		;We have a bit weil wir einen Interrupt hatten. Entweder ist der Timer ausgetimed oder 
								;der Eingangspegel hat sich geändert.
	;Das Stopbit ist bei Bit_Count=1.Es wird nicht in ShiftData geladen
	;test if this is a stop bit
		movlw	1
		subwf	Bit_Count,W		;Ergebnis in W
		btfsc	STATUS,Z		;Skip if not Zero; this is a Databit
		goto	Stop_Bit		;Bit_Count=1, we have the Stopbit. Don't sample it into ShiftData
		
		rrf		ShiftData,1		;rotate right, schafft Platz für ein neues bit. Result nach ShiftData		

		;re-start T0 for the next sampling time. don't activate IR
		movlw	Sample_Time			;Timer läuft hier bereits los, IR WIRD ABER ERST SPÄTER enabled
		movwf	TMR0				;Bank0		
		
		;Datenbit schon mal setzen
		bsf		ShiftData,7		;set bit 7 to high
		;den Pegel des Eingangs-Signals testen		
		btfss	DataLine	 	;Pegel überprüfen			
		;Das Bit wieder löschen, wenn der Pegel Low war
		bcf		ShiftData,7		;no, set Bit 7 low	
		
		movlw	0xA8			;prepare for Timer and Levelchange IR !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
;		movlw	0x88			;nur Levelchange Interrupt!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		
		goto	HouseKeeping_Exit
		
Stop_Bit
	;when we have read all bits, disable all IR and stop receiving
		movlw	0				;Disable Interrupts
		goto	HouseKeeping_Exit		

;------------Receiver mode: Send Binding Information--------------------------------------
Send_Bit
		btfsc	StartBit		;must we send the start bit?
		goto 	Switch_OFF		;yes, jump to Switch_OFF
		
Not_StartBit		
	;when we send binding information we send 15 bits. The startbit, 8 databits and several stopbits
	;the W register contains the byte to be sent. Before shifting the W-register we set the carry bit on.
	;We shift the bits right -> through carry every sample time pushing the lowest bit into the carry position
	;and the old carry (a 1 bit) as bit 7. By this, we fill up the byte with 1's that we use afterwards as stop bits
	;After shifting, we test the carry bit to set dataline high or low.
		
		bsf		STATUS,C		;fills up the Byte with 1's from top to bottom and produces the stop bit
		;jetzt ist das carry bit gesetzt und mit dem rrf wird es als high order bit reingeschoben
		rrf		INDF,F			;Das nächste Bit ins Carry shiften		
		;jetzt wurde Bit0 ins carry geschoben. Das wird jetzt überprüft
		btfsc	STATUS,C		;Ist das Carry gesetzt?
		goto	Switch_ON		;Ist gesetzt, deshalb nach Switch_ON
Switch_OFF		
		bcf		DataLine		;Ist nicht gesetzt, deshalb OFF. Ausgang Low
		bcf		StartBit		;lösche Startbit Indikation
		goto	Cont
Switch_ON		
		bsf		DataLine		;Ausgang High
Cont				
		movlw	Full_Bit_Time 	
		movwf	TMR0				;Bank0		
		bcf		Send				;reset Indicator for outside routine
		movlw	0xA0	;GIE + T0IE			;Beim Senden nur Timer IR
;-------------------------------------------------------------------------------------
		

HouseKeeping_Exit
		;Wir setzen das Interrupt Control Register komplett neu auf
		movwf	INTCON			;	Bank 0,1

;SELTSAM !!!!!! wenn ich nicht in der Interruptroutine auf das GPIO Register zugreife,z.B. mit bsf LED oder ähnlich,
;dann läuft der Timer für den zweiten Kanal über die gesamte Zeit beider Register. Es ist also so, als ob man den Timer1 mit einem
;Wert von 0 starten würde. Ich habe keine Ahnung was das soll. Solange in dieser Routine ein bsf LED (oder channel1) und ein 
;entsprechendes bcf LED zur Erzeugung eines Sync-Pulses fürs Scope war, funktioniert es
;Deshalb muß dieser "sinnnlose" Befehl hier drinnen sein.!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

;This is a miracle. Without one of these two instructions, the Timer1 for the channel pulses doesn't work correctly
		movfw	Servo_Lines		;Bank0
		;bcf		LED		;!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!mein Synch Impuls fürs Scope		
		nop ;instead of LED

		swapf   status_temp,W	; retrieve copy of STATUS register
		movwf	STATUS			; restore pre-isr STATUS register contents Bank 0,1
		swapf   w_temp,F
		swapf   w_temp,W		; restore pre-isr W register contents
		retfie					; return from interrupt
;*******************************************************************************
;********************* 19 Befehle lang **********************************************************
;******************************************************************************

;						Ende der Interrupt Routine
;*******************************************************************************
;========================================================================================
;*******************************************************************************

; these first 4 instructions are not required if the internal oscillator is not used
;but they preserve the OscCal value
main
		call    0x3FF			; retrieve factory calibration value
		bsf     STATUS,RP0		; set file register bank to 1    
		bcf	STATUS,IRP
		bcf	STATUS,RP1
		movwf   OSCCAL			; update register with factory cal value   Bank 1
		
		
;=====================Initialisierung===========================================
; remaining code goes here

init
		clrf	PIE1			;Bank1
		;Ein- und Ausgänge zuordnen
		clrf	ANSEL			;alle IO/O Ports sind digital							Bank 1
		
		clrf	TRISIO			;alles Output mit Ausnahme von GP3					  Bank 1
		
			
		movlw 	0x08				
		movwf	OPTION_REG		;Kein Prescaler für Timer0, internal Clock, GPIO pullups enabled			Bank 1
	
		
		bcf		STATUS,RP0		;select bank 0	
				
		movlw	0x04
		movwf	Servo_Lines			;Dataline high, that the receiver doesn't switch to bind mode by itself. All outputs low. Bank0
										
		movlw	07				;		
		movwf	CMCON			;switch off comparator  					Bank 0		
		
		movlw	0x20	
		movwf 	T1CON		;enable Timer1 prescaler 4 : 1; Timer off		Bank 0
	
;test, if the bind plug is plugged
		btfss	BindLine		;is high for normal op, low if bind plug plugged  
		goto	Request_Bind		;is plugged, so goto Bind Mode		
		
		;activate fail safe settings
		call	Fail_Safe_Lesen		;read fail safe data and copy into Copy_Byte1 - Copy_Byte16	
		
		
;-----------------		
		movlw	Max_Signal_Lost
		movwf	SL_Counter
		
		clrf	My_Temp



;========================================================================
;========================================================================		
;-------------------------------------------------------------------------------------------
;					Normal receive operation
;-------------------------------------------------------------------------------------------		
;normal receiver operation (bind plug not plugged) first has to send binding data, that is in the EEPROM
;Timing is done by Timer0 overflow IR.
;Timer0 is reloaded every bittime and restartet
;the receiver then must switch to receive mode and receive 16bit channel data
Normal_Op	
		call 	Bind_Lesen			;read the Binding Bytes from EEprom and put to Byte1 - Byte9   !ok geht!
		;wait 400 msec for the receiver to get powered on
		call	Wait200m	
		call	Wait200m	
		call	Setup_For_Send_BindInfo	;Timer0 free running with 24.4 usec(?) and data output via IR Handler !ok works!	
		bsf		Send_Bind				;Send Bind Information to receiver
		call	Send_Bind_Info		;wait and send binding information									! ok works !	
		bcf		Send_Bind

Cont_Receive	
		call	Setup_Registers_for_Receive		;setup registers and Timer0	
		call	Receive_Channel_Data		
		call	Output_Channel_Data			;Servo Kanal Impulse
						
		goto	Cont_Receive
		
;===============================================================
;          Bind Receiver with TX
;===============================================================			
;set the receiver into binding mode and try to receive a binding information
;save that information to EEprom for use with normal receive
Request_Bind
		bcf		DataLine		;make dataline low to set receiver into bind mode
;wait 50-250 msec with Output GPIO2 low and then make GPIO2 high and an Input 
		call	Wait200m
		bsf		DataLine		;make it high, to terminate the "set to bindmode" 
;--------------------------------------------------------
		bcf		Send_Bind
		call	Setup_Registers_for_Receive		;setup of registers 
		call	Wait200m			;this delay is very important as obviously there is anyhow an edge that would trigger receive
		call	Wait200m
		call 	Receive_Bind_Info
		call	Schreiben			;Write to EEProm
		;bsf		LED					;switch on "Bind complete"	LED								Bank 0
        nop ;instead of LED						
Term	
		nop							;Endless loop
		goto	Term		

;========================================================================
;========================================================================
;-----------------------------------------------------------------------
Wait500u
		clrf	Inner
I_Loop500
		nop
		nop
		nop					;385u
		nop					;450u
		nop					;510u
		decfsz	Inner,F	
		goto	I_Loop500
		return

;-----------------------------------------------------------------------		

Wait200m		
		movlw	.200	;setup for 200ms delay  
		movwf	Outer
O_Loop		
		movlw	.180
		movwf	Inner
I_Loop	
		movlw	.20		;.6
		movwf	IInner
II_Loop
		decfsz	IInner,F
		goto	II_Loop
		decfsz	Inner,F
		goto	I_Loop
		decfsz	Outer,F
		goto	O_Loop
		return		
;======================================================================			
		
Setup_For_Send_BindInfo

;don't allow Interrupts for Timer0 at this time
		clrf	PIR1			;clear peripheral InterruptFlags Bank 0 ; nur sicherheitshalber
		clrf	INTCON			;								Bank 0,1
	
		bsf		STATUS,RP0		;select bank 1									
		bcf		TRISIO,2		;make GP2 an output								Bank 1	
		bsf		WPU,2			;activate weak pullup							Bank 1		
		bcf		STATUS,RP0		;select bank 0	
		
;Timer0 aufsetzen
;beim ersten Aufsetzen des Timers ist es Wurst, wie lange er läuft, wenn nur das Programm bis dahin abgearbeitet ist.
;Denn erst nach dem Interrupt wird das erste (Stopbit) auf die Leitung gestellt und da dann immer derselbe Programmteil läuft,
;müßte das Timing konstant bleiben
		movlw	Sample_Time		;setup Timer; runs 24.4 us (?) till interrupt
		movwf	TMR0			;bank 0	
		movlw	0xA0			;enable GIE + T0IE
		movwf	INTCON			;Bank 0,1
		return

;======================================================================================================		
Setup_Registers_for_Receive		

;don't allow Interrupts for Timer0 at this time
		clrf	PIR1			;clear peripheral InterruptFlags Bank 0 ; nur sicherheitshalber
		
		bsf		STATUS,RP0		;select bank 1									
		bsf		TRISIO,2		;make GP2 an input								Bank 1				
		bsf		IOC,IOC2		;enable GPIO2 for Interrupt on Change			Bank 1		
		bcf		STATUS,RP0		;select bank 0		

		return

;======================================================================================================		
;-------Read 10 (9) x 8Bit Binding Bytes--------------------------------------------------------------------
Receive_Bind_Info

		call	Wait200m			;allow Receiver to power on

;we receive one byte of FF that does belong to nothing, so put it into Temp and the next byte addressed is Byte1				
		movlw	Temp			;Adresse für scrap byte before Byte1
		movwf	FSR				;									Bank 0,1
;caused by the byte above, we have to set the bytecount one higher		
		movlw	.11				
		movwf	Byte_Count
		
Cont_Bind_Info
		;clear possible IR flags and enable GIE and GPIE 
		;so it will wait for or continue with the next level change
		clrf	INTCON
		movlw	0x88			;allow level change interrupt only at this time
		movwf	INTCON			;Bank 0,1
		movlw	.10				;setup Bitcount. 9 passes, because the first pass is for the start bit
		movwf	Bit_Count

;---------------------------------		
;count the bits for one byte
Wait_For_Event1
		btfss	BitFound		;wait until the first level change IR or a timer0 Overrun IR occurres
		goto	Wait_For_Event1
		bcf		BitFound		;clear the found bit
		decfsz	Bit_Count,F		;count down, how many bits we have already
		goto	Wait_For_Event1			;not yet enough
;---------------------------------		
;now we have read in a full byte of 8 data and one stop bit

;clear all IF and disable IR
		clrf	INTCON			;Bank 0,1
		;store the received byte
		movf	ShiftData,W		;ins W-Reg einlesen
		movwf	INDF			;nach 28 ff speichern					Bank 0,1
		incf	FSR,F			;										Bank 0,1
		;The delay between the bytes is 610 usec

		decfsz	Byte_Count,F		;all Bytes received?
		goto	Cont_Bind_Info	;no 
;alle 10 (9) Bytes have been read and are saved to Byte1 - Byte10	
		
		;all Interrupts disabled
		clrf	INTCON			;Bank 0,1
			
		bsf		STATUS,RP0		;select bank 1		
		movlw 	0x08				
		movwf	OPTION_REG		;Kein Prescaler für Timer0, internal Clock, GPIO pullups enabled			Bank 1		
		bcf		STATUS,RP0		;select bank 1	
				
		return		

;-----------------------------------------------------------------------------		
;==============================================================================
;store 10 (9) byte bind Daten to  EEProm 
Schreiben
		movlw	.10					;setup Bytecount
		movwf	Byte_Count			;nach Byte_Count speichern
		bcf		INTCON,7			;Interrupts ausschalten GIE				Bank 0,1 
		
		movlw	Byte1				;Data-adress for Byte1, where Data come from
		movwf	FSR					;									Bank 0,1
		movlw	0x30					;
		movwf	To_Adrs				;Adresse of EEProm, to where data is going		

Again		
		call	EEProm_Write
		incf	FSR,F				;									Bank 0,1
		incf	To_Adrs,F
		decfsz	Byte_Count,F		;all Bytes written?
		goto	Again				;No, next Byte
		return
				
;======================================================================


Send_Bind_Info		;send binding information 9 x 8bit bytes
;at least 9 Byte have to be sent, 10 Bytes don't hurt
		bsf		Send_Bind				;Send Bind Information to receiver
		;copy first byte into Shift_Data
		bsf		Send			;set transmit mode for the interrupt routine
		bsf		StartBit		;to send the initial startbit
		movlw	.10
		movwf	Byte_Count
		movlw	Byte1
		movwf	FSR					;gets Adress of Byte1 			Bank 0,1

Next_Byte		
	;when we send binding information we send 15 15 bits. 1 startbit, 8 databits, 1 stopbit and 5 additional stopbits
	;the W register contains the byte to be sent.
	;Inthe interrupt routine, before shifting the W-register we set the carry bit on.
	;We shift the bits right -> through carry every sample time pushing the lowest bit into the carry position
	;and the old carry (a 1 bit) as bit 7. By this, we fill up the byte with 1's that we use afterwards as stop bits
	;(stop bits are 1's) The carry bit then is set onto the dataline

		movlw	.15					;Bitcount mit Start und mehreren Stop bits
		movwf	Bit_Count
		movf	INDF,W				;Daten von Byte1 in W						Bank 0,1
		
;------------------------------------
;Send will be switched off, when the Interrupt routine has put a bit onto the line
Wait_Send							;Wait for Send to be switched off from IR Routine
		btfsc	Send
		goto	Wait_Send
;------------------------------------

		bsf		Send				;swith it on for the next bit to be sent
		decfsz	Bit_Count,F			;all bits done?
		goto	Wait_Send					;No, do next bit
		
		incf	FSR,F				;										Bank 0,1
		bsf		StartBit
		decfsz	Byte_Count,F			;all bytes done?
		
		goto	Next_Byte			;no, do next byte
		bcf		Send_Bind		
		return
		
;============================================================================
;-------------------------------------------------------------------------		

Receive_Channel_Data		;receive 9 x 16bit bytes  1S, 16D, 1S
		;clear possible IR Flags
		movlw	0x88			;don't allow timer0 imterrupts at this time
		movwf	INTCON				;Bank 0,1
		
		
		movlw	Byte1			;Adress of Byte1
		movwf	FSR				;									Bank 0,1
		movlw	.18				;fill up 18 Bytes
		movwf	Byte_Count

Cont_Channel_Data
		movlw	.18				;setup Bitcount 1 Startbit, 16 Databits, 1 Stopbit
		movwf	Bit_Count

;setup Timer1 for signal loss checking for 25 msec timeout
;when T1 times out, we did not receive channel data in time. 
;Leave receive and gate out timing pulses according to last stored channeldata or use fail_safe positions.
;a timer value of 9E58 will give 25 msec runtime till overflow
		movlw	0x9E
		movwf	TMR1H			;										Bank0
		movlw	0x58			
		movwf	TMR1L			;										Bank0
		clrf	PIR1										;Bank 0
		movlw	0x21
		movwf 	T1CON		;switch Timer1 on with prescaler 4 : 1		;Bank 0
		bsf		Signal_Lost
		
;---------------------------------		
;count the bits for one word
Wait_For_Event2
						;insert remaining stuff to be done like signal loss checking, failsafe and others
		;Check_for Signal_Loss						
		btfsc	PIR1,0											;Bank 0
		goto	Signal_Loss		;exit loop waiting for data

		btfss	BitFound		;wait until the first level change IR or a timer0 Overrun IR occurres
		goto	Wait_For_Event2
;---------------------
;when the bitcounter has been decremented from 18 to 10 we have received the first complete byte into shiftdata
		movlw	.10
		subwf	Bit_Count,W		;test bitcount = 10
		btfsc	STATUS,Z
		call	Save_Byte		;bitcount is 10, we have read the first byte
		
		bcf		BitFound		;das found bit löschen	
;when the bitcounter goes to 0, the second databyte is available in shiftdata
		decfsz	Bit_Count,F		;do we have one full word (1+16+1 Bit)?
		goto	Wait_For_Event2		;not yet
;--------------------		
		call	Save_Byte
		;after every second byte (one full word) we must take a short break
		call	Wait_Between
				
		movf	Byte_Count,F	;test bytecount for zero
		btfss	STATUS,Z		;Is Byte_Count=0 ?
		goto	Cont_Channel_Data	;no, go on read next word
;---------------------------------		
		clrf	INTCON			;clear interrupts									Bank 0,1		
		clrf	T1CON			;Stop T1											;Bank 0
		clrf	PIR1
		bcf		Signal_Lost		;means Signal ok
		bcf		Restored		;in case of a new signal loss, we will have to restore failsafe data again
			
		btfss	BindLine		;high= no plug jumpered, don't save channeldata as fail safe
		call	Copy_CH2_EEProm	;save actual channel data as default settings
		
		return
;----------------------
Signal_Loss
		;Timer1 overflow interrupt occurred
		bsf		Signal_Lost		;this terminates the receive loop
		clrf	T1CON			;switch off timer1									;Bank 0
		bcf		PIR1,0			;reset Timer interrupt flag							;Bank 0
		return			
		
;==========================================================================
Save_Byte	
;we have a byte, so let's save it		
		movf	ShiftData,W		;read to w-reg
		movwf	INDF			;store to 28 ff 							Bank 0,1
		incf	FSR,F			;											Bank 0,1
		decf	Byte_Count,F
		return		
;=============================================================================
Wait_Between
		movlw	0x88			;GIE + GPIE
		movwf	INTCON			;							Bank 0,1
		return
	
			
;===========================================================================================-		
		
Output_Channel_Data			;create Channel Pulse for Servo	
;check, if we have to handle fail safe
;proove checksum
;copy channel data to the save area
;setup timer1
;switch on the correct output port
;wait for timer overrun
;do the next channel

		clrf	INTCON			;Interrupts komplett löschen			;Bank 0,1

;used for debugging
;copy channel data to EEProm, where they can be read out on the programmer		
;		decf	My_Temp,F
;		btfsc	STATUS,Z
;		goto	Copy_CH2_EEProm	

		btfss	Signal_Lost			;skip if signal lost
		goto	Ck_Sum				;signal ok
;with signal lost we at first use the last valid data as channel data
;if we have multiple contigous signal losses, we switch to fail safe data, that is we copy fail
;safe data from EEPROM to channel data working registers Copy_Byte 1 - 16

;check if signal lost count is already 0
		movf	SL_Counter,F		;set condition code
		btfss	STATUS,Z		;check Zero status. Skip decrement, if already 0
								;fail save data have already been copied 
		goto	Not_Zero	
		
;signal lost several times, use fail_safe data
;Check for the type of Fail-Safe action regarding the PPM stream
			
	if	PPM_Fail_Safe		;PPM_Fail_Safe=1 so continue with the normal code
	else
		return						;PPM_Fail_Safe=0 exit the routine and do not create a PPM stream
	endif	
									
		goto	Use_As_Is
																
Not_Zero								
;signal lost, check if we already have to use fail safe data
		decfsz	SL_Counter,F
		goto	Use_As_Is

;----------------------------		
;signal lost several times, use fail_safe data
;for one continuous signal lost condition, copy data only once	
;did we already restore fail_safe data?
		btfsc	Restored				;we not yet have copied the fail safe data	
		goto	Use_As_Is
		call	Fail_Safe_Lesen		;read fail safe data and copy into Copy_Byte1 - Copy_Byte16	
		bsf		Restored
		goto	Use_As_Is
;-----------------------------		
Ck_Sum		
		call	CheckSum
		btfsc	Checksum_Ok			;if checksum is invalid, we skip copying of the channel data and use old data
		call	Copy_Ch_Data		;Data is correct, so use it
		;Data are now available in Cpy_Byte1  -  Cpy_Byte16
		
;with maximum length of 6 channels and channel 7 und 8 at neutral, there will be about 1 msec of time left, before the next 
;datapacket arrives.		

;the 16 bit channel data of one channel represents the time of the channel pulse in usec.
;as the PIC runs with 16 Mhz crystal, that means 4 Mhz instructions. Timer1 running with a prescaler of 4 will step one step
;every 1 usec 
;The timer is an imcrementing counter. If we want it to run 1000 steps (=1msec) we must set it up to 65536-1000=64536
;That's the reason for subtracting timer1 low and high from 0. When we subtract the low part, we get a borrow (Carry) and that
;means, that we have to subtract that carry from the high part.
Use_As_Is
	;setup number of channels		
		movlw	Number_of_Channels
		movwf	Byte_Count			;Number of channels to support (max 8)
		
	;load FSR with address of first channel low byte
		movlw	Copy_Byte1			;low byte channel1
		movwf	FSR
;----------------------------------		
Next_Channel
;+++++++++++++++++++++++++++++++++++++++++++ 
;âûâîäèì PWM êàíàëà ãàçà íà âûâîä Channel1
;+++++++++++++++++++++++++++++++++++++++++++ 
        MOVF      Byte_Count,W   ; êîïèðîâàòü èç Byte_Count â W
        BCF       STATUS,Z ; îïóñòèì ôëàã Z â íîëü
        XORLW     .6     ; ïðîâîäèì ñðàâíåíèå ñ ÷èñëîì 6 (8 ýòî êàíàë 1, 7 - êàíàë 2 è ò.ï.)
        BTFSC     STATUS,Z ; äåëàåì áèò-ïðîâåðêó Z-ôëàãà
; åñëè Z=1, òî âûïîëíÿåòñÿ ñëåäóþùàÿ èíñòðóêöèÿ, èíà÷å – ïðîïóñêàåòñÿ
        goto AreEqual        
		goto not3chan
AreEqual
        bsf Channel3  ;ïîäíèìàåì âûâîä Channel3 ââåðõ 
not3chan  ; åñëè íå êàíàë ãàçà
;+++++++++++++++++++++++++++++++++++++++++++ 

		call	Timer1_Sync				;channel sync pulse creates 300 usec negative pulse  ---|___|-----
		call	Timer1_Channel_Pulse	;calculates and sets the timer1 start value
		decfsz	Byte_Count,F		;skip if all channels done?
		goto	Next_Channel
;-------------------------------
		call	Timer1_Sync			;terminates the last channel pulse
		if Positive
			bsf		PPM_Out			;make output pin high          ____|--------------------------		
		else
			bcf		PPM_Out			;make output pin low           ----|___________________________
		endif
	;all channels done
		bcf		Signal_Lost		;this terminates the receive loop
		bsf		DataLine
		return

;==========================================================
Timer1_Sync
		;switche output low and return after 290 usec. It takes about 10 cycles to start the channel pulse. 
		;This time adds to the sync pulse
		;to create a timer with 290 usec, we have to subtract 290 from 0000 -> = FEDE because counter is incrementing to 0000
		movlw	0xDE
		movwf	TMR1L
		movlw	0xFE
		movwf	TMR1H

		movlw	0x21
		movwf 	T1CON			;start Timer1 with prescaler 4 : 1			;Bank 0
		
		if Positive
			bcf		PPM_Out					;make output low		
		else
			bsf		PPM_Out
		endif
		
		;we have 300 usec time, time enough to calculate the timing for the channel pulse
		call	Prepare_Channel_Time		
;--------		
Wait_Ch_L
		btfss	PIR1,0		;wait until t1 has timed out				;Bank 0
		goto	Wait_Ch_L
;--------
		clrf	T1CON											;Bank 0
		bcf		PIR1,0		;reset IR Flag						;Bank 0	
		return

			
;===========================================================

Prepare_Channel_Time
		clrf	Temp
		movfw	INDF				;load low byte of a channel
		subwf	Temp,W				;subtract from 0 (Temp)
		movwf	CP_Low				;set timer low byte					;Bank 0
		
		incf	FSR,F				;step to next byte adress
		movfw	INDF				;load high byte of a channel
		incf	FSR,F				;step to next byte adress
		subwf	Temp,W				;subtract from 0
		movwf	CP_High				;set timer high byte				;Bank 0
		
		;we must decrement timer1H for the Carry, when timer1L is not zero
		movf	CP_Low,F			;Check Timer1Lo for zero status
		btfss	STATUS,Z			;Skip if Zero, must not decrement Timer1Hi		
		decf	CP_High,F			;decr timer high, that is for the carry of the low byte		;Bank 0

		;now we have the timer setup for the full channel timing
		;as we have splitted off the sync pulse we must adjust the channel pulse duration
		;as the timer is incrementing up to 0000 time is shortened by increasing the starting value
		;this means, add the sync pulse timing to the timer value 
		;the sync pulse is 300 usec so we have to add 300 = 0x0118 to the timer to shorten its running time.

		movlw	0x18				;add low order byte of 0x0118
		addwf	CP_Low,F				
		btfsc	STATUS,C			;Skip if no Carry
		incf	CP_High,F			;Had a Carry, so add it
		incf	CP_High,F			;add 0x01 as the high order byte of 0x0118
		;CP_high and CP_Low contain the adjusted timer value
		return		
;----------------------------------------		
Timer1_Channel_Pulse
		;move the prepared timing values into the timer registers and start the timer
		movfw	CP_Low
		movwf	TMR1L
		movfw	CP_High
		movwf	TMR1H
		movlw	0x21
		movwf 	T1CON			;start Timer1 with prescaler 4 : 1			;Bank 0
		if Positive
			bsf		PPM_Out			;make output pin high          ____|--------------------------
		else
			bcf		PPM_Out			;make output pin low           ----|__________________________
		endif
;--------		
Wait_Ch_H
		btfss	PIR1,0			;wait until t1 has timed out				;Bank 0
		goto	Wait_Ch_H
;--------
		bcf	Channel3 ;;;; îòïóñêàì âûâîä Channel3 
	;reset pending Interrupts
		clrf	T1CON											;Bank 0
		bcf		PIR1,0		;reset IR Flag						;Bank 0	
		return

;=============================================================================================
;=============================================================================================
Copy_CH2_EEProm
;		btfsc	FS_Done
;		return
		bcf		INTCON,7			;disable all Interrupts GIE				Bank 0,1 		
		movlw	.18					;setup Bytecount including checksum
		movwf	Byte_Count			;save to Byte_Count
		movlw	Copy_Byte1			;Data-Address of Byte1, where data comes from
		movwf	FSR					;									Bank 0,1
		movlw	0x40				;Startaddress of EEprom where FS data are to be stored
		movwf	To_Adrs				;		
;---------------------
EE_Again		
		call	EEProm_Write
		incf	FSR,F				;									Bank 0,1
		incf	To_Adrs,F
		decfsz	Byte_Count,F		;all bytes written?
		goto	EE_Again				;no, do next byte
;---------------------		
		bsf		FS_Done
		return
	
;=============================================================================================
CheckSum
;the first 8 words have to be added as 16bit words. The next 16bit word is the checksum
;Data is received with low 8bit byte first, then high 8bit byte
;Datastream:           EE05 EA05 3D06 0306 D205 FB03 DC05 DC05 9D2D
;numeric value:        05EE 05EA 063D 0603 05D2 03FB 05DC 05DC 2D9D
;Checksumcalculation:  05EE + 05EA+ + 063D + 0603 + 05D2 + 03FB + 05DC + 05DC = 2D9D
;Servo pulse length:   1518   1514    1597   1539   1490   1019   1500   1500  [usec]

;for the checksum, we must add 16bit words. We add up the low order bytes in W and collect the carry bits in Cksum_High
;we exit, if checksum low miscompares.
;we take Cksum_High and add up the high order bytes and compare with checksum high

		bcf		Checksum_Ok			;switch it off, will be switched on, if checksum is ok
		clrf	Cksum_High
		movlw	Byte3				;Address of 2. lo Byte
		movwf	FSR				;									Bank 0,1
		movlw	.7					;load one byte to w and then sum up 7 more low bytes to compare with check sum low
		movwf	Byte_Count
		movf	Byte1,W				;Data of Byte1 to W 
Sum_Up_Lo		
		addwf	INDF,W				;add 7 low bates to W						Bank 0,1
		btfsc	STATUS,C			;increment cksum_high, whenever a carry occures
		incf	Cksum_High,F		
		incf	FSR,F				;increment FSR twice, to point to next lobyte
		incf	FSR,F
		decfsz	Byte_Count,F		;all low bytes handled?		
		goto	Sum_Up_Lo			;no, do next byte
;compare Checksum Low
		;Checksum low is in W, FSR points to received checksum_low
		subwf	INDF,W				;subtract one from the other
									;If checksums low were equal, result is zero
		btfss	STATUS,Z			;check status for zero								
		goto	Fail				;Result not zero, checksums did not compare
;----------------------		
		movlw	.8					;we have to sum up checksum_high with 8 bytes of channel data high. 
		movwf	Byte_Count
		movlw	Byte2				;Address of 1. hi Byte
		movwf	FSR				;									Bank 0,1
		movf	Cksum_High,W		;the summed up carries from sum_up_lo
Sum_Up_Hi		
		addwf	INDF,W				;add Data high from Byte2 - 16 to W						Bank 0,1
		incf	FSR,F				;increment FSR twice, to point to next hibyte
		incf	FSR,F
		decfsz	Byte_Count,F		;all high bytes handled?			
		goto	Sum_Up_Hi			;no, do next byte
;compare Checksum High
		;W holds Checksum low, FSR points to Checksum-high
		subwf	INDF,W				;subtract one from the other
									;If checksums high were equal, result is zero
		btfss	STATUS,Z			;check status for zero									
		goto	Fail				;Result not zero, checksums did not compare

;Checksum ok,we can allow to copy the channel data so we have them on hand,in case of an interrupted transmission
;nevertheless, the receiver itself continues to send data for about 2 seconds, if the transmission fails
		bsf		Checksum_Ok	

;in case of valid received channel data, we set the residual_signal_lost counter to it's max value
		movlw	Max_Signal_Lost	
		movwf	SL_Counter
			
;		bcf		LED					;for debug only
		return
	
Fail	
;		bsf		LED					;for debug only
		movf	SL_Counter,F	;set condition code
		btfss	STATUS,Z	;decrement til Zero
		decf	SL_Counter,F

		return		
		
		
;=============================================================================		
;copy the actual channel data from Byte1 - Byte16 to Copy_Byte1 ff 
Copy_Ch_Data
	;if bind jumper is plugged, save data as fail safe data to EEPROM. Data is Checksum checked
		btfss	BindLine		;High=no plug jumpered, don't save channel data as fail safe
		call	Copy_CH2_EEProm		;save actual channel data as fail safe settings


		movlw	.16
		movwf	Byte_Count
		
		movlw	Copy_Byte1
		movwf	To_Adrs
		
		movlw	Byte1
		movwf	From_Adrs		
Copy_Cont		
		movf	From_Adrs,W		;source address into W
		movwf	FSR				;and to FSR
		movf 	INDF,W			;address where to read data from
		movwf	Temp			;save data to Temp 
		
		movf	To_Adrs,W			;get target address
		movwf	FSR				;put to FSR 
		movf 	Temp,W			;get data to be copied from Temp 
		movwf	INDF			;and move them to target 
		incf	From_Adrs,F		;increment source address
		incf	To_Adrs,F		;increment target address
		decfsz	Byte_Count,F	;decrement bytecounter
		goto	Copy_Cont		;move the next byte
		return
		
;=============================================================================				
EEProm_Write
;source address already in FSR, target address in To_Adrs
		movf	To_Adrs,W			;use target address
		bsf		STATUS,RP0			;select Bank 1 					Bank 0,1
		movwf	EEADR				;load it						Bank 1
		
		movf	INDF,W				;get data from source into W		Bank 0,1		
		movwf	EEDATA				;move to EEDATA			Bank 1
		bsf		EECON1,WREN			;Enable writing			Bank 1
		movlw	55h
		movwf	EECON2				;						Bank 1
		movlw	0xAA				
		movwf	EECON2				;						Bank 1
		bsf		EECON1,WR			;start writing    		Bank 1
		bcf		STATUS,RP0			;select bank 0					Bank 0,1
;------------------		
EE_Wait								;Wait for EEProm Write to finish		
		btfss	PIR1,EEIF			;wrinting has finished, when the flag has been set		Bank 0
		goto	EE_Wait				;not yet finished
;------------------				
		bcf		PIR1,EEIF			;clear interrupt flag										Bank 0
		return				
;===============================================================================
;Read Fail_Safe data from EEProm and copy to Copy_Byte1 ff 
Fail_Safe_Lesen
		movlw	.16					;setup Bytecount
		movwf	Byte_Count			;move to Byte_Count
		movlw	0x40 				;setup source address
		movwf	From_Adrs				;									Bank 0,1
		movlw	Copy_Byte1				;seetup target address
		call	Lesen
		return
;================================================================================
;read binding data from EEProm and copy to Byte1 - Byte10 
Bind_Lesen
		movlw	.10					;setup Bytecount
		movwf	Byte_Count			;move to Byte_Count
		movlw	0x30				;.34 				;source address from EEprom
		movwf	From_Adrs				;									Bank 0,1
		movlw	Byte1				;target address for Byte1
		call	Lesen
		return
;=================================================================================

Lesen

		movwf	FSR					;target address to FSR				Bank 0,1

L_Again		
		
		call	EEProm_Read			;read a byte from EEProm
		incf	From_Adrs,F
		incf	FSR,F				;									Bank 0,1
		decfsz	Byte_Count,F		;all bytes done?          
		goto	L_Again				;no, do next byte
		return

;=================================================================================
EEProm_Read
		movf	From_Adrs,W			;get source adresse
		bsf		STATUS,RP0			;select Bank 1						Bank 0,1
		movwf	EEADR				;holds Adress to be read			Bank 1
		bsf		EECON1,RD			;Start EE Read						Bank 1
		movf	EEDATA,W			;									Bank 1
		movwf	INDF				;store to target adresse (Byte1 - Byte9)	Bank 0,1
		bcf		STATUS,RP0			;select Bank 0						Bank 0,1
		return


;=================================================================================   
       org 0x3ff

       retlw 0xFF

; initialize eeprom locations

EE		CODE	0x2100
		DE	"Reinhard Strauch 2009; Decoder"
		DE	Prog_Level				;Programmversion
		if Positive 
			DE "+"
		else
			DE "-"
		endif
		DE	" "
		
		if PPM_Fail_Safe
			DE "FSon"
		else
			DE "FSoff"
		endif

ID		Code	0x2130		
		;10 Bytes of Bind procedure from transmitter		
		;DE 0xE1,0x5C,0,0,0x55,0x55,0x55,0x55,0x55,0xE6
		DE 0xEE,0x00,0x00,0x00,0x55,0x55,0x55,0x55,0x55,0x97	;dollop

		;Initial Fail Safe Setting - neutral - for all servo channels DC05 -> 05DC = 1500
FS		Code	0x2140	
		DE 0xDC,0x05,0xDC,0x05,0xAC,0x04,0xDC,0x05,0xDC,0x05,0xDC,0x05,0xDC,0x05,0xDC,0x05
		END                       ; directive 'end of program'



