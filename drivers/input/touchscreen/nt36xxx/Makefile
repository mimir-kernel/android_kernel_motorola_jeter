# SPDX-License-Identifier: GPL-2.0-only
#
# Makefile for the Novatek NT36xxx touchscreen driver.
#

# Each configuration option enables a list of files.

obj-$(CONFIG_TOUCHSCREEN_NT36XXX_I2C_MOTO8937) += nt36xxx-i2c-moto8937.o
nt36xxx-i2c-moto8937-y := nt36xxx.o nt36xxx_fw_update.o nt36xxx_ext_proc.o nt36xxx_mp_ctrlram.o

obj-$(CONFIG_TOUCHSCREEN_NT36XXX_SPI_MOTO8937) += nt36xxx-spi-moto8937.o
nt36xxx-spi-moto8937-y := nt36xxx.o nt36xxx_fw_update.o nt36xxx_ext_proc.o
