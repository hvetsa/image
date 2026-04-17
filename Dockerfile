FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# ─── System packages ──────────────────────────────────────────────────────────
# Runtime tools + build toolchain in one layer.
# Build tools (compilers, -dev headers) are purged after pip compiles packages.
COPY packages.txt /tmp/packages.txt
RUN apt-get update && \
    xargs -a /tmp/packages.txt apt-get install -y --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# ─── Latest Python (via deadsnakes PPA) ──────────────────────────────────────
# Install Python, bootstrap pip, install all packages, then purge build tools —
# all in one RUN so the compilers never persist in a committed layer.
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.13 \
        python3.13-dev \
        python3.13-venv \
    && rm -rf /var/lib/apt/lists/* && \
    # Set as default interpreter
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.13 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1 && \
    # Bootstrap pip
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.13 && \
    python3.13 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# ─── Python packages ──────────────────────────────────────────────────────────
COPY requirements.txt /tmp/requirements.txt
RUN python3.13 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt && \
    # Purge build-only packages — compilers and -dev headers are no longer needed
    apt-get purge -y --auto-remove \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        pkg-config \
        libssl-dev \
        libffi-dev \
        libxml2-dev \
        libxslt1-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        liblzma-dev \
        libncurses-dev \
        tk-dev \
        uuid-dev \
        python3.13-dev \
    && rm -rf /var/lib/apt/lists/*

# ─── Docker CLI ───────────────────────────────────────────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ─── Node Version Manager (nvm) + latest LTS Node ────────────────────────────
ENV NVM_DIR=/root/.nvm

COPY package.json /tmp/package.json
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts && \
    nvm alias default "lts/*" && \
    nvm use default && \
    # Global JS tooling + Claude Code in one layer
    npm install -g $(jq -r '.dependencies | to_entries | map("\(.key)@\(.value)") | join(" ")' /tmp/package.json) && \
    # Strip npm cache
    npm cache clean --force

# Persist nvm/node/npm on PATH for all subsequent RUN commands and at runtime
ENV PATH="$NVM_DIR/versions/node/$(ls $NVM_DIR/versions/node | sort -V | tail -1)/bin:$PATH"

# ─── cloudflared install ────────────────────────────
RUN mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | \
    tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | \
    tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && apt-get install -y cloudflared

# ─── openshift client install ────────────────────────────
 RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux-arm64.tar.gz \
      -o /tmp/oc.tar.gz \
 && tar -xzf /tmp/oc.tar.gz -C /usr/local/bin oc kubectl \
 && chmod +x /usr/local/bin/oc /usr/local/bin/kubectl \
 && rm /tmp/oc.tar.gz

# ─── Shell environment ────────────────────────────────────────────────────────
RUN printf '\n# nvm\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"\n' \
    >> /root/.bashrc

# ─── Entrypoint script ───────────────────────────────────────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN mkdir /root/.ssh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
