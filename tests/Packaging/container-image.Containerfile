# Container image for opensim-cli packaging tests
# Based on debian:bookworm (Debian 12) by default
# Installs basic dependencies needed for testing

FROM docker.io/library/debian:bookworm

# Install basic utilities
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        ca-certificates \
        curl \
        gpg \
        podman \
        sudo \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user for testing
RUN useradd -m testuser && \
    echo 'testuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set up environment
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]
