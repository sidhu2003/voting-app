FROM node:17-alpine

WORKDIR /app

COPY package.json package.json
RUN npm install

COPY . .

CMD ["node", "server.js"]

EXPOSE 4000