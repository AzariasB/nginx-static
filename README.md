# Nginx static

This project provides a distroless, rootless nginx image that is optimized for serving static content behind a reverse proxy.
As such, it does not include compression, https or other "heavy-lifting" features that should be handled by the reverse proxy.

## How to use

Here is an example of a docker-compose file on how you can use the image:

```docker-compose
name: "nginx"
services:
  nginx:
    image: "azariasb/nginx-static:1.31.2"
    read_only: true
    ports:
      - "80:3000/tcp"
    volumes:
      - ".:/static"
    tmpfs:
      - "/var/cache/nginx:uid=1000,gid=1000"
      - "/var/run:uid=1000,gid=1000"
    restart: "unless-stopped"
```

You can also base a static website content based on this image like so:
```dockerfile
FROM node:24 as builder

RUN npm ci && npm run build

FROM azariasb/nginx-static:1.31.2

COPY --from=builder /app/dist /static

```

and then run it as shown in the docker-compose exemple.

## Why use this image ?

- rootless: this image runs without root privileges which lowers the risk of privilege escalation or sandbox escaping
- distroless: the only two executables in the image are wget for the healthcheck and nginx to run the process. Meaning an attacker cannot use any other commands if the container is compromised
- read-only ready: you can set the container to be read-only to avoid any changes to be done on the container. This makes sense in a static-serving server since it does not need to change at all.
- lightweight: it only weights 3.2MB compared to the 26.9MB of the nginx-alpine image
- secure: no version is shown on the error pages and the tokens are disable in the configuration

## Supported platforms

The supported platforms are:

- linux/amd64
- linux/arm64
- linux/arm/v7
