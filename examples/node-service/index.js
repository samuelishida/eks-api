// Reference-only Node.js sample service (not deployed).
// A tiny health endpoint; the shape mirrors the Go API's /healthz.
const http = require("http");

const port = Number(process.env.PORT) || 8080;

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/healthz") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

server.listen(port, () => {
  console.log(`node-service listening on :${port}`);
});
