To develop, [install Nim](https://nim-lang.org/install.html) and do:

```
nimble run super_koalio
```

To develop with [paravim](https://github.com/paranim/paravim) (toggled by pressing `Esc`):

```
nimble dev
```

Or to make a release build:

```
nimble build -d:release
```

Or to make a release build for the web:

```
nimble build -d:release -d:emscripten
```

NOTE: To build for the web, you must install Emscripten:

```
git clone https://github.com/emscripten-core/emsdk
cd emsdk
./emsdk install 3.1.0
./emsdk activate 3.1.0
# add the dirs that are printed by the last command to your PATH
```
