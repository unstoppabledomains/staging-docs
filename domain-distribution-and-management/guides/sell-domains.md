---
title: Selling Domains with the Partner API | Unstoppable Domains Developer Portal
description: This page details basic configuration and usage of the Partner API.
---

# Sell Domains with the Partner API

The Partner API v3 provides you with the ability to lookup, register and manage Web3 domains. The API exposes a RESTful interface for interacting with Web3 domains and the Unstoppable Domains registry. Capabilities include:

- Lookup Domains: Search for specific domains or find suggested alternatives, to determine pricing, availability and on-chain details
- Registering Domains: Secure domains into your dedicated Custody wallets to maintain the domains on the blockchain
- Manage Domains: Update records on the blockchain or transfer the domain to external owners, all through a simple API interface

In this integration guide, we will create a Partner API flow focussing on domain lookup and registration. To complete this integration, you should be a JavaScript developer with experience in RESTful APIs.

:::info
If you’d like to skip ahead or follow along, you can clone the [full example](https://github.com/unstoppabledomains/demos/tree/vincent/full-flow/Unstoppable%20Partner%20API%20Example) from GitHub beforehand.
:::

## Step 1: Project Setup

Before we get started, you’ll need to install Node >= v18 and npm. Then, download the following setup script in a unix-like environment (MacOS, Linux, WSL, etc) to create the project directory, install the suggested packages, and create the suggested configuration files. If you do not have access to a unix-environment, clone the [full example](https://github.com/unstoppabledomains/demos/tree/vincent/full-flow/Unstoppable%20Partner%20API%20Example) from GitHub and follow along.

[Download Setup Script](../../static/scripts/setup-pav3-guide.sh)

After downloading the script, move the `setup-pav3-guide.sh` file to your desired directory and run the following commands:

```shell
chmod +x setup-pav3-guide.sh
./setup-pav3-guide.sh
```

This will create a `project` folder in your directory that we will use throughout this guide.

:::info
**@uauth/js** will be the library used for implementing Unstoppable Login on the frontend, **axios** will be used for the API calls on both the client and server, **nodemon** will be used for easier typescript server development, and **lowdb** will act as an interim database on the server to keep the guide self-contained.
:::

## Step 2: Setup Express.js

Express.js will serve as our backend throughout this guide. It will handle all interactions with the Partner API, any necessary database operations, and ideally also implement [webhooks](https://docs.unstoppabledomains.com/domain-distribution-and-management/guides/implementing-webhooks/). To keep this guide self-contained, we will be utilizing `lowdb` as an interim database and will forego webhooks to avoid needing an absolute URL.

It's very important that the Partner API is not directly accessed from a frontend client as the API key is very sensitive. As the API does not handle checkout payments, Unstoppable Domains keeps track of a running balance against the API key for periodic invoicing. It is up to the partner to collect payment from users and subsequently keep their API key secure. 

:::info
There is no charge for developing with the Partner API on our **sandbox** environment. Once you migrate to **production**, a running balance will be kept against your **production API key**.
:::

### Environment Variables

Build out your `./server/.env` file per the below. You can retrieve your Partner API key by following our [Set up Partner API Access Guide](https://docs.unstoppabledomains.com/domain-distribution-and-management/quickstart/retrieve-an-api-key/). 

```javascript
API_URL = 'https://api.ud-sandbox.com/partner/v3'
API_KEY_VALUE = 'xxxxx'
PORT = 3001
```

### Express Endpoints 

With our environment variables configured, we can start outlining the endpoints we'll need to use throughout our guide. We'll need a way to lookup domain suggestions based on a search query, register domains, and check domain availability.  This means the server will need to be prepared to recieve HTTP `POST` requests that have an `application/json` body as well as general HTTP `GET` requests with url query parameters. The request body will depend on the client implementation but in this guide, we will keep things consistent.

Other considerations:
- As the Partner API is dependant on the blockchain, it provides an operation ID for us to use to check current status. We should have some way of tracking these API operations so we know when the operations complete or if there are any problems and handle them appropriately.
- As there is a running balance against the `production` API, we should implement a way to know whether the frontend checkout was successful or not, and handle each case. While there is no cost for using `sandbox` like we are here, our recomendation is to return the registered domain to Unstoppable should checkout fail for any reason. Returns can be made within 14 days of registration and will be deducted from the running balance.
- Should checkout succeed, we should transfer the registered domain to the end-user to custody. 

Here is a basic implementation of our three necessary endpoints using Node and `express`. We'll add this to our `./server/src/server.ts` file.

```typescript
import express, { Express, Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import axios from 'axios';

// Load environment variables from .env file
dotenv.config();

// Set up the Express application instance
const app: Express = express();
const port = process.env.PORT || 3001;

// Unstoppable Domains Sandbox API configurations
const UNSTOPPABLE_SANDBOX_API_KEY = process.env.API_KEY_VALUE as string;
const UNSTOPPABLE_SANDBOX_API_URL = process.env.API_URL as string;

// Middleware setup
app.use(express.json()); // For parsing JSON request bodies
app.use(cors()); // Enable Cross-Origin Resource Sharing

/**
 * GET /api/domains - Fetch domain suggestions based on a query string.
 *
 * @query {string} query - The search term for domain suggestions.
 * @returns {Response} - Returns a JSON response with domain suggestions or an error message.
 */
app.get('/api/domains', async (req: Request, res: Response) => {
  const query = req.query.query as string;
  try {
    const domains = await searchDomains(query);
    res.json(domains);
  } catch (error: any) {
    res.status(500).json({ error: 'Error fetching domains', details: error.message });
  }
});

/**
 * POST /api/register - Registers a domain by its ID.
 *
 * @body {string} domainId - The ID of the domain to be registered.
 * @returns {Response} - Returns a JSON response with registration status or an error message.
 */
app.post('/api/register', async (req: Request, res: Response) => {
  const domainId = req.body.domainId as string;
  try {
    const register = await registerDomain(domainId);
    if (register.error) {
      res.status(500).json(register);
    } else {
      res.json(register);
    }
  } catch (error: any) {
    res.status(500).json({ error: 'Error registering domain', details: error.message });
  }
});

/**
 * POST /api/availability - Checks availability of an array of domains.
 *
 * @body {string[]} domains - Array of domains to check availability.
 * @returns {Response} - Returns a JSON response with availability status or an error message.
 */
app.post('/api/availability', async (req: Request, res: Response) => {
  const domains = req.body.domains as string[];
  try {
    const availability = await checkAvailability(domains);
    if (availability.error) {
      res.status(500).json(availability);
    } else {
      res.json(availability);
    }
  } catch (error: any) {
    res.status(500).json({ error: 'Error checking domain availability', details: error.message });
  }
});

/**
 * Starts the Express server and listens on the specified port.
 * Logs a message to the console once the server is running.
 */
app.listen(port, () => {
  console.log(`Server is running on http://localhost:${port}`);
});
```

### Partner API Proxy

Now that our Express.js server has appropriate endpoints for domain suggestions, domain registration, and domain availability, we need to proxy these endpoints to the Partner API. We'll use our `searchDomains`, `registerDomain`, and `checkAvailability`. functions previously defined for this task. We'll import the appropriate typings from our `./types` directory and make an `axios` request to the appropriate endpoint: 

- `searchDomains()` will be proxied to the [suggestions endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/getSuggestions)
- `registerDomain()` will be proxied to the [registration endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/mintSingleDomain)
- `checkAvailability()` will be proxied to the [domain details endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/getMultipleDomains)

We'll also add error handling here to encompass any issues with our server, `axios`, or the Partner API. Add these to the existing `server/src/server.ts` file.

```typescript searchDomains
import { Suggestions } from './types/suggestions';

/**
 * Searches for domain suggestions based on the provided domain name.
 *
 * This function makes an API call to the Unstoppable Domains suggestions endpoint
 * to retrieve a list of suggested domains related to the provided `domainName`.
 * It returns the suggestions data or an error object if the request fails.
 *
 * @param {string} domainName - The domain name query string to search suggestions for.
 * @returns {Promise<Suggestions>} - A promise that resolves to the Suggestions object,
 * containing either the suggestions data or an error object if an error occurs.
 *
 * @throws {Error} - If an error occurs during the API call, this function catches the error
 * and returns an error object with a descriptive message and details about the failure:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request could not be configured properly
 */
const searchDomains = async (domainName: string): Promise<Suggestions> => {
  let data = <Suggestions>{};
  try {
    const response = await axios.get(
      `${UNSTOPPABLE_SANDBOX_API_URL}/suggestions/domains?query=${domainName}`, 
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY
        }
      }
    );
    console.log('Suggestions:', response.data);
    data = response.data as Suggestions;
    return data
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```

```typescript registerDomain
import { Order } from './types/orders';

/**
 * Registers a domain with the provided domain ID.
 *
 * This function sends a POST request to the Unstoppable Domains API to register a domain to the default API wallet.
 * On successful registration, it returns the registration details as an `Order` object.
 * If an error occurs, it returns an error object with relevant details.
 *
 * @param {string} domainId - The ID of the domain to register.
 * @returns {Promise<Order>} - A promise that resolves to the `Order` object containing the registration details or an error object.
 *
 * @throws {Error} - If an error occurs, it catches the error and returns an error object with:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request configuration failed
 */
const registerDomain = async (domainId: string): Promise<Order> => {
  let data = <Order>{};
  try {
    const response = await axios.post(
      `${UNSTOPPABLE_SANDBOX_API_URL}/domains?query=${domainId}`,
      JSON.stringify({
        name: domainId,
        records: {}
      }),
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );
    console.log('Domain registered:', response.data);
    data = response.data as Order;
    return data
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```

```typescript checkAvailability
import { Domains } from './types/domains';

/**
 * Checks the availability of a list of domains.
 *
 * This function sends a GET request to the Unstoppable Domains API to check the
 * availability of a given list of domain names. It returns the domain details or an
 * error object if an error occurs.
 *
 * @param {Array<string>} domains - The ID of the operation to check.
 * @returns {Promise<Domains>} - A promise that resolves to an `Operation` object with status details or an error object.
 *
 * @throws {Error} - If an error occurs, it catches the error and returns an error object with:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request configuration failed
 */
const checkAvailability = async (domains: Array<string>): Promise<Domains> => {
  let data = <Domains>{};
  const query = domains.join('&query=');
  try {
    const response = await axios.get(
      `${UNSTOPPABLE_SANDBOX_API_URL}/domains?query=${query}`,
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );
    console.log('Domain Availability:', response.data);
    data = response.data as Domains;
    return data;
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```

We can also take this opportunity to take into account our earlier considerations:
- Partner API Operations 
- Returns
- Transfers

Partner API operation tracking will ideally be handled by [webhooks](https://docs.unstoppabledomains.com/domain-distribution-and-management/guides/implementing-webhooks/) but, as mentioned, this guide will not encompass public hosting. As such, we'll rely on the [operations endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/checkOperation). Similarily, we will use the [returns endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/returnDomain) to handle returning domains and we will use the [overwriting update endpoint](https://docs.unstoppabledomains.com/openapi/partner/#operation/updateDomainPut) to transfer the domain to the end user.

:::info
We'd ideally register a webhook for each Partner API operation we initiate, including a return, registration, transfer, etc. For the purposes of this guide, we can use the `checkOperation()` function as a synchronous polling approach within `trackOperation()`.
:::

```typescript checkOperation
import { Operation } from './types/orders';

/**
 * Checks the status of a domain-related operation.
 *
 * This function sends a GET request to the Unstoppable Domains API to check the
 * status of a given operation by its ID. It returns the operation details or an
 * error object if an error occurs.
 *
 * @param {string} operationId - The ID of the operation to check.
 * @returns {Promise<Operation>} - A promise that resolves to an `Operation` object with status details or an error object.
 *
 * @throws {Error} - If an error occurs, it catches the error and returns an error object with:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request configuration failed
 */
const checkOperation = async (operationId: string): Promise<Operation> => {
  let data = <Operation>{};
  try {
    const response = await axios.get(
      `${UNSTOPPABLE_SANDBOX_API_URL}/operations/${operationId}`,
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );
    console.log('Operation Status:', response.data);
    data = response.data as Operation;
    return data;
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```

```typescript trackOperation
/**
 * Periodically tracks the status of an operation and updates the database.
 *
 * This function polls the Unstoppable Domains API at a set interval to check the
 * status of a specified operation. It stops tracking if the operation completes.
 *
 * @param {string} operationId - The ID of the operation to track.
 */
const trackOperation = async (operationId: string) => {
  const interval = setInterval(async () => {
    const operation = await checkOperation(operationId);
    if (operation.error) {
      console.log('Error:', operation.error);
    } else {
      if (operation.status === "COMPLETED") {
        // Handle completed operation
        clearInterval(interval);
      }
      if (operation.status === "FAILED") {
        // Handle failed operation
        clearInterval(interval);
      }
      // You would want to ensure you're handling other status cases here
    }
  }, 60000); // 1 minute timer
};
```

```typescript returnDomain
import { Return } from './types/returns';

/**
 * Returns a domain to Unstoppable Domains.
 *
 * This function sends a DELETE request to the Unstoppable Domains API to remove
 * the specified domain from the default API wallet and returns it to Unstoppable Domains. 
 * It returns a confirmation or an error object in case of failure. Domains must be returned within 14 days.
 *
 * @param {string} domainId - The ID of the domain to return.
 * @returns {Promise<Return>} - A promise that resolves to a `Return` object with return details or an error object.
 *
 * @throws {Error} - If an error occurs, it catches the error and returns an error object with:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request configuration failed
 */
const returnDomain = async (domainId: string): Promise<Return> => {
  let data = <Return>{};
  try {
    const response = await axios.delete(
      `${UNSTOPPABLE_SANDBOX_API_URL}/domains/${domainId}`,
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );
    data = response.data as Return;
    return data
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```
```typescript transferDomain
import { Transfer } from './types/transfers';

/**
 * Transfers a domain to a specified wallet address.
 *
 * This function sends a PUT request to the Unstoppable Domains API to transfer ownership
 * of the specified domain to the provided wallet address. It returns the transfer details
 * or an error object in case of a failure.
 *
 * @param {string} domainId - The ID of the domain to transfer.
 * @param {string} walletAddress - The wallet address to transfer the domain ownership to.
 * @returns {Promise<Transfer>} - A promise that resolves to a `Transfer` object with transfer details or an error object.
 *
 * @throws {Error} - If an error occurs, it catches the error and returns an error object with:
 *  - "Server error" if the server responded with an error
 *  - "No response received" if there was no response from the server
 *  - "Error setting up request" if the request configuration failed
 */
const transferDomain = async (domainId: string, walletAddress: string): Promise<Transfer> => {
  let data = <Transfer>{};
  try {
    const response = await axios.put(
      `${UNSTOPPABLE_SANDBOX_API_URL}/domains/${domainId}`,
      JSON.stringify({
        name: domainId,
        owner: {
          type: 'EXTERNAL',
          address: walletAddress
        },
        records: {}
      }),
      {
        headers: {
          Authorization: 'Bearer ' + UNSTOPPABLE_SANDBOX_API_KEY,
          'Content-Type': 'application/json'
        }
      }
    );
    data = response.data as Transfer;
    return data
  } catch (error: any) {
    if (error.response) {
      console.error('Server error:', error.response.data);
      data.error = { message: 'Server error', details: error.response.data };
      return data;
    } else if (error.request) {
      console.error('No response received:', error.request);
      data.error = { message: 'No response received', details: error.request };
      return data;
    } else {
      console.error('Error setting up request:', error.message);
      data.error = { message: 'Error setting up request', details: error.message };
      return data;
    }
  }
};
```

We'll want to update our original `/api/register` endpoint with the `trackOperation()` function as registrations are blockchain dependant. We don't need to worry about the `transfer` or `return` functions just yet.

```typescript
app.post('/api/register', async (req: Request, res: Response) => {
  const domainId = req.body.domainId as string;
  try {
    const register = await registerDomain(domainId);
    if (register.error) {
      res.status(500).json(register);
    } else {
      res.json(register);
      trackOperation(register.operation.id);
    }
  } catch (error: any) {
    res.status(500).json({ error: 'Error registering domain', details: error.message });
  }
});
```

### Mock Database 

As the focus of this guide is not databases, we'll be taking advantage of `lowdb` which is a type-safe local JSON database. We'll use these mock databases to store Partner API responses for our orders, transfers, and returns in an easily-digestible format. These responses will be used in conjunction with the `trackOperation()` function to know when we can complete other actions on the domain. Only one operation can be done on a domain at a time so it's important to now when we're able to act on it again. We'll add the below to our `./server/src/server.ts` file.

To start, we'll need to specify the storage directory for the JSON files as well as the default data for the JSON. In this case, we'll be using the `./server/src/data/` directory for the JSON files and will specify `items` as our default data: 

```typescript
import path from 'path';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { JSONFile } from 'lowdb/node';
import { Low } from 'lowdb';
import { Orders } from './types/orders';
import { Transfers } from './types/transfers';
import { Returns } from './types/returns';

// Directory setup for the databases
const __dirname = dirname(fileURLToPath(import.meta.url));

// Default data for databases
const defaultOrderData: Orders = { items: <Order[]>[] }
const defaultTransferData: Transfers = { items: <Transfer[]>[] }
const defaultReturnData: Returns = { items: <Return[]>[] }

// Paths for local JSON databases
const orderDBPath = path.join(__dirname, 'data/orders.json')
const transferDBPath = path.join(__dirname, 'data/transfers.json')
const returnDBPath = path.join(__dirname, 'data/returns.json')
```

From there, we can instantiate and start the databases: 

```typescript
// LowDB instances for each JSON database
const orderDB = new Low(new JSONFile<Orders>(orderDBPath), defaultOrderData);
const transferDB = new Low(new JSONFile<Transfers>(transferDBPath), defaultTransferData);
const returnDB = new Low(new JSONFile<Returns>(returnDBPath), defaultReturnData);

/**
 * Initializes local JSON databases for orders, transfers, and returns.
 * Reads data from the database files and writes default data if none exists.
 */
const initDB = async () => {
  // Initialize Orders database
  await orderDB.read();
  orderDB.data = orderDB.data || defaultOrderData;
  await orderDB.write();

  // Initialize Transfers database
  await transferDB.read();
  transferDB.data = transferDB.data || defaultTransferData;
  await transferDB.write();

  // Initialize Returns database
  await returnDB.read();
  returnDB.data = returnDB.data || defaultReturnData;
  await returnDB.write();
  console.log('Databases initialized');
};

// Initialize the databases on server start
initDB().catch((error) => console.error('Error initializing DB:', error));
```

With the databases initialized, we can update our original `/api/register` endpoint with the JSON `orderDB` accordingly. This will add the Partner API response for each registration to `./server/src/data/orders.json`:

```typescript
app.post('/api/register', async (req: Request, res: Response) => {
  const domainId = req.body.domainId as string;
  try {
    const register = await registerDomain(domainId);
    if (register.error) {
      res.status(500).json(register);
    } else {
      res.json(register);
      await orderDB.update(({ items }) => items.push(register));
      trackOperation(register.operation.id, orderDB);
    }
  } catch (error: any) {
    res.status(500).json({ error: 'Error registering domain', details: error.message });
  }
});
```

Currently, the `trackOperation()` function only sets an interval for synchronously checking an operation ID until it either succeeds or fails. However, we need to utilize this function to keep our `orders.json` file up-to-date. To do this, we'll need a way to check the operation status currently saved in the orders database as well as a way to update it. We can do that with these two functions: 

```typescript
/**
 * Updates an operation in the database with new operation data.
 *
 * Reads the database, searches for an existing operation by its ID, and updates it
 * if found. Writes the updated data back to the database.
 *
 * @param {Operation} operation - The operation data to update in the database.
 * @param {Low<any>} db - The database instance to perform the update.
 * @returns {Promise<void>} - A promise that resolves when the operation is updated.
 */
const updateOperation = async (operation: Operation, db: Low<any>): Promise<void> => {
  await db.read();
  const item = db.data.items.find((item: any) => item.operation.id === operation.id);
  if (item) {
    item.operation = operation;
    await db.write();
  }
};

/**
 * Retrieves the current status of an operation from the database.
 *
 * This function reads the database, searches for an operation by its ID,
 * and returns its status. If the operation is not found, it returns the provided
 * default status.
 *
 * @param {string} operationId - The ID of the operation to retrieve the status for.
 * @param {string} status - The default status to return if the operation is not found.
 * @param {Low<any>} db - The database instance to search.
 * @returns {Promise<string>} - A promise that resolves to the status of the operation.
 */
const getCurrentOperationStatus = async (operationId: string, status: string, db: Low<any>): Promise<string> => {
  await db.read();
  const item = db.data.items.find((item: any) => item.operation.id === operationId);
  if (item) {
    return item.operation.status;
  }
  return status;
};
```

From there, we can update our `trackOperation()` function with database support. Now, it will check if there has been a change in the operation status :

```typescript
const trackOperation = async (operationId: string, db: Low<any>) => {
  const interval = setInterval(async () => {
    const operation = await checkOperation(operationId);
    const status = await getCurrentOperationStatus(operationId, operation.status, db);
    if (operation.error) {
      console.log('Error:', operation.error);
    } else {
      if (operation.status != status) {
        await updateOperation(operation, db);
        if (operation.status === "COMPLETED") {
          // Handle completed operation
          clearInterval(interval);
        }
        if (operation.status === "FAILED") {
          // Handle failed operation
          clearInterval(interval);
        }
        // You would want to ensure you're handling other status cases here
      }
    }
  }, 60000); // 1 minute timer
};
```

One final consideration with `lowdb` is that the database stops running when the `express` server is stopped. As such, it is possible for operations to complete and not be properly tracked. As a workaround, we can call `trackOperation()` when the server starts for any operation in our databases that are neither `COMPLETED` or `FAILED`.

```typescript
/**
 * Initializes tracking for any pending operations in the order, transfer, and return databases.
 * Loads the database data and identifies entries where the `operation.status` is not 'COMPLETED'.
 * For each pending operation, it triggers tracking functions to monitor ongoing processes.
 *
 * @async
 * @function initializeTracking
 * @returns {Promise<void>} - Resolves once all pending operations have been re-tracked.
 */
const initializeTracking = async (): Promise<void> => {
  // Load databases
  await orderDB.read();
  await transferDB.read();
  await returnDB.read();

  // Function to check and track pending operations
  const checkAndTrackPendingOperations = async (db: Low<any>) => {
    // Update according to the appropriate status of the operation
    const pendingItems = db.data?.items?.filter((item: any) => item.operation.status !== 'COMPLETED' && item.operation.status !== 'FAILED') || [];
    for (const item of pendingItems) {
      await trackOperation(item.operation.id, db);
    }
  };

  // Check and track pending operations in each database
  await checkAndTrackPendingOperations(orderDB);
  await checkAndTrackPendingOperations(transferDB);
  await checkAndTrackPendingOperations(returnDB);
  console.log('Pending operations re-tracked');
}

// Call initializeTracking when server starts
initializeTracking().catch((error) => console.error('Error initializing tracking:', error));
```

### Checkout

At this point, we have tied everything together with the exception of these two unused functions: `returnDomain()` and `transferDomain()`. As a reminder, both the `return` and `transfer` functions depend on the status of our frontend checkout. Should checkout succeed, we'll transfer the registered domain to the end user. If checkout fails, we'll return the registered domain to Unstoppable.

While this will be fully dependent on the frontend solution, we'll keep things simple and leverage our `lowdb` databases with a set interval. First, we need a way for the frontend to tell us whether checkout is completed or not and for what order.  

We'll set up a `POST` endpoint on our `express` server that will accept `application/json`. We'll need the domain that was purchased, the operation ID, a `TRUE` / `FALSE` boolean, and the wallet address the domain should be transferred to. The below function will use these parameters to update our `orderDB` with the appropriate data.

```typescript
/**
 * POST /api/checkout/:domain - Processes checkout for a domain by updating the order details.
 *
 * @param {string} domain - The domain ID in the URL path.
 * @body {string} wallet - Wallet address for the domain transfer.
 * @body {boolean} payment - Payment confirmation status.
 * @body {string} operationId - Operation ID associated with the checkout.
 * @returns {Response} - Returns a JSON response indicating order processing status.
 */
app.post('/api/checkout/:domain', async (req: Request, res: Response) => {
  const domain = req.params.domain as string;
  const walletAddress = req.body.wallet as string;
  const payment = req.body.payment as boolean;
  const operationId = req.body.operationId as string;
  try {
    await orderDB.read();
    const order = orderDB.data.items.find(order => order.operation.id === operationId);
    if (order) {
      order.walletAddress = walletAddress;
      order.payment = payment;
      await orderDB.write();
    }
    res.json(`Order for domain ${domain} is being processed`);
  } catch (error: any) {
    res.status(500).json({ error: 'Error processing checkout', details: error.message });
  }
});
```

Next, we'll need a function similar to `trackOperation()` that will track the status of the order checkout against the database. If the registration operation is complete, check if the `payment` boolean is `TRUE` and subsequently check if there is a `wallet address`. Presumably, that will be a successful order. Otherwise, assume failure and return the domain. Depending on the state, we'll use our `returnDomain()` or `transferDomain` functions and their associated databases.

The below does not account for edge cases and is meant as a starting point.

```typescript
/**
 * Monitors the checkout process and handles domain transfer or return based on payment status.
 *
 * This function periodically checks the status of an order associated with the provided domain ID.
 * If the order status is "COMPLETED" and payment is successful, it transfers the domain to the user's
 * wallet address. If payment is unsuccessful, it returns the domain to Unstoppable Domains.
 *
 * @param {string} operationId - The ID of the operation to monitor during checkout.
 */
const trackCheckout = async (operationId: string) => {
  const interval = setInterval(async () => {
    await orderDB.read();
    const order = orderDB.data.items.find(order => order.operation.id === operationId);
    if (order) {
      // Successful checkout
      if (order.operation.status === "COMPLETED" && order.walletAddress && order.payment === true) {
        try {
          const domainTransfer = await transferDomain(order.operation.domain, order.walletAddress);
          if (domainTransfer.error) {
            console.log('Error transferring domain:', domainTransfer.error);
            // Handle failed init transfer
          } else {
            console.log('Domain transferred:', domainTransfer);
            // Handle successful init transfer
            clearInterval(interval);
            await transferDB.update(({ items }) => items.push(domainTransfer));
            trackOperation(domainTransfer.operation.id, transferDB);
          }
        } catch (error: any) {
          console.log('Error transferring domain:', error.message);
        }
      // Usuccessful Checkout
      } else if (order.operation.status === "COMPLETED" && order.payment != true) {
        try {
          const domainReturn = await returnDomain(order.operation.domain);
          if (domainReturn.error) {
            console.log('Error returning domain:', domainReturn.error);
            // Handle failed init return
          } else {
            console.log('Domain returned:', domainReturn);
            // Handle successful init return
            clearInterval(interval);
            await returnDB.update(({ items }) => items.push(domainReturn));
            trackOperation(domainReturn.operation.id, returnDB);
          }
        } catch (error: any) {
          console.log('Error returning domain:', error.message);
        }
      }
      // You would want to ensure you're handling other status cases here
    }
  }, 180000); // 3 minute timer
};
```

Finally, we can update our original `/api/register` endpoint with the `trackCheckout()` function:

```typescript
app.post('/api/register', async (req: Request, res: Response) => {
  const domainId = req.body.domainId as string;
  try {
    const register = await registerDomain(domainId);
    if (register.error) {
      res.status(500).json(register);
    } else {
      res.json(register);
      await orderDB.update(({ items }) => items.push(register));
      trackOperation(register.operation.id, orderDB);
      trackCheckout(register.operation.id);
    }
  } catch (error: any) {
    res.status(500).json({ error: 'Error registering domain', details: error.message });
  }
});
```

At this point, we have a completed backend built with Node and `express`!

## Step 3: Setup Next.js

With our backend completed, it is now time to focus on the frontend. Next.js will serve this purpose throughout the remainder of this guide. While there are many viable alternatives, Next.js provides easy page and API management. 

In this section of the guide, we will creat functions to call our backend, build out an ecommerce cart, checkout and order pages, as well as a general search page. following sections will not focus on CSS or visual improvements but the initial setup script did add `Tailwind CSS` and the [full example](https://github.com/unstoppabledomains/demos/tree/vincent/full-flow/Unstoppable%20Partner%20API%20Example) can be referenced for a CSS outline.

### Environment Variables

Build out your `./client/.env` file per the below. You can retrieve your UAuth Client ID key by following our [Retrieve Client Credentials guide](https://docs.unstoppabledomains.com/identity/quickstart/retrieve-client-credentials/). 

```javascript
NEXT_PUBLIC_API_BASE_URL=http://localhost:3001
NEXT_PUBLIC_CLIENT_ID=1234567890
NEXT_PUBLIC_REDIRECT_URI=http://localhost:3000
NEXT_PUBLIC_SCOPES=openid wallet profile
```

### Express.js API

With our environment variables configured, we can start outlining our backend function calls. Per `Step 2`, we have four exposed endpoints on our `express` server: 
- `POST` to `/api/availability`
- `POST` to `/api/register`
- `GET` to `/api/domains`
- `POST` to `/api/checkout/:domain`

The general outline for each function will be very similar and, with the exception of `/api/domains`, will contain a JSON body. We'll need to call our backend server running on `port 3001` and handle both the expected result and any possible errors. In our `./client/src/app/api` directory, create the following files and add add the outlined example functions.
-  `fetchAvailability.ts`
-  `claimDomain.ts`
-  `fetchSuggestions.ts`
-  `initCheckout.ts`

These four functions will serve as the core of our frontend. 

```typescript fetchAvailability.ts
import axios from 'axios';
import { Domains } from '@/types/domains';

/**
 * Checks the availability of a list of domains.
 *
 * @param {string[]} domains - An array of domain names to check for availability.
 * @returns {Promise<Domains>} - A promise that resolves to a `Domains` object containing availability data for each domain.
 * @throws {Error} - If an error occurs during the request, throws an error with details.
 */
export const fetchAvailability = async (domains: string[]) => {
  try {
    const url = `${process.env.NEXT_PUBLIC_API_BASE_URL}/api/availability`;
    const res = await axios.post(url, 
      {
        domains: domains,
      }
    );

    return res.data as Domains;
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error('Error domain(s) availability: ', err);
    }
  }
}
```

```typescript claimDomain.ts
import axios from 'axios';
import { DomainSuggestion } from '../../types/suggestions';
import { Order } from '@/types/orders';

/**
 * Attempts to claim a specific domain.
 *
 * @param {DomainSuggestion} selectedDomain - The domain to claim, specified by a `DomainSuggestion` object.
 * @returns {Promise<Order>} - A promise that resolves to an `Order` object if the domain is successfully claimed.
 * @throws {Error} - If an error occurs during the request, throws an error with details.
 */
export const claimDomain = async (selectedDomain: DomainSuggestion) => {
  try {
    const url = `${process.env.NEXT_PUBLIC_API_BASE_URL}/api/register`;
    const res = await axios.post(url, 
      {
        domainId: selectedDomain.name,
      }
    );

    return res.data as Order;
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error('Error registering domain(s): ', err);
    }
  }
}
```

```typescript fetchSuggestions.ts
import { Suggestions } from '@/types/suggestions';
import axios from 'axios';

/**
 * Fetches domain suggestions based on a search query.
 *
 * @param {string} query - The search term used to find domain suggestions.
 * @returns {Promise<Suggestions>} - A promise that resolves to a `Suggestions` object containing domain suggestions.
 * @throws {Error} - If an error occurs during the request, throws an error with details.
 */
export const fetchSuggestions = async (query: string) => {
  try {
    const url = `${process.env.NEXT_PUBLIC_API_BASE_URL}/api/domains?query=${query}`;
    const res = await axios.get(url);

    return res.data as Suggestions;
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error('Error fetching domains: ', err);
    }
  }
}
```

```typescript initCheckout.ts
import axios from 'axios';

/**
 * Initializes the checkout process for a specific domain.
 *
 * @param {string} domain - The domain name being checked out.
 * @param {string} walletAddress - The wallet address for the domain transfer.
 * @param {boolean} payment - The payment status; `true` if payment is confirmed.
 * @param {string} operationId - The unique ID for the checkout operation.
 * @returns {Promise<any>} - A promise that resolves to the server response on checkout initiation.
 * @throws {Error} - If an error occurs during the request, throws an error with details.
 */
export const initCheckout = async (domain: string, walletAddress: string, payment: boolean, operationId: string) => {
  try {
    const url = `${process.env.NEXT_PUBLIC_API_BASE_URL}/api/checkout/${domain}`;
    const res = await axios.post(url, 
      {
        wallet: walletAddress,
        payment: payment,
        operationId: operationId,
      }
    );

    return res.data;
  } catch (err: unknown) {
    if (err instanceof Error) {
      throw new Error('Error processing checkout: ', err);
    }
  }
}
```

### Search

In our `./client/src/app/page.tsx` file we'll find our default `Home()` function for our Next.js app. We'll utilize this file for our domain search results. 

To start, lets add the neccessary imports at the very top of the file for the functions we'll be using as well as to declare the file as a Client Component module with `use client`. If `use client` isn't at the very top of your file, you'll run into compilation errors.

```typescript
"use client";
import React, { useState } from 'react';
import { fetchSuggestions } from './api/fetchSuggestions';
import { Suggestions } from '../types/suggestions';
```

From there, we can instantiate the states we'll need within the page at the start of our `Home()` function. This includes our user input for the domain search, the domain search results, any errors, and our pagination information.

```typescript
export default function Home() {
  const [query, setQuery] = useState('');
  const [domains, setDomains] = useState<Suggestions | null>(null);
  const [error, setError] = useState('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [loading, setLoading] = useState(false);
  const domainsPerPage = 5;
  return (
    ...
```

We're now in a place where we can setup our `pagination` and `search` functions as well as handling `user input`. 

As `pagination` will be a standalone function outside of `Home()`, lets start there. The `types` we need for our pagination function are not pre-included with the setup script so lets set those up now. After we close the `Home()` function, add the following interface definitaion and related `Pagination()` function. This function will split the returned list of domain suggestions into equal parts up to a maximum number per page as defined by `domainsPerPage`. There is some `Tailwind CSS` included here to make the button usage easier.

```typescript
interface PaginationProps {
  domainsPerPage: number;
  totalDomains: number;
  paginate: (pageNumber: number) => void;
}

/**
 * Pagination component to render page numbers for navigating through domain results.
 *
 * @param {number} domainsPerPage - Number of domains displayed per page.
 * @param {number} totalDomains - Total number of domain results.
 * @param {function} paginate - Callback function to change the page number.
 * @returns {JSX.Element} Pagination buttons for navigation.
 */
const Pagination: React.FC<PaginationProps> = ({ domainsPerPage, totalDomains, paginate }) => {
  const pageNumbers = [];

  for (let i = 1; i <= Math.ceil(totalDomains / domainsPerPage); i++) {
    pageNumbers.push(i);
  }

  return (
    <nav className="flex justify-center m-[20px]">
      <ul className="flex list-none gap-[10px]">
        {pageNumbers.map(number => (
          <li key={number}>
            <button onClick={() => paginate(number)} className="text-white bg-[#007bff] hover:bg-[#0056b3] font-medium px-[10px] py-[5px] rounded-[4px]">
              {number}
            </button>
          </li>
        ))}
      </ul>
    </nav>
  );
};
```

With the `Pagination()` function now sorted, lets handle the `search` function. We'll add this function within our `Home()` function before the `return`. This will be a simple imeplementation as we'll only need to call our `fetchSuggestions()` function and set the appropriate states like so:

```typescript
/**
   * Fetches domain suggestions based on the current search query.
   * Updates the `domains` state with the response or sets an error message if the fetch fails.
   */
  const searchDomains = async () => {
    try {
      const response = await fetchSuggestions(query);
      setDomains(response!);
      setError('');
      setCurrentPage(1);
    } catch (error) {
      console.error(error);
      setError('Error fetching domains. Please try again.');
    }
  };
```

We'll tie this to our pagination function shortly by doing some preliminary logic:

```typescript
// Calculate indexes for pagination based on current page
  const indexOfLastDomain = currentPage * domainsPerPage;
  const indexOfFirstDomain = indexOfLastDomain - domainsPerPage;
  const currentDomains = domains?.items?.slice(indexOfFirstDomain, indexOfLastDomain);

  /**
   * Sets the current page for pagination.
   * @param {number} pageNumber - The page number to navigate to.
   */
  const paginate = (pageNumber: number) => setCurrentPage(pageNumber);
```

Next, we need to handle user input. An easy way to handle this will be to leverage HTML forms. However, there are some considerations to make here. Notably, Unstoppable domains have limitations on what constitutes a valid domain name. In this guide, we'll handle this validation within our form submission function but it can be handled at any stage throughout the user input. We'll add this function below `searchDomains()`.

```typescript
/**
   * Handles form submission for domain search.
   * Validates user input, resets domain state, and initiates domain search.
   * 
   * @param {React.FormEvent<HTMLFormElement>} event - The form submit event.
   */
  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const inputElement = document.getElementById("search") as HTMLInputElement;
    const inputValue = inputElement.value;
    const isValid = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,22}[a-zA-Z0-9])?$/.test(inputValue);
    
    if (!isValid) {
      setDomains(null);
      setError('Must be 1-24 characters in length, Contain only letters, numbers, or hyphens, and cannot start or end with a hyphen.');
      return;
    }
    setLoading(true);
    try {
      setDomains(null); // Clear previous results
      await searchDomains(); // Fetch new search results
    } catch (error) {
      console.error("Error:", error);
    } finally {
      setLoading(false); // Reset loading state
    }
  }
```

The last step of our search will be the UI. Again, this guide will not focus on CSS but will provide some to get you started. Lets first add our HTML form to our function return. Rename the existing `<main> </main>` tags to `<div> </div>` tags and add the below between them.

```html
<form className="max-w-md mx-auto min-w-[400px] pt-[40px] pb-[30px]" onSubmit={(e: React.FormEvent<HTMLFormElement>) => {handleSubmit(e)}}>   
    <div className="relative text-[1.2em] block w-full bg-[#333] rounded-[8px]">
        <div className="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none ">
            <svg className="w-4 h-4 text-gray-500 dark:text-gray-400" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 20 20">
                <path stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="m19 19-4-4m0-7A7 7 0 1 1 1 8a7 7 0 0 1 14 0Z"/>
            </svg>
        </div>
        <input type="search" id="search" className="block w-full p-4 ps-10 bg-[#333] placeholder-gray-400 text-white rounded-[8px]" placeholder="Search for your new domain" onChange={(e) => setQuery(e.target.value)} required />
        <button type="submit" className="text-white absolute end-2.5 bottom-2.5 bg-[#007bff] hover:bg-[#0056b3] font-medium px-4 py-2 rounded-[4px]">Search</button>
    </div>
    <span className='flex text-gray-500 text-center justify-center mt-2'>Must be 1-24 characters in length, Contain only letters, numbers, or hyphens, and cannot start or end with a hyphen.</span>
</form>
{error && <div className="text-red-500 text-center mb-[20px]">{error}</div>}
```

Below the form, let's add the list of suggested domains: 

```html
<div className="flex flex-col items-center">
  {loading &&
    <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-black" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
    </svg>
  }
  {currentDomains?.map((domain) => (
    <div key={domain.name} className="flex justify-between items-center w-full max-w-[600px] p-[10px] m-[10px] bg-[#333] rounded-[4px]">
      <div>
        <p className="text-[1.2em] text-white">{domain.name}</p>
        <p className="text-[#bbb]">${(domain.price.listPrice.usdCents / 100).toFixed(2)} USD</p>
      </div>
      <button className="text-white text-[1.2em] bg-[#007bff] hover:bg-[#0056b3] font-medium px-4 py-2 rounded-[4px]">Add to Cart</button>
    </div>
  ))}
</div>
```

Finally, lets add our pagination buttons below our search results:

```html
<Pagination
  domainsPerPage={domainsPerPage}
  totalDomains={domains?.items?.length || 0}
  paginate={paginate}
/>
```

You should now have a user-interactible search bar with domain name validation, search results, and search result pagination. Feel free to clean up the default HTML provided by Next.js and to tune the CSS as you see fit!

### Helper Functions

Before we can proceed with the rest of our ecommerce experience, we need to implement a nav bar, a helper function, and add create two contexts: one for authentication, and one for our shopping cart. 

We'll start with our helper function first as the contexts rely on it, and the nav bar relies on the contexts. While we utilized `lowdb` on our `express` server to act as a mock database, we're going to utilize our browsers' local storage to handle our data needs on the frontend. There are several caveats with using local storage exclusively for an ecommerce experience but for the purposes of this guide, it will suffice. We'll create a our `useLocalStorage.ts` fle in `./client/src/app/utils`.

```typescript
import { useCallback, useEffect, useState } from 'react';

/**
 * Custom React hook to manage state with localStorage, syncing updates across browser tabs.
 * Provides a value stored in localStorage and an updater function to modify it.
 *
 * @template T - The type of the state value to be stored.
 * @param {string} storageKey - The localStorage key under which the state is saved.
 * @param {T} fallbackState - The initial value to be used if no item exists in localStorage.
 * @returns {[T, (newValue: T) => void]} - An array containing the current state value and a function to update it.
 */
function useLocalStorage<T>(storageKey: string, fallbackState: T) {
  const isClient = typeof window !== 'undefined';

  const [value, setValue] = useState<T>(() => {
    if (isClient) {
      const storedValue = localStorage.getItem(storageKey);
      return storedValue ? JSON.parse(storedValue) : fallbackState;
    }
    return fallbackState;
  });

  useEffect(() => {
    if (isClient) {
      const storedValue = localStorage.getItem(storageKey);
      setValue(storedValue ? JSON.parse(storedValue) : fallbackState);
    }
  }, [storageKey, isClient]);

  useEffect(() => {
    const handleChanges = (e: StorageEvent) => {
      if (e.key === storageKey) {
        setValue(e.newValue ? JSON.parse(e.newValue) : fallbackState);
      }
    }
    if (isClient) {
      window.addEventListener('storage', handleChanges);
    }
    return () => {
      if (isClient) {
        window.removeEventListener('storage', handleChanges);
      }
    };
  }, [storageKey, fallbackState, isClient]);

  const updateStorage = useCallback(
    (newValue: T) => {
      setValue(newValue)
      if (isClient) {
        localStorage.setItem(storageKey, JSON.stringify(newValue))
      }
    },
    [storageKey, isClient]
  )

  return [value, updateStorage] as const;
};

export default useLocalStorage
```

Next, let's handle the contexts. Contexts are designed to share data across multiple React components such as selected theme, user authentication, preferred language, etc. For our cart context, we'll need functions for:
- Adding an item to the cart
- Removing an item from the cart
- Clearing the cart
- Updating the cart items with backend responses

Create a `CartContext.tsx` file in `./client/src/app/context` and add the following:

```typescript
"use client";
import { DomainSuggestion } from '@/types/suggestions';
import { createContext, useContext, ReactNode } from 'react';
import useLocalStorage from '../utils/useLocalStorage';
import { CartItem } from '@/types/cart';

/**
 * @typedef {Object} CartContextType - Defines the context type for the cart.
 * @property {CartItem[]} cart - Array of items in the cart.
 * @property {(item: DomainSuggestion) => void} addToCart - Function to add a domain suggestion to the cart.
 * @property {(name: string) => void} removeFromCart - Function to remove a domain by name from the cart.
 * @property {(name: string, operationId: string) => void} updateCartItemOperation - Updates the operation ID of a cart item.
 * @property {(name: string, availability: boolean) => void} updateCartItemAvailability - Updates availability status of a cart item.
 * @property {() => void} clearCart - Clears all items from the cart.
 */

interface CartContextType {
  cart: CartItem[];
  addToCart: (item: DomainSuggestion) => void;
  removeFromCart: (name: string) => void;
  updateCartItemOperation: (name: string, operationId: string) => void;
  updateCartItemAvailability: (name: string, availability: boolean) => void;
  clearCart: () => void;
}

/** Context to manage cart state throughout the application */
const CartContext = createContext<CartContextType | undefined>(undefined);

/**
 * CartProvider component to wrap children and provide cart context.
 *
 * @param {Object} props - Props passed to the provider component.
 * @param {ReactNode} props.children - The components that will consume cart context.
 * @returns {JSX.Element} Context provider with cart functionalities.
 */
export const CartProvider = ({ children }: { children: ReactNode }) => {
  const [cart, setCart] = useLocalStorage<CartItem[]>('CART_STORAGE', []);

  /**
   * Adds a new item to the cart if it doesn't already exist.
   * @param {DomainSuggestion} item - The domain suggestion to add.
   */
  const addToCart = (item: DomainSuggestion) => {
    const newItem = { suggestion: item, available: true, operationId: '' };
    const newCart = cart.some(cartItem => cartItem.suggestion.name === newItem.suggestion.name)
    ? cart
    : [...cart, newItem];
    setCart(newCart);
  };

  /**
   * Removes an item from the cart by its domain name.
   * @param {string} name - The name of the domain to remove.
   */
  const removeFromCart = (name: string) => {
    setCart(cart.filter((item: CartItem) => item.suggestion.name !== name));
  };

  /**
   * Updates the operation ID for a specific cart item.
   * @param {string} name - Name of the cart item to update.
   * @param {string} operationId - The new operation ID to set.
   */
  const updateCartItemOperation = (name: string, operationId: string) => {
    const updatedCart = cart.map((item) => 
      item.suggestion.name === name ? { ...item, operationId } : item
    );
    setCart(updatedCart);
  };

  /**
   * Updates the availability status of a specific cart item.
   * @param {string} name - Name of the cart item to update.
   * @param {boolean} available - Availability status to set.
   */
  const updateCartItemAvailability = (name: string, available: boolean) => {
    const updatedCart = cart.map((item) => 
      item.suggestion.name === name ? { ...item, available } : item
    );
    setCart(updatedCart);
  };

  /** Clears all items from the cart. */
  const clearCart = () => setCart([]);

  return (
    <CartContext.Provider value={{ cart, addToCart, removeFromCart, updateCartItemOperation, updateCartItemAvailability, clearCart }}>
      {children}
    </CartContext.Provider>
  );
};

/**
 * Custom hook to use the CartContext.
 * Throws an error if used outside of CartProvider.
 * @returns {CartContextType} The cart context value.
 */
export const useCart = (): CartContextType => {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error("useCart must be used within a CartProvider");
  }
  return context;
};
```

We'll repeat the process above for our auth context. We'll be using Unstoppable Login for our auth provider and will need two functions:
- Login
- Logout

Create a `AuthContext.tsx` file in `./client/src/app/context` and add the following:

```typescript
"use client";
import { createContext, useContext, ReactNode, useState } from 'react';
import useLocalStorage from '../utils/useLocalStorage';
import UAuth from "@uauth/js";
import { Authorization } from '@/types/auth';

/**
 * @typedef {Object} AuthContextType - Defines the context type for authentication.
 * @property {Authorization | null} auth - The current authentication details.
 * @property {boolean} authorizing - Indicates if authentication is in progress.
 * @property {() => void} login - Initiates the login process.
 * @property {() => void} logout - Logs the user out.
 */

interface AuthContextType {
  auth: Authorization | null;
  authorizing: boolean;
  login: () => void;
  logout: () => void;
}

/** Context to manage authentication state throughout the application */
const AuthContext = createContext<AuthContextType | undefined>(undefined);

// UAuth instance for managing user authentication
const uauth = new UAuth({
    clientID: process.env.NEXT_PUBLIC_CLIENT_ID,
    redirectUri: process.env.NEXT_PUBLIC_REDIRECT_URI,
    scopes: process.env.NEXT_PUBLIC_SCOPES
  });

/**
 * AuthProvider component to wrap children and provide authentication context.
 *
 * @param {Object} props - Props passed to the provider component.
 * @param {ReactNode} props.children - The components that will consume auth context.
 * @returns {JSX.Element} Context provider with authentication functionalities.
 */
export const AuthProvider = ({ children }: { children: ReactNode }) => {
  const [auth, setAuth] = useLocalStorage<Authorization | null>('AUTH_STORAGE', null);
  const [authorizing, setAuthorizing] = useState(false);

  /**
   * Initiates the login process with Unstoppable Domains.
   * Sets auth state on successful verification.
   */
  const login = async () => {
    try {
        setAuthorizing(true);
        const authorization = await uauth.loginWithPopup();
        setAuth(authorization || null);
    } catch (error) {
        setAuth(null);
        console.log("Error logging in: " + error);
    } finally {
      setAuthorizing(false);
    }
  };

  /**
   * Logs the user out and clears the auth state.
   */
  const logout = async() => {
    await uauth.logout();
    setAuth(null)
  };

  return (
    <AuthContext.Provider value={{ auth, authorizing, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

/**
 * Custom hook to use the AuthContext.
 * Throws an error if used outside of AuthProvider.
 * @returns {AuthContextType} The auth context value.
 */
export const useAuth = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
};
```

Finally, let's add these contexts to our `layout.tsx` file in `./clinet/src/app` like so:

```typescript
import { CartProvider } from './context/CartContext';
import { AuthProvider } from "./context/AuthContext";
...
return (
  <html lang="en">
    <body className={`antialiased`}>
      <AuthProvider>
        <CartProvider>
          {children}
        </CartProvider>
      </AuthProvider>
    </body>
  </html>
);
```

For the Navbar, we'll need a way for users to login with Unstoppable and to access their cart. As this is mainly CSS, we can jump ahead to the implementation. Add the following to your `NavBar.tsx` file in `./client/src/app/components`: 

```typescript
import Link from 'next/link';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { useEffect, useState } from 'react';

/**
 * Nav component that renders the application header with links to the cart and account information.
 * Displays a loading spinner during client-side hydration.
 *
 * @returns {JSX.Element} The header and navigation elements of the application.
 */
const Nav = () => {
  const { cart } = useCart();
  const { auth, authorizing, login, logout } = useAuth();
  const [isClient, setIsClient] = useState(false); // Tracks client-side rendering status

  /**
   * Initiates the login process for wallet connection.
   */
  const connectWallet = () => {
    try {
      login();
    } catch (error) {
      console.error("Error:", error);
    }
  };

  /**
   * Initiates the logout process to disconnect the wallet.
   */
  const disconnectWallet = () => {
    try {
      logout();
    } catch (error) {
      console.error("Error:", error);
    }
  };

  useEffect(() => {
    setIsClient(true); // Set to true once the component has mounted client-side
  }, []);

  // If rendering server-side, display loading state to avoid flash of unhydrated content.
  if (!isClient) {
    return (
      <header className="bg-[#007bff] p-[20px] text-white text-[2em] text-center rounded-[4px] font-helveticaneue flex justify-between items-center">
        <h1>
          <Link href="/">Unstoppable Domains Partner API Example</Link>
        </h1>
        <nav className="flex flex-row space-x-4 font-inter text-lg">
        <div className='h-5 w-5 m-auto'>
          <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          </div>
      </nav>
      </header>
    );
  }

  return (
    <header className="bg-[#007bff] p-[20px] text-white text-[2em] text-center rounded-[4px] font-helveticaneue flex justify-between items-center">
      <h1>
        <Link href="/">Unstoppable Domains Partner API Example</Link>
      </h1>
      <nav className="flex flex-row space-x-4 font-inter text-lg">
        <Link href="/cart" className='flex flex-row m-auto h-10 w-150'>
          <div className='h-5 w-5 m-auto'>
            <svg className=" items-center justify-center" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M3 3H5L5.4 5M7 13H17L21 5H5.4M7 13L5.4 5M7 13L4.70711 15.2929C4.07714 15.9229 4.52331 17 5.41421 17H17M17 17C15.8954 17 15 17.8954 15 19C15 20.1046 15.8954 21 17 21C18.1046 21 19 20.1046 19 19C19 17.8954 18.1046 17 17 17ZM9 19C9 20.1046 8.10457 21 7 21C5.89543 21 5 20.1046 5 19C5 17.8954 5.89543 17 7 17C8.10457 17 9 17.8954 9 19Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
          </div>
          <div className='h-auto m-auto pl-1 font-inter'>
            <span>Cart ({cart.length})</span>
          </div>
        </Link>
        {auth ? 
          <button type="button" onClick={() => disconnectWallet()} className="flex flex-row m-auto h-10 w-150">
            <div className='h-5 w-5 m-auto'>
              <svg className="items-center justify-center" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                <path d="M7 17v1a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-1a3 3 0 0 0-3-3h-4a3 3 0 0 0-3 3Zm8-9a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>     
            </div>
            <div className='h-auto m-auto pl-1 font-inter'>
              <span>{auth.idToken.sub}</span>
            </div>
          </button>
        : <button type="button" onClick={() => connectWallet()} className="flex flex-row m-auto h-10 w-150">
            
            <div className='h-5 w-5 m-auto'>
              {authorizing ?
                <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              : <svg className="items-center justify-center" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                  <path d="M7 17v1a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-1a3 3 0 0 0-3-3h-4a3 3 0 0 0-3 3Zm8-9a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              }
            </div>
            <div className='h-auto m-auto pl-1 font-inter'>
              <span>Account</span>
            </div>
          </button>
        }
      </nav>
    </header>
  );
};

export default Nav;
```

Finally, lets add our Navbar and cart context to our search HTML:

```typescript
import Nav from './components/NavBar';
import { useCart } from './context/CartContext';
...
const [currentPage, setCurrentPage] = useState<number>(1);
const [loading, setLoading] = useState(false);
const { cart, addToCart, removeFromCart } = useCart();
const domainsPerPage = 5;
...
return (
<div>
  <Nav />
  ...
  <div className="flex flex-col items-center">
    ...
    {currentDomains?.map((domain) => (
      <div key={domain.name} className="flex justify-between items-center w-full max-w-[600px] p-[10px] m-[10px] bg-[#333] rounded-[4px]">
        <div>
          <p className="text-[1.2em] text-white">{domain.name}</p>
          <p className="text-[#bbb]">${(domain.price.listPrice.usdCents / 100).toFixed(2)} USD</p>
        </div>
        {cart.some(cartItem => cartItem.suggestion.name === domain.name)
          ? <button onClick={() => removeFromCart(domain.name)} className="text-[#49a668] text-[1.2em] bg-[#edf7f4] font-medium px-4 py-2 rounded-[4px]">Added</button>
          : <button onClick={() => addToCart(domain)} className="text-white text-[1.2em] bg-[#007bff] hover:bg-[#0056b3] font-medium px-4 py-2 rounded-[4px]">Add to Cart</button>
        }
      </div>
    ))}
  </div>
  ...
```

At this stage, we have a completed homepage that includes a search bar for Unstoppable domains, a way for users to add and remove those items from their shopping cart, and a way for user to login to our site. We now need to build the cart and checkout flow.

### Cart

We'll need to add a dedicated `/cart` route on our frontend to act as our ecommerce shopping cart. To start, create a `page.tsx` file in the `./client/src/app/cart` directory. Let's take care of the necessary imports as well as the component outline: we'll calculate the total dollar value of our card in USD, define a function for Unstoppable login, and add a rough return function.

```typescript
"use client";
import Link from 'next/link';
import Nav from '../components/NavBar';
import { claimDomain } from '../api/claimDomain';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useCart } from '../context/CartContext';
import { useAuth } from '../context/AuthContext';
import { fetchAvailability } from '../api/fetchAvailability';

const Cart = () => {
  const { cart, removeFromCart, updateCartItemOperation, updateCartItemAvailability, clearCart } = useCart();
  const { auth, login } = useAuth();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const [isClient, setIsClient] = useState(false);
  const [allAvailable, setAllAvailable] = useState(false);
  const [availabilityLoading, setAvailabilityLoading] = useState(false);

  // Calculate total price of items in the cart
  let total = 0;
  cart.forEach((item) => {
    total += item.suggestion.price.listPrice.usdCents;
  });

  /**
   * Initiates the login process for wallet connection.
   */
  const connectWallet = () => {
    try {
      login();
    } catch (error) {
      console.error("Error:", error);
    }
  }

  // Early return to avoid server-side rendering issues
  if (!isClient) {
    return (
      <section>
        <Nav />
      </section>
    );
  }

  return (
    <section>
      <Nav />
      <div>
      </div>
    </section>
  )
};

export default Cart;
```

The `Cart()` function will be one of the larger components we'll need to build out. The reason for this is this function will be responsible for both checking the availability of the domains added to the cart as well as registering those domains once checkout is initiated. 

We need to check availability because it is possible that user b will purchase a domain in user a's cart. In a similar vein, as soon as user a proceeds from the cart to checkout, we'll register the domains to our API key. This ensures the domains are not available for any other user to claim; avoiding issues of user a purchasing a domain that is no longer available. As we're already handling returns on our backend, we won't need to worry about the user not completing the checkout.

For availability checks, we can periodically check domains in the cart are available with a simple interval, and we'll need to check immedietly before registering the domains. Below is an 1 minute interval that starts when the user accesses the `/cart` route as well as the necessary availability function that will use our `fetchAvailability()` endpoint.

```typescript
/**
   * Sets client-side flag and periodically checks domain availability in the cart every minute.
   */
  useEffect(() => {
    setIsClient(true);
    // Reset cart oparationId on load
    cart.forEach((item) => {
      updateCartItemOperation(item.suggestion.name, '');
    });
    // Check if all cart items are available on load
    setAllAvailable(cart.every(item => item.available ?? false));
    // Periodic check every 60 seconds for domain availability in the cart
    const interval = setInterval(() => {
      setAvailabilityLoading(true);
      checkCartAvailability(); // Check the cart availability on interval
      setAvailabilityLoading(false);
    }, 60000);

    return () => clearInterval(interval); // Cleanup on component unmount
  }, []);

  /**
   * Checks the availability of all domains in the cart.
   * It updates the cart items' availability status based on the API response.
   *
   * @returns {Promise<boolean>} - Returns a boolean indicating if all items in the cart are available.
   */
  const checkCartAvailability = async (): Promise<boolean> => {
    try {
      setError('');
      const domains: string[] = cart.map(item => item.suggestion.name); // Collect domain names from the cart
      if (domains.length > 0) {
        interface Status {
          name: string;
          available: boolean;
        }
        const statuses: Status[] = [];
        // Call external availability check function
        const availability = await fetchAvailability(domains);
        // Update each cart item’s availability based on the API response
        if (availability?.items) {
          for (const item of availability?.items) {
            const cartItem = cart.find((cartItem) => cartItem.suggestion.name === item.name);
            if (cartItem) {
              if (item.availability.status === "AVAILABLE") {
                updateCartItemAvailability(item.name, true)
                statuses.push({ name: item.name, available: true })
              } else {
                updateCartItemAvailability(item.name, false)
                statuses.push({ name: item.name, available: false })
              }
            }
          }
        }
        // Handle error when item availability is missing
        // Check if all cart items are available
        setAllAvailable(cart.every(item => item.available ?? false));
        // Return true if all items are available, otherwise false
        return statuses.every(item => item.available ?? false);
      }
      return false; // Return false if there are no items in the cart
    } catch (error) {
      console.log('Error checking domain availability:', error);
      setError('An unexpected error occurred. Please try again.');
      return false;
    }
  };
```

Similarily, we can create our domain registration function that uses the `claimDomain()` endpoint. As mentioned, we'll check domain availability first before attempting to regiser the domain to the API key.

```typescript
/**
   * Registers the domains in the cart by first checking their availability and then attempting to claim each domain.
   * If any domain is unavailable or an error occurs during the registration, an error message is displayed.
   *
   * @returns {Promise<boolean>} - Returns a boolean indicating if the domain registration was successful.
   */
  const registerDomain = async (): Promise<boolean> => {
    try {
        setError('');
        setAvailabilityLoading(true);
        const available = await checkCartAvailability(); // Check availability of all domains in the cart
        setAvailabilityLoading(false);
        // Display error message if any domain is unavailable
        if (!available) {
          setError('One or more items in your cart are no longer available. Please remove them before proceeding.');
          return false;
        }
        // Attempt to claim each domain in the cart
        for (const item of cart) {
          try {
            const claim = await claimDomain(item.suggestion); // Attempt to claim the domain
            if (claim?.operation?.id) {
              updateCartItemOperation(item.suggestion.name, claim?.operation.id); // Update operation ID for the item based on claim response
            }
            // Handle any errors when ID is missing
          } catch (error) {
            console.log(`Error registering ${item.suggestion.name}:`, error);
            setError(`An unexpected error occurred while claiming ${item.suggestion.name}.`);
            return false;
          }
        };
        return true; // Return true if all domains are successfully claimed
    } catch (error) {
      console.log('Error registering domains:', error);
      setError('An unexpected error occurred. Please try again.');
      return false;
    }
  };
```

Then, much like our search bar on our homepage, we'll leverage HTML forms for user itneractivity and, as such, we need a function to handle `HTMLFormElement` events:

```typescript
/**
   * Handles the form submission for checkout. It triggers the checkout process
   * and navigates to the checkout page upon success.
   * 
   * @param {React.FormEvent<HTMLFormElement>} event - The form submission event.
   */
  const handleCheckout = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    let success = false;
    try {
      success = await registerDomain();
    } catch (error) {
      console.log("Error:", error);
    } finally {
      setLoading(false);
      if (success) {
        router.push('/checkout');
      }
    }
  }
```

We now have all of the functions we need added to our page and we can turn our focus to the HTML and CSS. Below is a rough starting point that you're encouraged to fine-tune to your liking! In general, we need a list of all the domain in the cart, show a total value, and provide typical UI for clearing the cart and removing individual items. To callback to our backend `express` server, we also need the users' wallet address to transfer the domain to upon successful purchase, we'll also add that to our HTML.

```typescript
return (
  <section>
    <Nav />
    <div className="mx-auto max-w-screen-xl px-4 2xl:px-0 pt-5">
      <div className="mt-6 sm:mt-8 md:gap-6 lg:flex lg:items-start xl:gap-8">
        {cart.length === 0 ? (
          <p className="text-center text-lg text-gray-500 dark:text-gray-400 mt-10 mx-auto">
            Your cart is empty.
          </p>
        ) : (
          <div>
            {cart.map((item) => (
              <div key={item.suggestion.name} className="pb-5">
                <div>
                  <div className="rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-700 dark:bg-gray-800 md:p-6">
                    <div className="space-y-4 md:flex md:items-center md:justify-between md:gap-6 md:space-y-0">
                      <svg className="h-20 w-20" focusable="false" aria-hidden="true" viewBox="0 0 40 40">
                        <path d="M38.3333 3.90803V16.5517L1.66666 31.4942L38.3333 3.90803Z" fill="#00C9FF"></path><path d="M31.4583 3.33333V25.1724C31.4583 31.5203 26.3281 36.6667 20 36.6667C13.6719 36.6667 8.54166 31.5203 8.54166 25.1724V15.977L15.4167 12.1839V25.1724C15.4167 26.2394 15.8392 27.2626 16.5913 28.0171C17.3434 28.7716 18.3635 29.1954 19.4271 29.1954C20.4907 29.1954 21.5108 28.7716 22.2629 28.0171C23.015 27.2626 23.4375 26.2394 23.4375 25.1724V7.75862L31.4583 3.33333Z" fill="#0D67FE"></path>
                      </svg>
                      <div className="flex items-center justify-between md:order-3 md:justify-end">
                        <div className="text-end md:order-4 md:w-32">
                          <p className="text-base font-bold text-gray-900 dark:text-white">${(item.suggestion.price.listPrice.usdCents / 100).toFixed(2)} USD</p>
                        </div>
                      </div>
    
                      <div className="flex flex-col w-full min-w-0 flex-1 space-y-4 md:order-2 md:max-w-md">
                        <span className="text-base font-medium text-gray-900 dark:text-white">{item.suggestion.name}</span>
                        {availabilityLoading &&
                          <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                          </svg>
                        }
                        {!availabilityLoading && !item.available && <span className="text-xs font-medium text-red-600 dark:text-red-500">Domain is no longer available</span>}
                        {!availabilityLoading && item.available && <span className="text-xs font-medium text-green-600 dark:text-green-500">Domain is available</span>}
                        <div className="flex items-center gap-4">
                          <button type="button" className="inline-flex items-center text-sm font-medium text-red-600 hover:underline dark:text-red-500" onClick={() => removeFromCart(item.suggestion.name)}>
                            <svg className="me-1.5 h-5 w-5" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" viewBox="0 0 24 24">
                              <path stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18 17.94 6M18 18 6.06 6" />
                            </svg>
                            Remove
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            ))}
            <Link href='/cart' onClick={() => clearCart()} className='flex flex-row font-medium text-gray-500 max-w-[120px] max-h-[20px]'>
              <div className='h-auto'>
                <span>Clear Cart</span>
              </div>
            </Link>
          </div>
        )}
        {cart.length > 0 &&
          <div className="mx-auto mt-6 max-w-4xl flex-1 space-y-6 lg:mt-0 lg:w-[25%]">
            <div className="space-y-4 rounded-[8px] border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-700 dark:bg-gray-800 sm:p-6">
              <p className="text-xl font-semibold text-gray-900 dark:text-white">Order summary</p>

              <div className="space-y-4">
                <dl className="flex items-center justify-between gap-4 border-t border-gray-200 pt-2 dark:border-gray-700">
                  <dt className="text-base font-bold text-gray-900 dark:text-white">Total</dt>
                  <dd className="text-base font-bold text-gray-900 dark:text-white">${((total) / 100).toFixed(2)} USD</dd>
                </dl>
              </div>

              <form onSubmit={handleCheckout}>
              { (auth && allAvailable) ? 
                <button type="submit" className="flex mx-auto w-[50%] md:w-[40%] items-center justify-center rounded-lg bg-[#007bff] px-5 py-2.5 text-sm font-medium text-white hover:bg-primary-800 focus:outline-none focus:ring-4 focus:ring-primary-300 dark:bg-primary-600 dark:hover:bg-primary-700 dark:focus:ring-primary-800">
                  {loading &&
                    <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                  }
                  Proceed to Checkout
                </button>
              : <div className="flex mx-auto w-[50%] md:w-[40%] items-center cursor-not-allowed justify-center rounded-lg bg-[#007bff] px-5 py-2.5 text-sm font-medium text-white hover:bg-primary-800 focus:outline-none focus:ring-4 focus:ring-primary-300 dark:bg-primary-600 dark:hover:bg-primary-700 dark:focus:ring-primary-800">
                  Proceed to Checkout
                </div>
              }
              </form>
              {error && <div className="text-red-500 text-center mb-[20px]">{error}</div>}
              <div className="flex items-center justify-center gap-2">
                <span className="text-sm font-normal text-gray-500 dark:text-gray-400"> or </span>
                <Link href='/' className="inline-flex items-center gap-2 text-sm font-medium underline hover:no-underline text-[#007bff]">
                  Continue Shopping
                </Link>
              </div>
              { auth ? 
                <p className="text-sm font-normal text-gray-500 dark:text-gray-400 text-center">
                  Connected Wallet Address:&nbsp;
                  <span className="items-center gap-2 text-sm font-medium text-[#007bff]">
                    {auth?.idToken?.sub}&nbsp;
                    <span className="text-xs text-gray-500 dark:text-gray-400">
                      ({auth?.idToken?.wallet_address})
                    </span> 
                  </span>
                </p>
              : <p className="text-sm font-normal text-gray-500 dark:text-gray-400 text-center">
                  One or more items in your cart require a wallet connection.&nbsp;
                  <button onClick={() => connectWallet()} title="" className="font-medium text-primary-700 underline hover:no-underline dark:text-primary-500">
                    Connect your wallet now.
                  </button>
                </p>
              }
            </div>
          </div>
        }
      </div>
    </div>
  </section>
);
```

We've now completed bulding out our cart! You'll be able to search for domains on the homepage, add those domains to the cart, and view our new cart page.

### Checkout

We'll need to add a dedicated `/checkout` route on our frontend to act as our payment gateway. As a reminder, the Partner API does not handle payments. It is up to the partner to integrate a payment gateway of their choice and to charge the end user in whatever fiat / crypto they so choose. Note that Unstoppable Domains will invoice the partner based on the API price. 

To start, create a `page.tsx` file in the `./client/src/app/checkout` directory. Let's take care of the necessary imports as well as the component outline: we'll add minimal logic to redirect the user away from the `/checkout` page if they shouldn't be there, calculate total cart value, and add our return.

:::info
Partners can use any payment gateway and collect payment in any fiat / crypto they prefer. Partners are also free to set their own pricing however Unstoppable will invoice based on the API returned cost of the domain.
:::

```typescript
"use client";
import { useCart } from '../context/CartContext';
import Nav from '../components/NavBar';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '../context/AuthContext';
import { initCheckout } from '../api/initCheckout';
import Link from 'next/link';
import useLocalStorage from '../utils/useLocalStorage';

/**
 * Checkout component manages the checkout process, including the countdown timer, domain transfer,
 * and final checkout submission. It checks if the cart has items and if the user is authenticated 
 * before proceeding. The user has a two-minute window to complete the checkout process.
 * 
 * @component
 */
const Checkout = () => {
  const { cart } = useCart();
  const { auth } = useAuth();
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const router = useRouter();
  const [isClient, setIsClient] = useState(false);
  const [expired, setExpired] = useState(false);
  const [timeLeft, setTimeLeft] = useState<number>(0);
  const [startTime, setStartTime] = useLocalStorage<number | null>('CHECKOUT_TIME', null);
  const countdownTime = 120;

  /**
   * Redirects the user to the cart page if the cart is empty, invalid, or the user is not authenticated.
   */
  useEffect(() => {
    if (cart.length === 0 || !auth) {
      router.push('/cart');
    } else if (cart.some(item => item.operationId === '')) {
      router.push('/cart');
    }
  }, [cart, auth, router]);

  /**
   * Ensures the component is only rendered on the client side.
   */
  useEffect(() => {
    setIsClient(true);
  }, []);

  // Calculate total price of items in the cart
  let total = 0;
  cart.forEach((item) => {
    total += item.suggestion.price.listPrice.usdCents;
  });

  // Early return to avoid server-side rendering issues
  if (!isClient) {
    return (
      <section>
        <Nav />
      </section>
    );
  }

  return (
    <section>
      <Nav />
      <div>
      </div>
    </section>
  )
};

export default Checkout;
```

The `Checkout()` function will be resposible for using our last `initCheckout()` endpoint we defined earlier. It's important to note here that this guide will not encompass integration of a payment gateway. Instead, we will leverage HTML forms and no data will be stored. 

On our backend, we assumed a three (3) minute timer for our checkout flow on whether payment has succeeded or failed. So, we will start by implementing a similar timer on the frontend. Ideally, this will be a shorter time-frame than our backend expects to allow for some buffer. We'll get the current time, calculate the remaining time, and format the time from seconds back into a user-digestible format. Keep in mind that official payment gateways may already have a timout that would make this function redundant.


```typescript
/**
 * Calculates the remaining time on the countdown timer.
 */
useEffect(() => {
  const currentTime = Math.floor(Date.now() / 1000); // Get current timestamp in seconds
  if (startTime) {
    const elapsedTime = currentTime - startTime;
    const remainingTime = countdownTime - elapsedTime;
    // If time expired, stop the checkout process
    if (remainingTime <= 0) {
      setExpired(true);
      setTimeLeft(0);
      setStartTime(null);
      return;
    }
    // Otherwise, update the time left
    setTimeLeft(remainingTime);
  } else {
    // If no start time, initialize the countdown
    setStartTime(currentTime);
    setTimeLeft(countdownTime);
    setExpired(false);
  }
  /**
   * Interval to update the countdown timer every second.
   */
  const interval = setInterval(() => {
    setTimeLeft((prevTime) => {
      if (prevTime <= 0) {
        clearInterval(interval);
        setExpired(true);
        setStartTime(null);
        return 0;
      }
      return prevTime - 1;
    });
  }, 1000);
  // Cleanup the interval on component unmount or when countdown is finished
  return () => clearInterval(interval);
}, []);

/**
 * Helper function to format remaining time into minutes and seconds.
 * @param {number} seconds - The time in seconds to format.
 * @returns {string} - Formatted time string in 'minutes:seconds' format.
 */
const formatTime = (seconds: number): string => {
  const minutes = Math.floor(seconds / 60);
  const secs = seconds % 60;
  return `${minutes}:${secs < 10 ? '0' : ''}${secs}`;
};
```

Now we can create our checkout function that uses the `initCheckout()` endpoint. We'll ensure we have the users' wallet address for the domain transfer as well as the registration operation ID and handle any errors appropriately.

```typescript
/**
   * Executes the checkout process for each item in the cart.
   * It tries to process each domain in the cart and queues the transfer using initCheckout.
   * If any error occurs during the transfer, an error message is set and the process stops.
   * 
   * @returns {Promise<boolean>} - Returns a boolean indicating if the checkout was successful.
   */
  const checkout = async (): Promise<boolean> => {
    try {
      setError('');
      for (const item of cart) {
        try {
            if (auth?.idToken.wallet_address && item.operationId) {
              await initCheckout(item.suggestion.name, auth?.idToken.wallet_address, true, item.operationId);
            }
            // Handle any errors when wallet_address and operation ID are missing
          } catch (error) {
            console.error(`Error processing ${item.suggestion.name}:`, error);
            setError(`An unexpected error occurred while processing ${item.suggestion.name}.`);
            return false; // If an error occurs for a domain, return false to halt checkout
          }
      };
      return true; // Return true if all domains are successfully processed
    } catch (error) {
      console.error('Error processing domains:', error);
      setError('An unexpected error occurred. Please try again.');
      return false; // Return false if there's an issue with the overall checkout
    }
  };
```

Then, much like our search bar on our homepage, we'll leverage HTML forms for user itneractivity and, as such, we need a function to handle `HTMLFormElement` events:

```typescript
/**
   * Handles the form submission for checkout. It triggers the checkout process
   * and navigates to the order page upon success.
   * 
   * @param {React.FormEvent<HTMLFormElement>} event - The form submission event.
   */
  const handleCheckout = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true); // Set loading state to true during checkout process
    let success = false;
    try {
      success = await checkout(); // Attempt to process checkout
    } catch (error) {
      console.error("Error:", error);
    } finally {
      setLoading(false); // Reset loading state after checkout process
      if (success) {
        router.push('/order'); // Navigate to order page upon successful checkout
      }
    }
  }
```

We now have all of the functions we need added to our page and we can turn our focus to the HTML and CSS. Below is a rough starting point that you're encouraged to fine-tune to your liking! In general, we need to display the form for our chosen payment gateway as well as the total the user will be charged. We should also display the wallet address the domain will be transferred to along with the checkout timer.

```typescript
return (
  <section>
    <Nav />
    <div className="mx-auto max-w-screen-xl px-4 2xl:px-0 pt-5">
      <div>
        <div className="mt-6 sm:mt-8 lg:flex lg:items-start lg:gap-12">
        <form onSubmit={handleCheckout} action="/order" className="w-full rounded-lg border border-gray-200 bg-white p-4 shadow-sm dark:border-gray-700 dark:bg-gray-800 sm:p-6 lg:max-w-xl lg:p-8">
            <div className="mb-6 grid grid-cols-2 gap-4">
            <div className="col-span-2 sm:col-span-1">
                <label htmlFor="full_name" className="mb-2 block text-sm font-medium text-gray-900 dark:text-white"> Full name (as displayed on card)* </label>
                <input type="text" id="full_name" className="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-primary-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:focus:border-primary-500 dark:focus:ring-primary-500" placeholder="Partner Engineering" required />
            </div>

            <div className="col-span-2 sm:col-span-1">
                <label htmlFor="card-number-input" className="mb-2 block text-sm font-medium text-gray-900 dark:text-white"> Card number* </label>
                <input type="text" id="card-number-input" className="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 pe-10 text-sm text-gray-900 focus:border-primary-500 focus:ring-primary-500  dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:focus:border-primary-500 dark:focus:ring-primary-500" placeholder="4242424242424242" pattern="^4[0-9]{12}(?:[0-9]{3})?$" required />
            </div>

            <div>
                <label htmlFor="card-expiration-input" className="mb-2 flex items-center gap-1 text-sm font-medium text-gray-900 dark:text-white">Card expiration* </label>
                <input id="card-expiration-input" type="text" className="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-primary-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:focus:border-primary-500 dark:focus:ring-primary-500" placeholder="1234" required />
            </div>

            <div>
                <label htmlFor="cvv-input" className="mb-2 flex items-center gap-1 text-sm font-medium text-gray-900 dark:text-white">CVV*</label>
                <input type="number" id="cvv-input" className="block w-full rounded-lg border border-gray-300 bg-gray-50 p-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-primary-500 dark:border-gray-600 dark:bg-gray-700 dark:text-white dark:placeholder:text-gray-400 dark:focus:border-primary-500 dark:focus:ring-primary-500" placeholder="567" required />
            </div>
            </div>

            <button type="submit" className="flex w-full items-center justify-center rounded-lg bg-[#007bff] px-5 py-2.5 text-sm font-medium text-white focus:outline-none focus:ring-4" disabled={expired}>
            {loading &&
                <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
            }
            {expired ? 'Checkout expired' : 'Pay now'}
            </button>
            {error && <div className="text-red-500 text-center mb-[20px]">{error}</div>}
            {expired ?
            <div className="flex items-center justify-center gap-2 mt-6">
                <Link href='/cart' className="inline-flex items-center gap-2 text-sm font-medium underline hover:no-underline text-[#007bff]">
                Return to Cart
                <svg className="h-5 w-5" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <path stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 12H5m14 0-4 4m4-4-4-4" />
                </svg>
                </Link>
            </div>
            : 
            <div className="mt-6 mx-auto text-center text-gray-500 dark:text-gray-400">Checkout time remaining: {formatTime(timeLeft)}</div>
            }
        </form>

        <div className="mt-6 grow sm:mt-8 lg:mt-0">
            <div className="space-y-4">
            <dl className="flex items-center justify-between gap-4 border-t border-gray-200 pt-2 dark:border-gray-700">
                <dt className="text-base font-bold text-gray-400">Total</dt>
                <dd className="text-base font-bold text-gray-400">${((total) / 100).toFixed(2)} USD</dd>
            </dl>
            </div>
        </div>
        </div>
        { auth && 
        <p className="mt-3 text-sm font-normal text-gray-500 dark:text-gray-400 text-center mx-auto lg:text-left">
            Domain will transfer after checkout to Wallet Address:&nbsp;
            <span className="gap-2 text-sm font-medium text-[#007bff]">
            {auth?.idToken?.sub}&nbsp;
            <span className="text-xs text-gray-500 dark:text-gray-400">
                ({auth?.idToken?.wallet_address})
            </span> 
            </span>
        </p>
        }
      </div>
    </div>
  </section>
);
```

### Orders

Finally, we can create our order, or confirmation, page. Here we'll simply outline the details of the domain registration and transfer. This will be mainly CSS and HTML but we'll ensure we empty the cart context and redirect the user if they shouldn't be on the page yet. To start, create a `page.tsx` file in the `./client/src/app/order` directory.

```typescript
"use client";
import { useCart } from '../context/CartContext';
import Link from 'next/link';
import Nav from '../components/NavBar';
import { useAuth } from '../context/AuthContext';
import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';

/**
 * Order confirmation page component.
 * 
 * This component displays an order summary with a thank-you message. 
 * If the user is not authenticated or has an empty cart, it redirects them to the cart page.
 * 
 * @component
 */
const Order = () => {
  const { cart, clearCart } = useCart();
  const { auth } = useAuth();
  const router = useRouter();
  const [isClient, setIsClient] = useState(false);

  /**
   * Redirects the user to the cart page if the cart is empty, invalid, or the user is not authenticated.
   */
  useEffect(() => {
    if (cart.length === 0 || !auth) {
      router.push('/cart');
    } else if (cart.some(item => item.operationId === '')) {
      router.push('/cart');
    }
  }, [cart, auth, router]);

  /**
   * Ensures the component is only rendered on the client side.
   */
  useEffect(() => {
    setIsClient(true);
  }, []);

  // Early return to avoid server-side rendering issues
  if (!isClient) {
    return (
      <section>
        <Nav />
      </section>
    );
  }

  return (
    <section>
      <Nav />
      <div>
      </div>
    </section>
  );
};

export default Order;
```

Then we can add the HTML to our return:

```typescript
return (
    <section>
      <Nav />
      <div className="mx-auto max-w-screen-xl px-4 2xl:px-0 pt-5">
        <h2 className="mt-6 text-xl font-semibold text-gray-400 sm:text-2xl mb-2">Thanks for your order!</h2>
        <p className="text-gray-500 dark:text-gray-400 mb-6 md:mb-8">Your order <a href="#" className="font-medium text-gray-400 hover:underline">#{Math.floor(100000 + Math.random() * 900000)}</a> will be processed within a few minutes. Keep an eye on your wallet for the domain.</p>
        <div className="w-[75%] space-y-4 sm:space-y-2 rounded-lg border border-gray-100 bg-gray-50 p-6 dark:border-gray-700 dark:bg-gray-800 mb-6 md:mb-8">
          <dl className="sm:flex items-center justify-between gap-4">
            <dt className="font-normal mb-1 sm:mb-0 text-gray-500 dark:text-gray-400">Date</dt>
            <dd className="font-medium text-gray-900 dark:text-white sm:text-end">{new Date().toLocaleString()}</dd>
          </dl>
          <dl className="sm:flex items-center justify-between gap-4">
            <dt className="font-normal mb-1 sm:mb-0 text-gray-500 dark:text-gray-400">Payment Method</dt>
            <dd className="font-medium text-gray-900 dark:text-white sm:text-end">Credit Card</dd>
          </dl>
          <dl className="sm:flex items-center justify-between gap-4">
            <dt className="font-normal mb-1 sm:mb-0 text-gray-500 dark:text-gray-400">Minting Wallet</dt>
            <dd className="font-medium text-gray-900 dark:text-white sm:text-end">{auth?.idToken?.sub}</dd>
          </dl>
        </div>
        <div className="flex items-center space-x-4">
          <Link href='/' onClick={() => clearCart()} className="flex flex-row gap-2 items-center justify-center rounded-lg bg-[#007bff] px-5 py-2.5 text-sm font-medium text-white focus:outline-none focus:ring-4">
            Return to shopping
          </Link>
        </div>
      </div>
    </section>
  );
```

That's it! You are now running a local ecommerce platform for selling Unstoppable domains. 

## Recap

As a recap, we implemented an `Express.js` backend that supports the following Partner API functions: 
- Domain Suggestion lookup
- Domain Availability lookup
- Domain Registration
- Domain Transfers
- Domain Returns
- Partner API Operation Tracking

Then, we built out a `Next.js` frontend that implements our four exposed `express` endpoints for `search`, `availability`, `registration`, and `checkout` to allow users to:
- Search for available Unstoppable domains
- Add Unstoppable domains to a shopping cart
- Add their payment details to a `fake` payment gateway
- Recieve their Unstoppable domain(s)

Continue to build upon this demo and happy coding!