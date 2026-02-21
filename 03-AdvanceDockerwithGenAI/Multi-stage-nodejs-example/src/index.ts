import express from "express";
import cors from "cors";
import helmet from "helmet";
import morgan from "morgan";
import { z } from "zod";

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(morgan("combined"));
app.use(express.json());

// Validation schemas
const UserSchema = z.object({
  name: z.string().min(2),
  email: z.string().email(),
  role: z.enum(["admin", "user", "viewer"]),
});

// In-memory store
interface User {
  id: number;
  name: string;
  email: string;
  role: string;
  createdAt: Date;
}

let users: User[] = [];
let nextId = 1;

// Routes
app.get("/", (_req, res) => {
  res.json({
    name: "realworld-api",
    version: "1.0.0",
    endpoints: ["/health", "/api/users"],
  });
});

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
    memoryUsage: process.memoryUsage(),
  });
});

// GET all users
app.get("/api/users", (_req, res) => {
  res.json({ count: users.length, data: users });
});

// GET user by id
app.get("/api/users/:id", (req, res) => {
  const user = users.find((u) => u.id === parseInt(req.params.id));
  if (!user) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  res.json(user);
});

// POST create user
app.post("/api/users", (req, res) => {
  const result = UserSchema.safeParse(req.body);
  if (!result.success) {
    res.status(400).json({ error: result.error.issues });
    return;
  }

  const user: User = {
    id: nextId++,
    ...result.data,
    createdAt: new Date(),
  };
  users.push(user);
  res.status(201).json(user);
});

// DELETE user
app.delete("/api/users/:id", (req, res) => {
  const index = users.findIndex((u) => u.id === parseInt(req.params.id));
  if (index === -1) {
    res.status(404).json({ error: "User not found" });
    return;
  }
  users.splice(index, 1);
  res.status(204).send();
});

// Start server
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || "development"}`);
});