FROM node:20-alpine

WORKDIR /workspace/api

COPY package.json ./
RUN npm install

COPY src ./src

EXPOSE 3000

CMD ["npm", "run", "start"]
