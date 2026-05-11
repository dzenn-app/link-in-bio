# syntax=docker/dockerfile:1

FROM --platform=$TARGETPLATFORM node:22-alpine AS base
RUN apk add --no-cache libc6-compat openssl
RUN corepack enable && corepack prepare pnpm@latest --activate

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
COPY prisma ./prisma/
RUN pnpm install --frozen-lockfile

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=1024"

ARG NEXT_PUBLIC_APP_URL
ARG NEXT_PUBLIC_BETTER_AUTH_URL

ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL
ENV NEXT_PUBLIC_BETTER_AUTH_URL=$NEXT_PUBLIC_BETTER_AUTH_URL

# prisma.config.ts pakai DIRECT_URL, bukan DATABASE_URL
ENV DIRECT_URL="postgresql://dummy:dummy@localhost:5432/dummy"
ENV DATABASE_URL="postgresql://dummy:dummy@localhost:5432/dummy"
ENV BETTER_AUTH_SECRET="dummy-secret-for-build-only-will-be-replaced-at-runtime"
ENV BETTER_AUTH_URL="http://localhost:3000"
ENV GOOGLE_CLIENT_ID="dummy-google-client-id"
ENV GOOGLE_CLIENT_SECRET="dummy-google-client-secret"
ENV S3_PUBLIC_URL="https://dummy-s3-public-url.example.com"
ENV S3_BUCKET="dummy-bucket"
ENV S3_REGION="ap-southeast-1"
ENV S3_ACCESS_KEY="dummy-access-key"
ENV S3_SECRET_ACCESS_KEY="dummy-secret-access-key"

# Generate Prisma client dulu, lalu build Next.js.
RUN pnpm prisma generate --config prisma.config.ts
RUN pnpm exec next build

FROM base AS runner
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules

COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma
COPY --from=builder --chown=nextjs:nodejs /app/prisma.config.ts ./prisma.config.ts

COPY --from=builder --chown=nextjs:nodejs /app/lib/generated/prisma ./lib/generated/prisma
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK NONE

USER nextjs
EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "server.js"]
