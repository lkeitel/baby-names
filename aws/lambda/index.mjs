import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand, PutCommand } from "@aws-sdk/lib-dynamodb";

const db = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.TABLE;
const ROOM = /^[a-z0-9-]{8,40}$/;
const TTL_SECONDS = 90 * 86400;

const str = (v, max) => typeof v === "string" && v.length > 0 && v.length <= max;
const list = (v, max = 800) => Array.isArray(v) && v.length <= max && v.every(x => str(x, 30));
const res = (statusCode, body) => ({ statusCode, headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

export const handler = async (event) => {
  if (event.requestContext?.http?.method !== "POST") return res(405, { error: "POST only" });
  if ((event.body || "").length > 40000) return res(413, { error: "too large" });
  let b;
  try { b = JSON.parse(event.body || "{}"); } catch { return res(400, { error: "bad json" }); }
  if (typeof b.room !== "string" || !ROOM.test(b.room)) return res(400, { error: "bad room" });

  if (b.action === "get") {
    const r = await db.send(new QueryCommand({
      TableName: TABLE, KeyConditionExpression: "room = :r", ExpressionAttributeValues: { ":r": b.room }
    }));
    const out = { players: {}, custom: [], stars: [] };
    for (const it of r.Items || []) {
      if (it.slot === "shared") { out.custom = it.custom || []; out.stars = it.stars || []; }
      else out.players[it.slot] = { name: it.name, liked: it.liked || [] };
    }
    return res(200, out);
  }

  if (b.action === "put") {
    const slot = String(b.slot);
    if (!["0", "1"].includes(slot) || !str(b.name, 20) || !list(b.liked)) return res(400, { error: "bad player" });
    const ttl = Math.floor(Date.now() / 1000) + TTL_SECONDS;
    await db.send(new PutCommand({ TableName: TABLE, Item: { room: b.room, slot, name: b.name, liked: b.liked, ttl } }));
    if (b.custom !== undefined || b.stars !== undefined) {
      if (!list(b.custom || [], 200) || !list(b.stars || [])) return res(400, { error: "bad shared" });
      await db.send(new PutCommand({
        TableName: TABLE, Item: { room: b.room, slot: "shared", custom: b.custom || [], stars: b.stars || [], ttl }
      }));
    }
    return res(200, { ok: true });
  }
  return res(400, { error: "unknown action" });
};
