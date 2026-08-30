# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

COMPOSE_LAUNCHER := "docker compose"

# Build the Arena image, then the launchable images.
build:
    ./build.sh

# Rebuild only the code-server layer, reusing the existing Arena image.
build-vscode:
    ./build.sh -s

# Build everything from scratch, no cache.
rebuild:
    ./build.sh -R

# Also build cuRobo (enables the `ik_reachable` reachability check).
build-curobo:
    INSTALL_CUROBO=true ./build.sh

launch:
    {{COMPOSE_LAUNCHER}} up -d

down:
    {{COMPOSE_LAUNCHER}} down

logs:
    {{COMPOSE_LAUNCHER}} logs -f

deploy: build launch

# Open a shell in the running container as the mapped host user.
shell:
    docker exec -it isaac-arena-vscode su $(id -un)

# Sync this directory and the Arena clone to a GPU host (ssh alias `gpu`).
# The stack cannot run on macOS; this is the path to a machine where it can.
DST := "gpu"
sync:
    rsync --delete --exclude '.git' --exclude '.env' -r . {{DST}}:isaac-arena-launchable --progress
    rsync --delete --exclude '.git' -r ../IsaacLab-Arena {{DST}}: --progress
