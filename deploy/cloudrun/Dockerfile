# DuDuClaw OS public site (website/ + docs-site/dist) served by nginx.
# The _site/ directory is assembled by scripts/build-site.sh and copied in by
# scripts/deploy-cloudrun.sh before `gcloud run deploy --source deploy/cloudrun`.
FROM --platform=linux/amd64 nginx:stable-alpine

RUN rm -rf /usr/share/nginx/html/*
COPY _site/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY mime.types /etc/nginx/mime.types

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
