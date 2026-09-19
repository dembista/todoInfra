const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;
const ENV = process.env.NODE_ENV || 'development';

app.use(express.json());
app.use(express.static('public'));

let todos = [];

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', env: ENV, timestamp: new Date().toISOString() });
});

app.get('/api/todos', (req, res) => {
  res.json(todos);
});

app.post('/api/todos', (req, res) => {
  const { title } = req.body;
  if (!title) {
    return res.status(400).json({ error: 'title is required' });
  }
  const todo = { id: todos.length + 1, title, done: false, createdAt: new Date().toISOString() };
  todos.push(todo);
  res.status(201).json(todo);
});

app.put('/api/todos/:id', (req, res) => {
  const id = Number(req.params.id);
  const todo = todos.find((t) => t.id === id);
  if (!todo) {
    return res.status(404).json({ error: 'todo not found' });
  }
  if (req.body.title !== undefined) todo.title = req.body.title;
  if (req.body.done !== undefined) todo.done = Boolean(req.body.done);
  res.json(todo);
});

app.delete('/api/todos/:id', (req, res) => {
  const id = Number(req.params.id);
  const index = todos.findIndex((t) => t.id === id);
  if (index === -1) {
    return res.status(404).json({ error: 'todo not found' });
  }
  todos.splice(index, 1);
  res.status(204).end();
});

app.listen(PORT, () => {
  console.log(`Todo app listening on port ${PORT} (${ENV})`);
});

module.exports = app;