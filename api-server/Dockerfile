FROM node:20-alpine

WORKDIR /usr/src/app

COPY package.json ./
RUN npm install --production

COPY src ./src

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "src/index.js"]
