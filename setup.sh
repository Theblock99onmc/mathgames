#!/bin/bash

# 1. Hoofdmap aanmaken
echo "Mappenstructuur aanmaken..."
mkdir -p math-hub-app/nginx
mkdir -p math-hub-app/backend
mkdir -p math-hub-app/public

cd math-hub-app

# 2. docker-compose.yml genereren
echo "docker-compose.yml aanmaken..."
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  db:
    image: postgres:16-alpine
    restart: always
    environment:
      POSTGRES_USER: mathuser
      POSTGRES_PASSWORD: mathpassword
      POSTGRES_DB: mathhub
    volumes:
      - postgres_data:/var/lib/postgresql/data

  backend:
    build: ./backend
    restart: always
    environment:
      DATABASE_URL: postgres://mathuser:mathpassword@db:5432/mathhub
      JWT_SECRET: supergeheimewachtwoordsleutel
    depends_on:
      - db

  frontend:
    image: nginx:alpine
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./public:/usr/share/nginx/html:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - backend

volumes:
  postgres_data:
EOF

# 3. Nginx configuratie genereren
echo "Nginx configuratie aanmaken..."
cat << 'EOF' > nginx/default.conf
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend:5000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# 4. Backend: package.json genereren
echo "Backend bestanden aanmaken..."
cat << 'EOF' > backend/package.json
{
  "name": "math-hub-backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "bcrypt": "^5.1.1",
    "cors": "^2.8.5",
    "express": "^4.19.2",
    "jsonwebtoken": "^9.0.2",
    "pg": "^8.11.5"
  }
}
EOF

# 5. Backend: server.js genereren
cat << 'EOF' > backend/server.js
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const app = express();
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

pool.query(`
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    xp INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS leaderboards (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    game_mode VARCHAR(50) NOT NULL,
    score INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
`).catch(console.error);

app.post('/auth/register', async (req, res) => {
  const { username, password } = req.body;
  try {
    const hash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (username, password_hash) VALUES ($1, $2) RETURNING id, username',
      [username, hash]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(400).json({ error: 'Gebruikersnaam bestaat al of ongeldige invoer' });
  }
});

app.post('/auth/login', async (req, res) => {
  const { username, password } = req.body;
  try {
    const user = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    if (user.rows.length === 0) return res.status(400).json({ error: 'Gebruiker niet gevonden' });

    const valid = await bcrypt.compare(password, user.rows[0].password_hash);
    if (!valid) return res.status(401).json({ error: 'Ongeldig wachtwoord' });

    const token = jwt.sign({ id: user.rows[0].id, username }, process.env.JWT_SECRET || 'geheim');
    res.json({ token, username, xp: user.rows[0].xp });
  } catch(err) {
    res.status(500).json({ error: 'Server fout' });
  }
});

app.get('/leaderboard/:game', async (req, res) => {
  const { game } = req.params;
  try {
    const result = await pool.query(`
      SELECT u.username, MAX(l.score) as highscore
      FROM leaderboards l
      JOIN users u ON l.user_id = u.id
      WHERE l.game_mode = $1
      GROUP BY u.username
      ORDER BY highscore DESC
      LIMIT 10
    `, [game]);
    res.json(result.rows);
  } catch(err) {
    res.status(500).json({ error: 'Fout bij ophalen leaderboard' });
  }
});

app.listen(5000, () => console.log('Backend draait op poort 5000'));
EOF

# 6. Backend: Dockerfile genereren
cat << 'EOF' > backend/Dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5000
CMD ["node", "server.js"]
EOF

# 7. Frontend: Tijdelijke index.html aanmaken
echo "Tijdelijke HTML-pagina aanmaken..."
cat << 'EOF' > public/index.html
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Math & Reken Hub - Setup Gelukt!</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #f4f4f9; }
        h1 { color: #4CAF50; }
    </style>
</head>
<body>
    <h1>Docker Setup is Succesvol! 🚀</h1>
    <p>Vervang dit bestand (<code>public/index.html</code>) door jouw eigen Math & Reken Hub HTML-code.</p>
</body>
</html>
EOF

echo ""
echo "==================================================="
echo "✅ Setup voltooid! Alle bestanden zijn aangemaakt in de map: math-hub-app/"
echo ""
echo "Volgende stappen:"
echo "1. Ga naar de map: cd math-hub-app"
echo "2. Vervang eventueel 'public/index.html' door jouw eigen HTML-bestand."
echo "3. Start de applicatie met: docker compose up -d --build"
echo "4. Open je browser en ga naar: http://localhost"
echo "==================================================="
