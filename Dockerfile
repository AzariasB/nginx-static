FROM alpine:3.24 AS build

LABEL maintainer="Azarias B."

# renovate: datasource=docker depName=library/nginx versioning=semver
ENV NGINX_VERSION=1.31.4

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
WORKDIR /usr/src

RUN GPG_KEYS="41DB92713D3BF4BFF3EE91069C5E7FA2F54977D4 \
	D6786CE303D9A9022998DC6CC8464D549AF75C0A \
	43387825DDB1BB97EC36BA5D007C8D7C15D87369 \
	7338973069ED3F443F4D37DFA64FD5B17ADB39A8 \
	13C82A63B603576156E30A4EA0EA981B66B0D967 \
	573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62" \
	&& CONFIG="\
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--modules-path=/usr/lib/nginx/modules \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
	--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
	--user=nginx \
	--group=nginx \
	--with-threads \
	--with-http_realip_module \
	--with-file-aio \
	" \
	&& addgroup -S nginx \
	&& adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
	&& apk add --no-cache --virtual .build-deps \
	gcc \
	libc-dev \
	make \
	pcre-dev \
	zlib-dev \
	linux-headers \
	curl \
	gnupg \
	gd-dev \
	&& curl -fSL "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" -o nginx.tar.gz \
	&& curl -fSL "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz.asc"  -o nginx.tar.gz.asc \
	# Mitigate Shellcheck 2086, we want to split words
	&& fetch_gpg_keys() { \
	set -- "$@" "--recv-keys"; \
	for key in $GPG_KEYS; do set -- "$@" "$key"; done; \
	gpg "$@"; \
	} \
	&& GNUPGHOME="$(mktemp -d)" \
	&& export GNUPGHOME \
	&& found=''; \
	for server in \
	hkp://keyserver.ubuntu.com:80 \
	pgp.mit.edu \
	; do \
	echo "Fetching GPG keys $GPG_KEYS from $server"; \
	fetch_gpg_keys --keyserver "$server" --keyserver-options timeout=10 && found=yes && break; \
	done; \
	test -z "$found" && echo >&2 "error: failed to fetch GPG keys $GPG_KEYS" && exit 1; \
	gpg --batch --verify nginx.tar.gz.asc nginx.tar.gz \
	&& tar -zx --strip-components=1 -f nginx.tar.gz \
	&& sed -i 's@"nginx/"@"-/"@g' src/core/nginx.h \
	&& sed -i 's@r->headers_out.server == NULL@0@g' src/http/ngx_http_header_filter_module.c \
	&& sed -i 's@r->headers_out.server == NULL@0@g' src/http/v2/ngx_http_v2_filter_module.c \
	&& sed -i 's@<hr><center>nginx</center>@@g' src/http/ngx_http_special_response.c \
	# Mitigate Shellcheck 2086, we want to split words
	&& make_config() { \
	for config_element in $CONFIG; do set -- "$@" "$config_element"; done; \
	set -- "$@" "--with-debug"; \
	set -o xtrace; \
	./configure "$@"; \
	set +o xtrace; \
	} \
	&& make_config \
	&& make -j "$(getconf _NPROCESSORS_ONLN)" \
	&& mv objs/nginx objs/nginx-debug \
	&& make_config \
	&& make -j "$(getconf _NPROCESSORS_ONLN)" \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& install -m755 objs/nginx-debug /usr/sbin/nginx-debug \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx*

FROM scratch

COPY --from=build \
	/lib/ld-musl-*.so.1 \
	/usr/lib/libpcre.so.1 \
	/usr/lib/libz.so.1 \
	/lib/

COPY --from=build /var/log /var/log
COPY --from=build /etc/nginx /etc/nginx
COPY --from=build /etc/passwd /etc/group /etc/
COPY --from=build /usr/sbin/nginx /usr/sbin/
COPY --from=build --chown=1000:1000 /var/cache/nginx /var/cache/nginx
COPY --from=build --chown=1000:1000 /var/run /var/run
COPY --from=build /usr/sbin/nginx /usr/sbin/nginx
COPY --from=build /usr/bin/wget /usr/bin/wget

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.vh.default.conf /etc/nginx/conf.d/default.conf
RUN --mount=type=bind,from=build,source=/,target=/mount ["/mount/bin/busybox", "ln", "-sf", "/dev/stdout", "/var/log/nginx/access.log"]
RUN --mount=type=bind,from=build,source=/,target=/mount ["/mount/bin/busybox", "ln", "-sf", "/dev/stderr", "/var/log/nginx/error.log"]
RUN --mount=type=bind,from=build,source=/,target=/mount ["/mount/bin/busybox", "mkdir","/static"]

HEALTHCHECK --interval=5s --timeout=2s --start-interval=5s \
    CMD ["/usr/bin/wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:8080/healthz"]

EXPOSE 8080

STOPSIGNAL SIGTERM

USER 1000:1000

CMD ["/usr/sbin/nginx"]
