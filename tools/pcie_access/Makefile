
BUILD=./build

build: 
	@mkdir -p $(BUILD)

bar_rw: build
	$(CC) -o $(BUILD)/bar_rw bar_rw.c $(CFLAGS) $(LDFLAGS)

clean: 
	@rm -rf $(BUILD)