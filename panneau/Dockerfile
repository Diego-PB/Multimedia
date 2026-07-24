FROM node:20-alpine

# Installer Docker CLI + Docker Compose plugin
RUN apk add --no-cache \
    docker-cli \
    docker-cli-compose \
    bash

WORKDIR /app

# Installer les dépendances Node.js
COPY package.json package-lock.json* ./
RUN npm install --production

# Copier le code source
COPY . .

# Créer le dossier de données persistantes
RUN mkdir -p /app/data

EXPOSE 3000

CMD ["node", "server.js"]
