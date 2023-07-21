SRCS := $(wildcard src/*.cc)
OBJS :=  $(SRCS:src/%.cc=build/%.o)
CXXFLAGS := -Iinclude -W -Wall -g -std=c++17

all : fithfont

conman : $(OBJS)
	clang++ -o $@ $+

clean :
	@rm -rf build fithfont

build/%.o : src/%.cc Makefile
	@mkdir -p $(@D)
	clang++ $(CXXFLAGS) -c $< -o $@

install : fithfont
	@cp fithfont $(BIN_DIR)

