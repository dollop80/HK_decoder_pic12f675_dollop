Decodes the digital data that the satellite receiver supplies

Uses the digital data to Create a PPM datastream of up to eight channel pulses (Output on Pin6)

Polarity of output signal is selectable with a single setting at compile time

reads and saves the binding information into the EEPROM when the bind plug is attached

initializes the satellite receiver with bind information on normal power on

saves the current channel values as fail safe defaults when the the bind plug is put on momentarily during normal receive

On signal loss, the satellite receiver continues to supply the last valid data for about two seconds. 

When the decoder recognizes a signal loss or invalid data, it repeats the last valid datastream up to three times.
After that, it switches to the fail safe data, stored in EEPROM. Default programmed fail safe is channel 3 low and all others neutral
Uses channel data again as soon as available.


If the compile time switch PPM_FailSafe=0 the output will be suppressed while in fails safe situation

dollop
модифицировал прошивку. ”брал светодиод.
—делал, чтобы на выводе LED (GPIO,0 вывод 7, вместо светодиода) выводилс€ PWM канала газа (у мен€ это канал 3). —делано дл€ того, чтобы можно было прилепить пищалку на канал, котора€ бы пищала когда не дрыгаешь газом. Ќомер канала можно помен€ть в строке 763. ¬се остальное без изменений



