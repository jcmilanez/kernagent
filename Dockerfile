# Multi-stage Docker build that compiles the Ghidra decompiler so the image
# works on macOS ARM (and other platforms) where the native binaries are not
# shipped pre-built.

FROM eclipse-temurin:21-jdk-jammy AS ghidra-builder

ENV DEBIAN_FRONTEND=noninteractive
ENV GHIDRA_VERSION=11.4.2
ENV GHIDRA_BUILD=20250826
ENV GHIDRA_DIR=ghidra_${GHIDRA_VERSION}_PUBLIC
ENV GHIDRA_SHA=795a02076af16257bd6f3f4736c4fc152ce9ff1f95df35cd47e2adc086e037a6
ENV GHIDRA_URL=https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_BUILD}.zip
ENV GRADLE_VERSION=8.8

# Install native build tooling required for Ghidra's decompiler
RUN apt-get update && apt-get install -y \
    build-essential \
    bison \
    flex \
    git \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install a modern Gradle version (the apt one is too old for Ghidra)
RUN wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O /tmp/gradle.zip \
    && unzip -q /tmp/gradle.zip -d /opt \
    && mv "/opt/gradle-${GRADLE_VERSION}" /opt/gradle \
    && rm /tmp/gradle.zip
ENV PATH="/opt/gradle/bin:${PATH}"

# Download and verify Ghidra, then compile the native decompiler
WORKDIR /tmp
RUN wget -q "${GHIDRA_URL}" -O ghidra.zip \
    && echo "${GHIDRA_SHA} ghidra.zip" | sha256sum -c - \
    && unzip -q ghidra.zip \
    && mv "${GHIDRA_DIR}" /ghidra \
    && rm ghidra.zip

WORKDIR /ghidra/support/gradle
RUN gradle --no-daemon buildNatives

################################################################################

FROM eclipse-temurin:21-jdk-jammy

ENV DEBIAN_FRONTEND=noninteractive

# Install Python runtime and helpers
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    wget \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

# Bring in the compiled Ghidra distribution (with native decompiler)
COPY --from=ghidra-builder /ghidra /opt/ghidra
ENV GHIDRA_INSTALL_DIR=/opt/ghidra

# Ensure the decompiler binaries are executable inside the image
RUN find "${GHIDRA_INSTALL_DIR}/Ghidra/Features/Decompiler/os" -type f -name "decompile" -exec chmod +x {} +

# Python configuration
ENV PYTHONUNBUFFERED=1

# Copy application sources and install dependencies with uv
WORKDIR /workspace/project

# First, copy pyproject.toml and README to the project root
COPY pyproject.toml uv.lock /workspace/project/
COPY README.md /workspace/project/README.md

# Create the kernagent package directory and copy Python sources
RUN mkdir -p /workspace/project/kernagent
COPY kernagent/__init__.py \
     kernagent/__main__.py \
     kernagent/agent.py \
     kernagent/cli.py \
     kernagent/config.py \
     kernagent/llm_client.py \
     kernagent/log.py \
     kernagent/prompts.py \
     /workspace/project/kernagent/

# Copy subdirectories
COPY kernagent/oneshot /workspace/project/kernagent/oneshot
COPY kernagent/snapshot /workspace/project/kernagent/snapshot

# Install dependencies using uv (including dev dependencies for testing)
RUN cd /workspace/project && uv sync --all-groups

# Share binaries via mounted volume
VOLUME /data

# Use uv to run the application
ENTRYPOINT ["uv", "run", "--directory", "/workspace/project", "-m", "kernagent.cli"]
CMD ["--help"]
