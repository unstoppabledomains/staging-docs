#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Create folder structure
mkdir -p project/{client,server/src/{data,types}} && cd project

# Initialize NPM and install dependencies
npm init --yes && npm install --save-dev concurrently
npx json -I -f package.json -e 'this.workspaces=["client", "server"]'
npx json -I -f package.json -e 'this.scripts={
  "start": "concurrently \"npm run start:client\" \"npm run start:server\"",
  "start:client": "npm run dev --workspace client",
  "start:server": "npm run dev --workspace server",
  "install:all": "npm install && npm install --workspace client && npm install --workspace server"
}'

# Create Next.js app
npx create-next-app@latest client --ts --tailwind --app --src-dir --no-eslint --use-npm --empty --yes
mkdir -p client/src/{app/{api,cart,checkout,components,context,order,utils},types}
npm install --save @uauth/js axios --workspace client

# Set up server workspace
npm init --yes --workspace server
npm install --save-dev typescript ts-node nodemon @types/node @types/express @types/cors --workspace server
npm install --save axios cors dotenv express jose lowdb --workspace server

cd server

# Configure server package.json
npx json -I -f package.json -e 'this.scripts={
  "build": "npx tsc",
  "start": "node dist/server.js",
  "dev": "nodemon src/server.ts"
}'
npx json -I -f package.json -e 'this.exports="./server.js"'
npx json -I -f package.json -e 'this.type="module"'

touch tsconfig.json && touch nodemon.json

# Create TypeScript config
cat << EOF > tsconfig.json
{"compilerOptions": {
  "target": "ES2017",
  "module": "ESNext",
  "rootDir": "./src",
  "moduleResolution": "node",
  "outDir": "./dist",
  "esModuleInterop": true,
  "forceConsistentCasingInFileNames": true,
  "strict": true,
  "skipLibCheck": true
},
"include": ["src/**/*"],
"exclude": ["node_modules", "dist"]}
EOF

# Create Nodemon config
cat << EOF > nodemon.json
{
  "watch": ["src"],
  "ext": "ts",
  "execMap": {
    "ts": "node --loader ts-node/esm"
  }
}
EOF

cd ..

# Download type files
curl -s -o "./server/src/types/auth.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/auth.d.ts"
curl -s -o "./server/src/types/domains.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/domains.d.ts"
curl -s -o "./server/src/types/orders.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/orders.d.ts"
curl -s -o "./server/src/types/returns.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/returns.d.ts"
curl -s -o "./server/src/types/suggestions.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/suggestions.d.ts"
curl -s -o "./server/src/types/transfers.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/server/src/types/transfers.d.ts"
curl -s -o "./client/src/types/auth.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/client/src/types/auth.d.ts"
curl -s -o "./client/src/types/cart.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/client/src/types/cart.d.ts"
curl -s -o "./client/src/types/domains.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/client/src/types/domains.d.ts"
curl -s -o "./client/src/types/orders.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/client/src/types/orders.d.ts"
curl -s -o "./client/src/types/suggestions.d.ts" \
  "https://raw.githubusercontent.com/unstoppabledomains/demos/refs/heads/vincent/full-flow/Unstoppable%20Partner%20API%20Example/client/src/types/suggestions.d.ts"

# Run installation script
npm run install:all
