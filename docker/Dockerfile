# Test runner image: Factorio headless + Node + factorio-test-cli.
# Factorio headless is x86_64 only; on Apple silicon run with --platform linux/amd64.
FROM node:22-bookworm-slim

ARG FACTORIO_VERSION=2.1.25
ARG FACTORIO_TEST_CLI_VERSION=latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl xz-utils ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://factorio.com/get-download/${FACTORIO_VERSION}/headless/linux64" \
    | tar -xJ -C /opt

RUN npm install -g "factorio-test-cli@${FACTORIO_TEST_CLI_VERSION}"

ENV PATH="/opt/factorio/bin/x64:${PATH}"
WORKDIR /work
ENTRYPOINT ["factorio-test"]
CMD ["run", "--mod-path", "."]
