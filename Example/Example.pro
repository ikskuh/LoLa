TEMPLATE = app
CONFIG += console c++17
CONFIG -= app_bundle
CONFIG -= qt

SOURCES += \
        main.cpp



win32:CONFIG(release, debug|release): LIBS += -L$$OUT_PWD/../NativeLoLa/release/ -lNativeLoLa
else:win32:CONFIG(debug, debug|release): LIBS += -L$$OUT_PWD/../NativeLoLa/debug/ -lNativeLoLa
else:unix: LIBS += -L$$OUT_PWD/../NativeLoLa/ -lNativeLoLa

INCLUDEPATH += $$PWD/../NativeLoLa
DEPENDPATH += $$PWD/../NativeLoLa

win32-g++:CONFIG(release, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../NativeLoLa/release/libNativeLoLa.a
else:win32-g++:CONFIG(debug, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../NativeLoLa/debug/libNativeLoLa.a
else:win32:!win32-g++:CONFIG(release, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../NativeLoLa/release/NativeLoLa.lib
else:win32:!win32-g++:CONFIG(debug, debug|release): PRE_TARGETDEPS += $$OUT_PWD/../NativeLoLa/debug/NativeLoLa.lib
else:unix: PRE_TARGETDEPS += $$OUT_PWD/../NativeLoLa/libNativeLoLa.a
