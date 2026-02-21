# Multi-Stage vs Single-Stage Docker Build Comparison

A simple Express + TypeScript app to demonstrate the image size difference between single-stage and multi-stage Docker builds.

## Step 1: Build the Single-Stage Image

```bash
docker build -f Dockerfile.singlestage -t demo-single .
```

This builds everything in one stage. The final image contains dev dependencies (TypeScript, @types/*), source code, and compiled output.

## Step 2: Build the Multi-Stage Image

### Why Multi-Stage?

**During build time** (`npm run build`), you need all those dev tools:

- `typescript` - to compile `.ts` → `.js`
- `eslint` + plugins - to check code quality before shipping
- `jest` + `supertest` - to run tests before shipping
- `webpack` + `ts-loader` - to bundle code
- `prettier` - to format code
- `husky` + `lint-staged` - to enforce quality on git commits
- `swagger-jsdoc` - to generate API docs
- `nodemon` + `ts-node` - for local development hot-reload

**During runtime** (`node dist/index.js`), the compiled JavaScript only needs:

- `express` - to serve HTTP requests
- `cors` - to handle cross-origin requests
- `helmet` - for security headers
- `morgan` - for request logging
- `dotenv` - to read environment variables
- `zod` - for input validation

The `dist/` folder is plain JavaScript - it doesn't care about TypeScript, linters, or test frameworks anymore. It just runs on Node.js with the production packages.

That's exactly what multi-stage does - **stage 1** is your *workshop* with all the tools, **stage 2** is the *delivery truck* carrying only the finished product. In a real company with a large codebase, dev dependencies can easily be **500+ MB** while production deps might be just **50–100 MB**.

```bash
docker build -f Dockerfile -t demo-multi .
```

This uses two stages. The final image only contains production dependencies and the compiled JavaScript output.
## Step 3: Compare Image Sizes

```bash
docker images | grep demo
```

Expected output (approximate):

```
demo-single    latest    abc123    10 seconds ago    ~590 MB
demo-multi     latest    def456    5 seconds ago     ~390 MB
```

That's a 203 MB difference. You can immediately see that the multi-stage build discards all the unnecessary dev tooling and ships only what's needed to run the app.