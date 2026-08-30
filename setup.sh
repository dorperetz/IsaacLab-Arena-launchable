#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# NVIDIA Brev setup script. Paste the contents of this file into the
# "Paste Script" tab when creating the Launchable. It is also safe to run by
# hand on any fresh Linux GPU host with Docker and the NVIDIA Container Toolkit.
#
# Expect 45-90 minutes and at least 250 GB of disk for the first run.

set -eux

# Optional: if you are NOT using a Brev Secure Link, set a code-server password.
# export VSCODE_PASSWORD=your_password

# The git URL of *this* repository, which the instance clones. Override with an env
# var to deploy from a fork or a branch other than the default.
LAUNCHABLE_REPO_URL="${LAUNCHABLE_REPO_URL:-https://github.com/dorperetz/IsaacLab-Arena-launchable}"
ARENA_REPO_URL="${ARENA_REPO_URL:-https://github.com/isaac-sim/IsaacLab-Arena}"
ARENA_REPO="${ARENA_REPO:-$HOME/IsaacLab-Arena}"
LAUNCHABLE_DIR="${LAUNCHABLE_DIR:-$HOME/isaac-arena-launchable}"

# Never prompt for credentials: there is no TTY here, and a prompt surfaces as a
# confusing "could not read Username ... No such device or address" instead of the
# real problem (a repo that is missing, private, or misspelled).
export GIT_TERMINAL_PROMPT=0

# Fail fast with a readable message if either repo is unreachable, rather than
# discovering it halfway through provisioning.
for url in "${ARENA_REPO_URL}" "${LAUNCHABLE_REPO_URL}"; do
    if ! git ls-remote "${url}" HEAD >/dev/null 2>&1; then
        echo "ERROR: cannot read git repository: ${url}" >&2
        echo "       Check that it exists, is public, and the URL is spelled correctly." >&2
        echo "       For a private repo, embed a token or provide a deploy key." >&2
        exit 1
    fi
done

# IsaacLab-Arena's .gitmodules points at git@github.com:... for both submodules.
# A fresh cloud instance has no SSH key, so rewrite those URLs to HTTPS before
# recursing, otherwise `submodule update` fails on a public repository.
git config --global url."https://github.com/".insteadOf "git@github.com:"

if [ ! -d "${ARENA_REPO}/.git" ]; then
    git clone "${ARENA_REPO_URL}" "${ARENA_REPO}"
fi
git -C "${ARENA_REPO}" submodule update --init --recursive

if [ ! -d "${LAUNCHABLE_DIR}/.git" ]; then
    git clone "${LAUNCHABLE_REPO_URL}" "${LAUNCHABLE_DIR}"
fi
cd "${LAUNCHABLE_DIR}"

# Host mounts for models, datasets and evaluation output. Created up front so the
# bind mounts do not spring into existence as root-owned directories.
mkdir -p "$HOME/datasets" "$HOME/models" "$HOME/eval"

cat > .env <<ENVEOF
ARENA_REPO=${ARENA_REPO}
HOST_UID=$(id -u)
HOST_GID=$(id -g)
HOST_USER=$(id -un)
HOST_GROUP=$(id -gn)
DATASETS_DIR=$HOME/datasets
MODELS_DIR=$HOME/models
EVAL_DIR=$HOME/eval
VIEWER_ENV=brev
ENVEOF

# Set INSTALL_CUROBO=true here to also build cuRobo (the `ik_reachable` check).
./build.sh 2>&1 | tee "$HOME/isaac-arena-build.log"

docker compose up -d
