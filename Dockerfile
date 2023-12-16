# Builder image
# 
# This sets up the environment used to build swiftarr.
FROM docker.io/library/swift:5.8-jammy as builder

ARG env

RUN apt-get -qq update && apt-get install -y \
    libssl-dev zlib1g-dev libgd-dev
RUN mkdir -p /build/lib && cp -R /usr/lib/swift/linux/*.so* /build/lib

WORKDIR /app

# Not copying "." means that changes to the runtime scripts do not trigger
# a complete application rebuild, which saves a lot of time.
#
# We copy some of the .build directory to prevent having to fetch state
# from the internet during a rebuild. Note that this requires
# the .build directory to exist which means you've seeded it from somewhere
# or done a local build.
#
# The README.md here is a hack to conditionally copy based on whether you have
# done a local build or not. This is pretty ghetto but I think it's the only
# way to allow for an offline build while maintaining compatibility for
# fresh users. The trailing / is important here so don't screw that up.
# https://redgreenrepeat.com/2018/04/13/how-to-conditionally-copy-file-in-dockerfile/
COPY ./README.md ./.build/checkouts* /app/.build/checkouts/
COPY ./README.md ./.build/workspace-state.json* /app/.build/
# We copy the app sources after the .build so that the image build can use
# the cached image layer.
COPY ./Sources /app/Sources
COPY ./Package.* /app
COPY ./Tests /app/Tests

# This runs the actual build.
RUN swift build -c release && mv `swift build -c release --show-bin-path` /build/bin

# Base image
#
# This has its own build stage to allow the depedencies from the internet
# to be installed in a cached image. Otherwise it'd be running the steps
# every time which we don't want.
FROM docker.io/library/ubuntu:22.04 as base

# Prereqs
COPY scripts/init-prereqs.sh /
COPY scripts/run.sh /
COPY scripts/health.sh /
RUN mkdir -p /app/images
RUN /init-prereqs.sh

# User
RUN useradd -U -d /app -c "Swiftarr App User" -s /bin/bash swiftarr
RUN chown -R swiftarr:swiftarr /app
USER swiftarr:swiftarr

# Run
CMD ["/run.sh"]

# Actual Swiftarr Image
#
# This sources from the base image we built above.
FROM base

ARG env
ARG port
ENV ENVIRONMENT=$env
ENV PORT=$port
ENV AUTO_MIGRATE=true

# App installation
WORKDIR /app
COPY --from=builder /build/bin/swiftarr /app
COPY --from=builder /build/lib/* /usr/lib/
COPY --from=builder /build/bin/swiftarr_swiftarr.resources /app/swiftarr_swiftarr.resources
# @TODO tests???

# Healthcheck & Network 
EXPOSE $port
HEALTHCHECK --interval=10s --retries=3 --start-period=3s --timeout=10s CMD [ "/health.sh" ]
