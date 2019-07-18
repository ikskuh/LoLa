TEMPLATE = lib
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

CONFIG += static

INCLUDEPATH += $$PWD/include/LoLa
DEPENDPATH  += $$PWD/include/LoLa

YACCSOURCES += \
  src/grammar.yy

LEXSOURCES += \
  src/yy.ll

HEADERS += \
  include/LoLa/common.hpp \
  include/LoLa/compiler.hpp \
  include/LoLa/il.hpp \
  include/LoLa/runtime.hpp \
  include/LoLa/tombstone.hpp \
  include/LoLa/ast.hpp \
  src/driver.hpp \
  include/LoLa/error.hpp \
  grammar.tab.h \
  src/scanner.hpp

SOURCES += \
  src/ast.cpp \
  src/common.cpp \
  src/compiler.cpp \
  src/driver.cpp \
  src/error.cpp \
  src/il.cpp \
  src/runtime.cpp \
  src/tombstone.cpp
