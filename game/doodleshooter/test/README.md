# Game tests

Run with Node's built-in test runner — there is no test framework dependency, and there must not
be one:

```bash
node --test
```

Test files use the `.mjs` extension because the game deliberately has no `package.json`, so Node
would otherwise treat a `.js` file as CommonJS.

Note: `node --test test/` (with a trailing slash) fails on Node 24 — use bare `node --test`, which
discovers `test/**/*.test.mjs` automatically.

`vendor/`, `public/` and this directory are excluded from source scans.
