# Stage 1: Build the Next.js App
FROM node:14 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Serve the App
FROM node:14-alpine
WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/package*.json ./
RUN npm install --only=production
EXPOSE 3000
CMD ["npm", "start"]
