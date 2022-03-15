#!/usr/bin/env bash
#
# WARNING
#
# THIS SCRIPT SHOULD BE RUN ONLY DURING A CODE FREEZE!!
#
# Make sure you have the following tools installed:
# - Git version 2.35 or newer
# - The git-filter-repo tool: brew install git-filter-repo
set -ex

if ! which git-filter-repo > /dev/null; then
    echo -e "git-filter-repo doesn't seem to be installed.\n"
    echo "To install it, follow the instructions in the link below:"
    echo "https://github.com/newren/git-filter-repo/blob/main/INSTALL.md"
    exit 1
fi

MONOREPO_PATH=$(pwd)
TMP_DIR=$(mktemp -d)
OWNER_NAME=gabrielfalcao
PROJECT_NAME=lettuce
INTEGRATION_BRANCH_NAME="integrate-${PROJECT_NAME}"
TMP_REMOTE="git@github.com:${OWNER_NAME}/lettuce-pre-monorepo.git"
TMP_REMOTE_NAME="${PROJECT_NAME}-pre-monorepo"
TMP_CLONE_PATH="${TMP_DIR}/${PROJECT_NAME}"
BENCHMARK_LOG=$(mktemp -d)/benchmark.txt
# Step 1: Freshly clone ${PROJECT_NAME} in a tmp dir and switch to that dir
git clone git@github.com:${OWNER_NAME}/${PROJECT_NAME}.git ${TMP_CLONE_PATH}
pushd "${TMP_CLONE_PATH}"
# Step 2: Rewrite history ✊ via `git filter-repo` command.
#         First reword every commit whose python code executes *without error*. The callback uses a regex to match #1337 references change to ${OWNER_NAME}/test-monorepo-1#1337.
#         Next move all files  ${PROJECT_NAME} files under projects/${PROJECT_NAME}/ within the monorepo.
#

time git filter-repo \
	--commit-callback "
    commit.message = re.sub(
        b'\(\#([0-9]+)\)',
        lambda m: b'(${OWNER_NAME}/${PROJECT_NAME}#%b)' % m.group(1),
        commit.message
    )
    commit.message += (b'\nMigrated to ${OWNER_NAME}/test-monorepo-1 from ${OWNER_NAME}/${PROJECT_NAME}@%s'
        % commit.original_id[0:7])
    " \
    --path-rename :projects/${PROJECT_NAME}/ \
    --path-rename projects/${PROJECT_NAME}/tests/:tests/${PROJECT_NAME}/ \
    --path-rename projects/${PROJECT_NAME}/.travis.yml:.artifacts/${PROJECT_NAME}/.travis.yml \
    --path-rename projects/${PROJECT_NAME}/tox.ini:.artifacts/${PROJECT_NAME}/tox.ini \
    --path-rename projects/${PROJECT_NAME}/.github/:.artifacts/${PROJECT_NAME}/.github/ \
    | tee ${BENCHMARK_LOG}  # Benchmarking to test the hypothesis that the command might run faster if the python code within the `--commit-callback` command handles errors properly.

# Step 3: Push to temporary remote
git remote add temp-remote $TMP_REMOTE
git push -f -a temp-remote


# Step 4: Go to monorepo
pushd "${MONOREPO_PATH}"

# Step 5: Add ${PROJECT_NAME}'s temporary remote to the monorepo
git remote add ${TMP_REMOTE_NAME}

# Step 6: Create integration branch
git branch -D ${INTEGRATION_BRANCH_NAME}
git branch ${INTEGRATION_BRANCH_NAME}

# Step 7: Go to integration branch
git checkout ${INTEGRATION_BRANCH_NAME}

# Step 8: *Magic Step* -> `--allow-unrelated-histories`
git merge --squash --allow-unrelated-histories ${TMP_REMOTE_NAME}/master

# Step 9: Go back to monorepo's main branch
git checkout main

# Step 10: Merge the integration branch into main
git merge ${INTEGRATION_BRANCH_NAME}

# Step 11: Explain the next manual steps
echo "Now inspect your history, if everything looks fine, push to github"
echo "so that you can browse the final product and show of to your girlfriends"
#    Preferably on something other than the `main` branch
# 5. push up that branch that has the new history and take another look at it
# 6. git checkout main \
#      && git merge my-branch-with-the-history-that-we-just-pulled-in \
#      && git push
