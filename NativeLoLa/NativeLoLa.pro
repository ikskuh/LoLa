TEMPLATE = lib
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

CONFIG += static

SOURCES += \
  ast.cpp \
  driver.cpp \
  lolacore.cpp

HEADERS += \
  ast.hpp \
  driver.hpp \
  grammar.tab.h \
  lolacore.hpp \
  scanner.hpp

YACCSOURCES += \
  grammar.yy

LEXSOURCES += \
  yy.ll
