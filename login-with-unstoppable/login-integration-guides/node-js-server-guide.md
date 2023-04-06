---
title: Node.js Server Guide for Login with Unstoppable | UD Developer Portal
description: This integration guide is intended for a custom @uauth/node integration for server-side applications and does not come with a default front-end UI.
showNextButton: false
---

# Node.js Server Guide: Login with Unstoppable

This integration guide is for the `@uauth/node` library used in server-side applications. It does not come with a default front-end UI and requires custom front-end UI development. For more information about this library, please see the associated [github repo](https://github.com/unstoppabledomains/uauth/tree/main/packages/node).

:::warning
The example code in this guide assumes that ECMAScript modules are [enabled](https://nodejs.org/dist/latest-v16.x/docs/api/esm.html#enabling). Otherwise, `import` statements should be replaced with CommonJS `require()` statements.
:::

## Step 1: Configure the Login Client

Add `http://localhost:5000/callback` to your client's [Redirect URIs](/login-with-unstoppable/login-integration-guides/login-client-configuration.md#redirect-uris). Make sure that the port matches the port your app is being served to. Example code in this guide assumes port 5000.

Set the [Token Endpoint Authentication Method](/login-with-unstoppable/login-integration-guides/login-client-configuration/#token-endpoint-authentication-method) on your client dashboard to **Client Secret Post**. Once you've clicked the **Confirm Changes** button, `clientSecret` and `clientAuthMethod` will be added to your client metadata on the **Basic** configuration page.

```javascript
{
  clientID: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  clientSecret: "xxxxxxxxxxxxxxxxxxxxxxxxxx",
  clientAuthMethod: "client_secret_post",
  redirectUri: "http://localhost:5000/callback",
  scope: "openid wallet"
}
```

## Step 2: Install the @uauth/node Library

Install the `@uauth/node` and resolution packages with `yarn` or `npm`.

```shell yarn
yarn add @uauth/node @unstoppabledomains/resolution
```

```shell npm
npm install --save @uauth/node @unstoppabledomains/resolution
```

For the example in this guide, you will also need to install the following packages:

```shell yarn
yarn add express-session express express-async-errors morgan
```

```shell npm
npm install --save express-session express express-async-errors morgan
```

## Step 3: Setup @uauth/node Library

You can then initialize a new `Client` instance using the Client Metadata copied from the **Basic** page.

```typescript
import {Client} from '@uauth/node'
import Resolution from '@unstoppabledomains/resolution'
// This package requires a fetch polyfill for now.

import 'whatwg-fetch'

global.XMLHttpRequest = require('xhr2')
global.XMLHttpRequestUpload = (
  global.XMLHttpRequest as any
).XMLHttpRequestUpload

// Initialize the client with the login client metadata and an instance of Resolution

const clientSecret = 'xxxxxxxxxxxxxxxxxxxxxxxxxx'
const client = new Client({
  clientID: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
  clientSecret: clientSecret,
  redirectUri: 'http://localhost:5000/callback',
  scope: 'openid wallet',
  resolution: new Resolution({ apiKey: clientSecret}),
})
```

## Step 4: Build the Server's Endpoints

Because there are a variety of ways to store session data about a user, the package comes with a way to specify in an abstract way the three methods required to authorize and maintain a user session.

### The Login Method

**`login(ctx: Context, options: {username: string}): Promise<void>`**

1. Takes a username and generates an interaction object, saves it to a session.
2. Queries the blockchain to find if an auth server has been configured otherwise uses fallback.
3. Redirects the user to the auth server with a OIDC compliant authorization request.
4. After every authorization attempt the server will redirect the user to the `redirectUri` specified at instantiation.

### The Callback Method

**`callback(ctx: Context): Promise<Authorization>`**

1. Parses authorization code found in current uri.
2. Exchanges authorization code for access and id tokens.
3. Stores authorization (id and access tokens) inside session.

### The Middleware Method

**`middleware(): (ctx: Context) => void`**

1. The authorization inside the session is attached to the context then passed to the next handler.
2. If there is no session, it throws an Error.

### Putting it all together

The following is an example of using the pre-configured `express-session` to implement login.

```javascript
import session from 'express-session'
import express from 'express'
import 'express-async-errors'
import morgan from 'morgan'

const app = express()

app.use(morgan('dev'))

// Required for express session middleware
app.use(session({secret: 'keyboard cat'}))

// Required for /login & /callback
app.use(express.urlencoded({extended: true}))

const {login, callback, middleware} = client.createExpressSessionLogin()

app.post('/login', (req, res, next) => {
  return login(req, res, next, {
    username: req.body.domain,
  })
})

app.post('/callback', async (req, res, next) => {
  console.log('Calling back!')

  await callback(req, res, next)

  return res.redirect('/profile')
})

const onlyAuthorized = middleware()

app.get('/profile', onlyAuthorized, (req, res) => {
  res.json(res.locals.uauth)
})
```

Developers can also create their own login system using a different session system from `express-session` using the [login() method](#the-login-method).

## Step 5: Build a Front-end UI

The form must call the endpoint where the [`login` handler](node-js-server-guide.md#the-login-method) is called and it must correspond with the parameters to that function.

```javascript
app.get('/', (_, res) => {
  const indexPage =
  `<!DOCTYPE html><html><body>
    <form action="/login" method="POST">
      <input name="domain" id="domain" />
    <button type="submit">Login</button>
    </form>
  </body></html>`

  return res.send(indexPage)
})

app.listen(process.env.PORT, () => {
  console.log(`Listening at http://localhost:${process.env.PORT}`)
})
```

:::success Congratulations!
You just implemented Login with Unstoppable.
:::

<embed src="/snippets/_login-paths-next.md" />
