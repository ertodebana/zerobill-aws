import { createPublicKey, randomUUID, verify as verifySignature } from "node:crypto";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const TOKEN_RE = /^Bearer ([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/;
const MAX_TOKEN_LENGTH = 4096;
const MAX_BODY_BYTES = 8192;
const JWKS_TTL_MS = 60 * 60 * 1000;
const JWKS_COOLDOWN_MS = 60 * 1000;

// The AWS SDK is supplied by the Lambda Node.js runtime. Loading it dynamically
// keeps the isolated JWT tests runnable with Node alone; the client is still
// constructed once at module scope in Lambda.
let ddb;
let ddbCommands;
let ddbLoadError;
const ddbReady = import("@aws-sdk/client-dynamodb")
  .then((sdk) => {
    ddbCommands = sdk;
    ddb = new sdk.DynamoDBClient({ maxAttempts: 2 });
  })
  .catch((error) => {
    ddbLoadError = error;
  });

let jwksKeys = new Map();
let jwksFetchedAt = 0;
let jwksLastAttemptAt = 0;

function failure(code, statusCode = 401) {
  const error = new Error(code);
  error.code = code;
  error.statusCode = statusCode;
  return error;
}

function decodeJsonSegment(segment, code) {
  try {
    return JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
  } catch {
    throw failure(code);
  }
}

async function getCognitoKey(kid) {
  const now = Date.now();
  if (jwksKeys.has(kid) && now - jwksFetchedAt < JWKS_TTL_MS) {
    return jwksKeys.get(kid);
  }

  if (now - jwksLastAttemptAt >= JWKS_COOLDOWN_MS) {
    jwksLastAttemptAt = now;
    const poolId = process.env.USER_POOL_ID;
    const region = process.env.AWS_REGION;
    const issuer = `https://cognito-idp.${region}.amazonaws.com/${poolId}`;

    try {
      const response = await fetch(`${issuer}/.well-known/jwks.json`, {
        signal: AbortSignal.timeout(1500),
      });
      if (!response.ok) throw new Error("jwks_http_error");

      const document = await response.json();
      const nextKeys = new Map();
      for (const jwk of document.keys ?? []) {
        if (jwk.kty !== "RSA" || jwk.alg !== "RS256" || jwk.use !== "sig" || typeof jwk.kid !== "string") {
          continue;
        }
        try {
          nextKeys.set(jwk.kid, createPublicKey({ key: jwk, format: "jwk" }));
        } catch {
          // Ignore malformed keys and keep only keys OpenSSL can use.
        }
      }
      jwksKeys = nextKeys;
      jwksFetchedAt = now;
    } catch {
      // Keep a stale cache on network errors. A known cached kid can still work.
      if (jwksKeys.size === 0) throw failure("jwks_unavailable", 503);
    }
  }

  const key = jwksKeys.get(kid);
  if (!key) throw failure("unknown_kid");
  return key;
}

export async function verifyToken(token, { issuer, clientId, getKey, nowSec = Math.floor(Date.now() / 1000) }) {
  if (typeof token !== "string" || token.length > MAX_TOKEN_LENGTH) throw failure("token_too_large");
  const match = TOKEN_RE.exec(`Bearer ${token}`);
  if (!match) throw failure("malformed_token");

  const [, headerPart, payloadPart, signaturePart] = match;
  const header = decodeJsonSegment(headerPart, "malformed_header");
  if (header.alg !== "RS256") throw failure("unsupported_algorithm");
  if (typeof header.kid !== "string" || header.kid.length === 0) throw failure("missing_kid");

  const claims = decodeJsonSegment(payloadPart, "malformed_payload");
  if (claims.iss !== issuer) throw failure("wrong_issuer");
  if (claims.token_use !== "access") throw failure("wrong_token_use");
  if (claims.client_id !== clientId) throw failure("wrong_client_id");
  if (Object.hasOwn(claims, "aud")) throw failure("unexpected_audience");
  if (typeof claims.exp !== "number" || !Number.isFinite(claims.exp) || nowSec >= claims.exp) {
    throw failure("expired_token");
  }
  if (typeof claims.iat !== "number" || !Number.isFinite(claims.iat) || claims.iat > nowSec + 60) {
    throw failure("invalid_iat");
  }
  if (typeof claims.sub !== "string" || !UUID_RE.test(claims.sub)) throw failure("invalid_sub");

  let key;
  try {
    key = await getKey(header.kid);
  } catch (error) {
    if (error?.code === "jwks_unavailable") throw error;
    if (error?.code === "unknown_kid") throw error;
    throw failure("unknown_kid");
  }

  let valid = false;
  try {
    valid = verifySignature(
      "RSA-SHA256",
      Buffer.from(`${headerPart}.${payloadPart}`),
      key,
      Buffer.from(signaturePart, "base64url"),
    );
  } catch {
    valid = false;
  }
  if (!valid) throw failure("invalid_signature");

  return { sub: claims.sub };
}

function response(statusCode, message, extraHeaders = {}) {
  return {
    statusCode,
    headers: { "content-type": "application/json", ...extraHeaders },
    body: statusCode === 204 ? "" : JSON.stringify({ message }),
  };
}

function jsonResponse(statusCode, value, extraHeaders = {}) {
  return {
    statusCode,
    headers: { "content-type": "application/json", ...extraHeaders },
    body: JSON.stringify(value),
  };
}

function headerValue(headers, name) {
  const wanted = name.toLowerCase();
  for (const [key, value] of Object.entries(headers ?? {})) {
    if (key.toLowerCase() === wanted) return value;
  }
  return undefined;
}

function routeFor(method, path) {
  if (path === "/notes") {
    if (method === "GET" || method === "POST") return { route: "/notes", noteId: null };
    return { response: response(405, "method not allowed"), route: "/notes" };
  }

  const match = /^\/notes\/([0-9a-f-]{36})$/.exec(path);
  if (match) {
    if (["GET", "PUT", "DELETE"].includes(method)) return { route: "/notes/{id}", noteId: match[1] };
    return { response: response(405, "method not allowed"), route: "/notes/{id}" };
  }

  return { response: response(404, "not found"), route: "unmatched" };
}

function decodeRequestBody(event) {
  const raw = event.body ?? "";
  const body = event.isBase64Encoded ? Buffer.from(raw, "base64").toString("utf8") : raw;
  if (Buffer.byteLength(body, "utf8") > MAX_BODY_BYTES) throw failure("body_too_large", 413);
  try {
    const value = JSON.parse(body);
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_object");
    return value;
  } catch {
    throw failure("invalid_json", 400);
  }
}

function validateNoteBody(value) {
  const title = value.title;
  const body = value.body;
  if (typeof title !== "string" || [...title].length < 1 || [...title].length > 200) {
    throw failure("invalid_title", 400);
  }
  if (typeof body !== "string" || Buffer.byteLength(body, "utf8") > 2000) {
    throw failure("invalid_body", 400);
  }
  return { title, body };
}

function fromAttribute(item) {
  return {
    id: item.note_id.S,
    title: item.title.S,
    body: item.body.S,
    created_at: item.created_at.S,
    updated_at: item.updated_at.S,
  };
}

async function sendDdb(command) {
  await ddbReady;
  if (ddbLoadError) throw ddbLoadError;
  return ddb.send(command);
}

function isConditionalFailure(error) {
  return error?.name === "ConditionalCheckFailedException";
}

function isThrottle(error) {
  return ["ProvisionedThroughputExceededException", "ThrottlingException", "RequestLimitExceeded"].includes(error?.name);
}

export async function handler(event) {
  const startedAt = Date.now();
  const method = event?.requestContext?.http?.method ?? "UNKNOWN";
  const routed = routeFor(method, event?.rawPath ?? "");
  let route = routed.route;
  let status = 200;
  let reason;
  let errorName;
  let sub;
  let result;

  try {
    if (routed.response) {
      result = routed.response;
      status = result.statusCode;
      return result;
    }

    const authorization = headerValue(event.headers, "authorization");
    const bearer = typeof authorization === "string" ? /^Bearer (.+)$/.exec(authorization) : null;
    if (!bearer) throw failure("missing_bearer_token");

    const userPoolId = process.env.USER_POOL_ID;
    const issuer = `https://cognito-idp.${process.env.AWS_REGION}.amazonaws.com/${userPoolId}`;
    try {
      ({ sub } = await verifyToken(bearer[1], {
        issuer,
        clientId: process.env.CLIENT_ID,
        getKey: getCognitoKey,
      }));
    } catch (error) {
      reason = error?.code ?? "invalid_token";
      if (error?.statusCode === 503) {
        throw failure(reason, 503);
      }
      throw failure(reason);
    }

    let note;
    if (method === "POST") {
      const input = validateNoteBody(decodeRequestBody(event));
      const now = new Date().toISOString();
      const item = {
        user_id: { S: sub },
        note_id: { S: randomUUID() },
        title: { S: input.title },
        body: { S: input.body },
        created_at: { S: now },
        updated_at: { S: now },
      };
      await sendDdb(new ddbCommands.PutItemCommand({
        TableName: process.env.TABLE_NAME,
        Item: item,
        ConditionExpression: "attribute_not_exists(note_id)",
      }));
      status = 201;
      result = jsonResponse(status, fromAttribute(item));
    } else if (method === "GET" && route === "/notes") {
      // ponytail: Limit 25, no pagination cursor; add LastEvaluatedKey cursor when users exceed 25 notes
      const items = await sendDdb(new ddbCommands.QueryCommand({
        TableName: process.env.TABLE_NAME,
        KeyConditionExpression: "user_id = :user_id",
        ExpressionAttributeValues: { ":user_id": { S: sub } },
        Limit: 25,
        ConsistentRead: false,
      }));
      status = 200;
      result = jsonResponse(status, { items: (items.Items ?? []).map(fromAttribute) });
    } else if (method === "GET") {
      const found = await sendDdb(new ddbCommands.GetItemCommand({
        TableName: process.env.TABLE_NAME,
        Key: { user_id: { S: sub }, note_id: { S: routed.noteId } },
        ConsistentRead: false,
      }));
      if (!found.Item) {
        status = 404;
        result = response(status, "not found");
      } else {
        status = 200;
        result = jsonResponse(status, fromAttribute(found.Item));
      }
    } else if (method === "PUT") {
      const input = validateNoteBody(decodeRequestBody(event));
      const now = new Date().toISOString();
      const updated = await sendDdb(new ddbCommands.UpdateItemCommand({
        TableName: process.env.TABLE_NAME,
        Key: { user_id: { S: sub }, note_id: { S: routed.noteId } },
        UpdateExpression: "SET title = :title, body = :body, updated_at = :updated_at",
        ExpressionAttributeValues: {
          ":title": { S: input.title },
          ":body": { S: input.body },
          ":updated_at": { S: now },
        },
        ConditionExpression: "attribute_exists(note_id)",
        ReturnValues: "ALL_NEW",
      }));
      status = 200;
      result = jsonResponse(status, fromAttribute(updated.Attributes));
    } else {
      await sendDdb(new ddbCommands.DeleteItemCommand({
        TableName: process.env.TABLE_NAME,
        Key: { user_id: { S: sub }, note_id: { S: routed.noteId } },
        ConditionExpression: "attribute_exists(note_id)",
      }));
      status = 204;
      result = response(status, "");
    }
  } catch (error) {
    if (error?.statusCode === 401) {
      status = 401;
      reason = error.code ?? "unauthorized";
      result = response(status, "unauthorized", { "www-authenticate": "Bearer" });
    } else if (error?.statusCode === 503 || isThrottle(error)) {
      status = 503;
      reason = isThrottle(error) ? "throttled" : (error.code ?? "service_unavailable");
      result = response(status, "service unavailable", { "retry-after": "1" });
    } else if (error?.statusCode === 413) {
      status = 413;
      result = response(status, "request too large");
    } else if (error?.statusCode === 400) {
      status = 400;
      result = response(status, "invalid request");
    } else if (isConditionalFailure(error)) {
      status = 404;
      result = response(status, "not found");
    } else {
      status = 500;
      errorName = error?.name ?? "Error";
      result = response(status, "internal server error");
    }
  } finally {
    const record = {
      method,
      route,
      status,
      ms: Date.now() - startedAt,
      ...(reason && (status === 401 || status === 503) ? { reason } : {}),
      ...(sub ? { sub8: sub.slice(0, 8) } : {}),
      ...(status === 500 ? { error_name: errorName } : {}),
    };
    console.log(JSON.stringify(record));
  }

  return result;
}
