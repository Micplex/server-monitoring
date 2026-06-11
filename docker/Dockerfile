FROM alpine:3.20
RUN apk add --no-cache bash coreutils procps util-linux curl docker-cli grep sed gawk
WORKDIR /opt/monitoring
COPY . /opt/monitoring/
RUN mkdir -p /opt/monitoring/logs /opt/monitoring/data/metrics /opt/monitoring/data/alerts /opt/monitoring/data/reports /opt/monitoring/data/backups
# Fix Windows CRLF line endings
RUN find /opt/monitoring -type f \( -name "*.sh" -o -name "*.conf" -o -name "monitor" -o -name "alert-check" -o -name "report" -o -name "health" \) | xargs sed -i 's/\r//'
# Rewrite metrics_writer.sh with proper tab-separated output
RUN printf '#!/usr/bin/env bash\nwrite_metric(){\n  local collection="$1"; shift\n  local dir="${DATA_DIR}/metrics"; mkdir -p "$dir"\n  local file="${dir}/${collection}_$(date +%%Y-%%m-%%d).tsv"\n  local ts="$(date +'"'"'%%Y-%%m-%%d %%H:%%M:%%S'"'"')"\n  printf "%%s" "$ts" >> "$file"\n  for _arg in "$@"; do printf "\\t%%s" "$_arg" >> "$file"; done\n  printf "\\n" >> "$file"\n}\n' > /opt/monitoring/scripts/core/metrics_writer.sh
RUN find /opt/monitoring/scripts -name "*.sh" -exec chmod +x {} \; && chmod +x /opt/monitoring/bin/* /opt/monitoring/docker/docker-entrypoint.sh
CMD ["/bin/bash", "/opt/monitoring/docker/docker-entrypoint.sh"]
