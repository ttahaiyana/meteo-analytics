FROM node:22-alpine AS web
WORKDIR /w
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

FROM golang:1.26 AS api
WORKDIR /b
COPY backend/ ./
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

FROM r-base:4.5.2
RUN Rscript -e 'install.packages("jsonlite", repos="https://cloud.r-project.org")'
WORKDIR /app
COPY --from=api /server /app/bin/server
COPY --from=web /w/dist /app/frontend/dist
COPY analysis/ /app/analysis/
COPY data/locations.json /app/data/locations.json
VOLUME /app/data/raw
EXPOSE 8080
CMD ["/app/bin/server", "-root", "/app", "-addr", ":8080"]
