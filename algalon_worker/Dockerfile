# Multi-stage build for optimal image size
FROM rust:1.88-slim as builder

# Accept build arguments for version and port
ARG ALL_SMI_VERSION=v0.9.0
ARG PORT=9090

# Install system dependencies for cross-compilation
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    protobuf-compiler \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Clone the specific version of all-smi
RUN git clone --depth 1 --branch ${ALL_SMI_VERSION} https://github.com/inureyes/all-smi.git .

# Build the application in release mode
RUN cargo build --release --bin all-smi

# Runtime stage with minimal image
FROM debian:bookworm-slim

# Accept port argument for runtime
ARG PORT=9090
ENV ALL_SMI_PORT=${PORT}

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -r -s /bin/false allsmi

# Copy the binary from the builder stage
COPY --from=builder /app/target/release/all-smi /usr/local/bin/all-smi

# Make the binary executable
RUN chmod +x /usr/local/bin/all-smi

# Switch to non-root user
USER allsmi

# Expose the configurable port
EXPOSE ${PORT}

# Set the default command with configurable port
ENTRYPOINT ["/usr/local/bin/all-smi"]
CMD ["api", "--port", "${ALL_SMI_PORT}"]