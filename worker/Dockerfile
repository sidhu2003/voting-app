# =========================
# Build stage
# =========================
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0 AS build

ARG TARGETARCH
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN echo "Building on $BUILDPLATFORM for $TARGETPLATFORM ($TARGETARCH)"

WORKDIR /source

COPY *.csproj .

RUN dotnet restore -a $TARGETARCH

COPY . .

RUN dotnet publish \
    -c Release \
    -o /app/publish \
    -a $TARGETARCH \
    --self-contained false \
    --no-restore \
    /p:UseAppHost=false


# =========================
# Runtime stage
# =========================
FROM mcr.microsoft.com/dotnet/runtime:8.0

WORKDIR /app

COPY --from=build /app/publish .

# Create non-root user
RUN useradd \
    --uid 10001 \
    --create-home \
    --shell /usr/sbin/nologin \
    appuser

USER 10001

ENTRYPOINT ["dotnet", "Worker.dll"]