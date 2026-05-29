---
name: add-ffi
description: Add a new FFI function bridging the Rust audio engine and Flutter/Dart UI. Handles all 7-8 files that need updating.
---

# Add FFI Function

The user will describe what engine function they need. Follow these steps **in order** to add it across all layers. Read each target file before editing.

## Step 1: Rust API (`engine/src/api/<domain>.rs`)

Add the business logic function. Return `Result<T, String>` for fallible operations.

```rust
pub fn my_function(param: i32) -> Result<String, String> {
    with_graph(|graph| {
        // business logic here
        Ok("Done".to_string())
    })
}
```

- Use `with_graph()` for read-only access, `with_graph_mut()` for mutation
- Use `get_audio_graph()?` + manual lock for try_lock patterns
- If adding a new api module file, register it in `engine/src/api/mod.rs` and re-export

## Step 2: Rust FFI (`engine/src/ffi/<domain>.rs`)

Wrap the API function for C export.

**String return, no string params:**
```rust
#[no_mangle]
pub extern "C" fn my_function_ffi(param: i32) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), || {
        match api::my_function(param) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    })
}
```

**With string params** (use `AssertUnwindSafe`):
```rust
#[no_mangle]
pub extern "C" fn my_function_ffi(name: *const c_char) -> *mut c_char {
    ffi_catch(std::ptr::null_mut(), AssertUnwindSafe(|| {
        let name_str = unsafe {
            match CStr::from_ptr(name).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => return safe_cstring("Error: Invalid UTF-8".to_string()).into_raw(),
            }
        };
        match api::my_function(&name_str) {
            Ok(msg) => safe_cstring(msg).into_raw(),
            Err(e) => safe_cstring(format!("Error: {e}")).into_raw(),
        }
    }))
}
```

**Numeric return:**
```rust
#[no_mangle]
pub extern "C" fn my_function_ffi() -> f64 {
    ffi_catch(0.0, || {
        api::my_function().unwrap_or(0.0)
    })
}
```

- If adding a new ffi module file, register it in `engine/src/ffi/mod.rs`: `mod my_module;`
- The function name MUST end with `_ffi` suffix

## Step 3: Dart Typedefs (`ui/lib/audio_engine_typedefs.dart`)

Add both native and Dart typedefs near related functions.

```dart
// Native (C types)
typedef _MyFunctionFfiNative = ffi.Pointer<Utf8> Function(ffi.Int32 param);
// Dart (Dart types)
typedef _MyFunctionFfi = ffi.Pointer<Utf8> Function(int param);
```

**Type mapping:**

| Rust | Dart Native (C) | Dart |
|------|-----------------|------|
| `*mut c_char` (return) | `ffi.Pointer<Utf8>` | `ffi.Pointer<Utf8>` |
| `*const c_char` (param) | `ffi.Pointer<ffi.Char>` | `ffi.Pointer<ffi.Char>` |
| `f32` | `ffi.Float` | `double` |
| `f64` | `ffi.Double` | `double` |
| `i32` | `ffi.Int32` | `int` |
| `i64` | `ffi.Int64` | `int` |
| `u32` | `ffi.Uint32` | `int` |
| `u64` | `ffi.Uint64` | `int` |
| `bool` | `ffi.Bool` | `bool` |

## Step 4: Dart Symbol Lookup (`ui/lib/audio_engine_base.dart`)

Add the late final field with other fields of the same domain:
```dart
late final _MyFunctionFfi _myFunction;
```

Add the lookup in the constructor, near related lookups:
```dart
_myFunction = _lib
    .lookup<ffi.NativeFunction<_MyFunctionFfiNative>>('my_function_ffi')
    .asFunction();
```

**CRITICAL**: The string `'my_function_ffi'` must match the Rust `#[no_mangle]` name exactly.

## Step 5: Dart Wrapper (`ui/lib/audio_engine_<domain>.dart`)

Add a public method in the appropriate mixin (transport, tracks, recording, or plugins).

**String return:**
```dart
String myFunction(int param) {
  try {
    final resultPtr = _myFunction(param);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  } catch (e) {
    rethrow;
  }
}
```

**String param:**
```dart
String myFunction(String name) {
  try {
    final namePtr = name.toNativeUtf8();
    final resultPtr = _myFunction(namePtr.cast());
    malloc.free(namePtr);
    final result = resultPtr.toDartString();
    _freeRustString(resultPtr);
    return result;
  } catch (e) {
    rethrow;
  }
}
```

- Use `print()` not `debugPrint()` in this file
- Always free Rust-allocated strings with `_freeRustString()`
- Always free Dart-allocated strings with `malloc.free()`

## Step 6: Interface (`ui/lib/services/commands/audio_engine_interface.dart`)

Add the abstract method signature:
```dart
String myFunction(int param);
```

## Step 7: Stub (`ui/lib/audio_engine_stub.dart`)

Add the stub implementation:
```dart
@override
String myFunction(int param) => throw UnsupportedError('stub');
```

## Step 8: Web (`ui/lib/audio_engine_web.dart`)

Add the web implementation. If web support isn't needed yet, add a TODO stub:
```dart
@override
String myFunction(int param) {
  // TODO: implement web support
  return 'Not supported on web';
}
```

If web IS supported, use the JS interop helpers:
```dart
@override
String myFunction(int param) {
  final result = _callEngineWith('my_function', [param.toJS]);
  return _jsToString(result) ?? 'Error';
}
```

## Verification Checklist

After completing all steps, verify:
1. **Rust compiles**: run `cargo build` in `engine/`
2. **Dart analyzes**: run `flutter analyze` in `ui/`
3. **Symbol match**: the lookup string in Step 4 matches the `#[no_mangle]` name in Step 2
4. **Memory safety**: Rust strings freed via `_freeRustString()`, Dart strings freed via `malloc.free()`
5. **Update CHANGELOG.md** if this is a user-facing feature
