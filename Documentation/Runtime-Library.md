# LoLa Runtime Library

This file documents the LoLa Runtime Library, a set of basic I/O routines to enable standalone LoLa programs.

The API in this document is meant for the standalone LoLa interpreter and functions listed here are not necessarily available in embedded programs! 

## Generic

### `Exit(code: number): noreturn`

This function will stop execution of the program and will return `code` to the OS.

## File I/O

### `ReadFile(path: string): string|void`

Reads in the contents of a file located at `path` as a `string` or returns `void` when the file does not exist or the given path is not a file.

### `WriteFile(path: string, contents: string): void`

Writes `contents` to the file located at `path`. If the file does not exist, it will be created.

### `FileExists(path: string): boolean`

Returns `true` if a file exists at the given `path`, `else` otherwise.

## Console I/O

### `Print(…): void`

Will print every argument to the standard output. All arguments of type `string` will be printed verbatim, non-`string` arguments are converted into a human-readable form and will then be printed.

After all arguments are printed, a line break will be outputted.

### `ReadLine(): string|void`

Reads a line of text from the standard input and returns it as a `string`. If the standard input is in the *end of file* state, `void` will be returned.

## Standard Objects

### `CreateList([init: array]): object`

Returns a new object that implements a dynamic list.

If `init` is given, the list will be initialized with the contents of `init`.

This list has the following API:

#### `list.Add(item): void`
Appends a new item to the back of the list.

#### `list.Remove(item): boolean`
Removes all occurrances of `item` in the list.

#### `list.RemoveAt(index): void`
Removes the item at `index`. Indices start at `0`. When the index is out of range, nothing will happen.

#### `list.GetCount(): number`
Returns the current number of elements in the list.

#### `list.GetItem(index): any`
Returns the item at `index` or panics with `OutOfRange`;

#### `list.SetItem(index, value): void`
Replaces the item at `index` with `value`.

#### `list.ToArray(): array`
Returns the current list as an array.

#### `list.IndexOf(item): number`
Returns first the index of `item` in the list or `void` if the item was not found.

#### `list.Resize(size): void`
Resizes the list to `size` items. New items will be set to `void`.

#### `list.Clear(): void`
Removes all items from the list.

### `CreateDictionary(): object`

Returns a new object that implements a key-value store.

#### `dict.Get(key): any`
Returns the value associated with `key` or returns `void` if `key` does not have a associated value.

#### `dict.Set(key, value): void`
Sets the associated value for `key` to `value`. If `value` is `void`, the key will be removed.

#### `dict.Remove(key): boolean`
Removes any value associated with `key`. Returns `true` when a key was removed else `false`.

#### `dict.Contains(key): boolean`
Returns `true` if the dictionary contains a value associated with `key`.

#### `dict.GetKeys(): array`
Returns an array with all keys stored in the dictionary.

#### `dict.GetValues(): array`
Returns an array with all values stored in the dictionary.

#### `dict.Clear(): void`
Removes all values from the dictionary.

#### `dict.GetCount(): number`
Returns the number of keys currently stored in the list.

