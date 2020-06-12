To develop, [install Nim](https://nim-lang.org/install.html) and do:

```
nimble dev
```

Or to make a release build:

```
nimble build -d:release
```

This project is preconfigured to show [paravim](https://github.com/paranim/paravim) in dev mode by pressing `Esc`. If you are getting a "could not load" error, you can disable it in `config.nims`.