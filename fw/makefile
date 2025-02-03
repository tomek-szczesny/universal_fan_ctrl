
build:
	avra universal_fan_ctrl.asm

burn:
	sudo avrdude -c buspirate -P /dev/ttyUSB0 -B 100 -p m8 -v -U flash:w:universal_fan_ctrl.hex
