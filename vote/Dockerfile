# =========================
# Stage 1: Build dependencies
# =========================
FROM python:3.11-slim AS builder

WORKDIR /build

# Install only tools required to build Python dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gcc \
       g++ \
       libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# Install dependencies into a separate directory
RUN pip install \
    --no-cache-dir \
    --prefix=/install \
    -r requirements.txt


# =========================
# Stage 2: Minimal runtime
# =========================
FROM python:3.11-slim

WORKDIR /app

# Create non-root user
RUN useradd \
    --uid 10001 \
    --create-home \
    --shell /usr/sbin/nologin \
    appuser

# Copy ONLY installed Python packages
COPY --from=builder /install /usr/local

# Copy application
COPY --chown=10001:10001 . .

USER 10001

EXPOSE 4000

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:4000", "app:app"]