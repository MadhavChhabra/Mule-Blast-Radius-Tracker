# Build the Flutter web bundle, then serve it as static files via nginx.
FROM ghcr.io/cirruslabs/flutter:3.24.3 AS build
WORKDIR /src
COPY dashboard/ .
ARG APIGUARD_API=http://localhost:8080
RUN flutter pub get && flutter build web --release --web-renderer html --dart-define=APIGUARD_API=${APIGUARD_API}

FROM nginx:alpine
COPY --from=build /src/build/web /usr/share/nginx/html
COPY dashboard/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
