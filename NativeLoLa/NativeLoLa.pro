TEMPLATE = lib
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

CONFIG += static

SOURCES += \
  ast.cpp \
  common_runtime.cpp \
  compiler.cpp \
  driver.cpp \
  error.cpp \
  il.cpp \
  lolacore.cpp \
  runtime.cpp

HEADERS += \
  ast.hpp \
  common_runtime.hpp \
  compiler.hpp \
  driver.hpp \
  error.hpp \
  grammar.tab.h \
  il.hpp \
  lolacore.hpp \
  runtime.hpp \
  scanner.hpp

YACCSOURCES += \
  grammar.yy

LEXSOURCES += \
  yy.ll
