obj-m += rpad.o

rpad-y := rp_pl.o rp_pl_hw.o rp_scope.o rp_hk.o

all:
	$(Q)$(MAKE) ARCH=arm CROSS_COMPILE=arm-xilinx-linux-gnueabi- -C ../../../linux/linux-xlnx M=$(PWD) modules

clean:
	$(Q)$(MAKE) ARCH=arm -C ../../../linux/linux-xlnx M=$(PWD) clean

