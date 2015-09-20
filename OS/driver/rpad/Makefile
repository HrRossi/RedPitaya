SRC_DIR := src
INSTALL_DIR ?= .

.PHONY : all install clean

all:
	make -C $(SRC_DIR)

install: $(SRC_DIR)/rpad.ko
	mkdir -p $(INSTALL_DIR)/bin/
	cp $(SRC_DIR)/rpad.ko $(INSTALL_DIR)/bin

clean:
	-make -C $(SRC_DIR) clean

