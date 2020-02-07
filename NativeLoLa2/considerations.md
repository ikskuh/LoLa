# Considerations on the implementation of NativeLoLa version 2

- object references should be non-pointer types
  - two callbacks:
    - `getObject(objectName: []const u8) ?oid`
    - `callFunction(object: oid, name: []const u8) FunCallOrImmediate`
    - `isObjectHandleValid(object: oid) bool`
  - objects may be invalidated at any time, but never at VM execution time
  - VM must check if a foreign object stack still exists before calling it
- implement copy-on-write arrays for improved performance?
  - probably too much implementation overhead
- possibly implement a garbage collector
  - only the current stack and global variables may store values
  - all temporary values may be freed afterwards
  - different environments may "share" values
    - GC implementation would be harder
