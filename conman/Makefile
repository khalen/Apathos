SRCS := $(wildcard src/*.cc)
OBJS :=  $(SRCS:src/%.cc=build/%.o)
CXXFLAGS := -Iinclude -W -Wall -g -std=c++17

all : conman

conman : $(OBJS)
	clang++ -o $@ $+

clean :
	@rm -rf build conman

build/%.o : src/%.cc Makefile
	@mkdir -p $(@D)
	clang++ $(CXXFLAGS) -c $< -o $@

install : conman
	@cp conman $(BIN_DIR)
