#!/usr/bin/env bash

set -x

source .scripts/logging_utils.sh

( startgroup "Ensuring Miniforge" ) 2> /dev/null

MICROMAMBA_VERSION="2.0.2-0"
MICROMAMBA_URL="https://github.com/mamba-org/micromamba-releases/releases/download/${MICROMAMBA_VERSION}/micromamba-osx-64"
MINIFORGE_HOME="${MINIFORGE_HOME:-${HOME}/Miniforge3}"

if [[ -d "${MINIFORGE_HOME}" ]]; then
  echo "Miniforge already installed at ${MINIFORGE_HOME}."
else
  echo "Downloading micromamba ${MICROMAMBA_VERSION}"
  micromamba_tmp="$(mktemp -d)/micromamba"
  curl -L -o "${micromamba_tmp}" "${MICROMAMBA_URL}"
  chmod +x "${micromamba_tmp}"
  echo "Creating environment"
  "${micromamba_tmp}" create --yes --root-prefix ~/.conda --prefix "${MINIFORGE_HOME}" \
    --no-exp-repodata-parsing \
    --channel conda-forge \
    --file .ci_support/requirements.txt
fi

( endgroup "Ensuring Miniforge" ) 2> /dev/null

( startgroup "Configuring conda" ) 2> /dev/null

cat >~/.condarc <<CONDARC
always_yes: true
show_channel_urls: true
solver: libmamba
CONDARC

source "${MINIFORGE_HOME}/etc/profile.d/conda.sh"
conda activate base

echo -e "\n\nSetting up the condarc and mangling the compiler."
setup_conda_rc ./ ./recipes ./.ci_support/${CONFIG}.yaml
if [[ "${CI:-}" != "" ]]; then
  mangle_compiler ./ ./recipes .ci_support/${CONFIG}.yaml
fi

if [[ "${CI:-}" != "" ]]; then
  echo -e "\n\nMangling homebrew in the CI to avoid conflicts."
  /usr/bin/sudo mangle_homebrew
  /usr/bin/sudo -k
else
  echo -e "\n\nNot mangling homebrew as we are not running in CI"
fi

echo -e "\n\nRunning the build setup script."
source run_conda_forge_build_setup

set -e

# make sure there is a package directory so that artifact publishing works
mkdir -p "${MINIFORGE_HOME}/conda-bld/osx-64/" "${MINIFORGE_HOME}/conda-bld/noarch/"

# Find the recipes from main in this PR and remove them.
echo ""
echo "Finding recipes merged in main and removing them from the build."
pushd ./recipes > /dev/null
git fetch --force origin main:main
git ls-tree --name-only main -- . | xargs -I {} sh -c "rm -rf {} && echo Removing recipe: {}"
popd > /dev/null
echo ""

( endgroup "Configuring conda" ) 2> /dev/null

# We just want to build all of the recipes.
echo "Building all recipes"
python .ci_support/build_all.py

( startgroup "Inspecting artifacts" ) 2> /dev/null
# inspect_artifacts was only added in conda-forge-ci-setup 4.6.0; --all-packages in 4.9.3
command -v inspect_artifacts >/dev/null 2>&1 && inspect_artifacts --all-packages || echo "inspect_artifacts needs conda-forge-ci-setup >=4.9.3"
( endgroup "Inspecting artifacts" ) 2> /dev/null
