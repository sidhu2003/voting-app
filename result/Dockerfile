FROM node:22-alpine
WORKDIR /app

# Create non-root user with UID 10001
RUN addgroup -g 10001 -S appgroup \
    && adduser -u 10001 -S appuser -G appgroup

COPY package.json package-lock.json* ./

RUN npm install

# Make application files owned by the non-root user
COPY --chown=10001:10001 . .

USER 10001

EXPOSE 80

CMD ["node", "server.js"]