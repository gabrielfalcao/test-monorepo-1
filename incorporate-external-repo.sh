#!/usr/bin/env bash
#
# WARNING
#
# THIS SCRIPT SHOULD BE RUN ONLY DURING A CODE FREEZE!!
#
# Make sure you have the following tools installed:
# - Git version 2.35 or newer
# - The git-filter-repo tool: brew install git-filter-repo
tput clear
set -ex

#   ___ ___  _  _ ___ ___ ___
#  / __/ _ \| \| | __|_ _/ __|
# | (_| (_) | .` | _| | | (_ |
#  \___\___/|_|\_|_| |___\___|
#  ___  _   ___    _   __  __ ___
# | _ \/_\ | _ \  /_\ |  \/  / __|
# |  _/ _ \|   / / _ \| |\/| \__ \
# |_|/_/ \_\_|_\/_/ \_\_|  |_|___/

# NOTE: Preferably on something other than the `main` branch
FINAL_MONOREPO_BRANCH_TARGET=main
MONOREPO_PATH=$(pwd)
TMP_DIR=$(mktemp -d)
OWNER_NAME=gabrielfalcao
PROJECT_NAME=lettuce # upstream project name, such as vi or hybrid
UPSTREAMS_MAIN_BRANCH_NAME=master  # this should be "main" for newer github projects or "master" for old ones :/
INTEGRATION_BRANCH_NAME="integrate-${PROJECT_NAME}"
TMP_REMOTE="git@github.com:${OWNER_NAME}/${PROJECT_NAME}-pre-monorepo.git"
TMP_REMOTE_NAME="${PROJECT_NAME}-pre-monorepo"
TMP_CLONE_PATH="${TMP_DIR}/${PROJECT_NAME}"
BENCHMARK_LOG="${TMP_DIR}/benchmark.txt"

#  _  _ ___ _    ___ ___ ___
# | || | __| |  | _ \ __| _ \
# | __ | _|| |__|  _/ _||   /
# |_||_|___|____|_| |___|_|_\
#  ___ _   _ _  _  ___ _____ ___ ___  _  _ ___
# | __| | | | \| |/ __|_   _|_ _/ _ \| \| / __|
# | _|| |_| | .` | (__  | |  | | (_) | .` \__ \
# |_|  \___/|_|\_|\___| |_| |___\___/|_|\_|___/
function integration_branch_already_exists() {
    git branch --list | grep "[[:space:]]\+\b${INTEGRATION_BRANCH_NAME}\$" > /dev/null
}
function temporary_remote_already_exists_in_monorepo() {
    git remote show | grep "^${TMP_REMOTE_NAME}\$" > /dev/null
}
function determine_push_url_of_git_remote() {
    name="$@"
    git remote show -n "${name}" | grep -i 'push.*url' | awk '{ print $NF }'
}

#  ___   _   ___ ___ _______   __
# / __| /_\ | __| __|_   _\ \ / /
# \__ \/ _ \| _|| _|  | |  \ V /
# |___/_/ \_\_| |___| |_|   |_|
#   ___ _  _ ___ ___ _  _____
#  / __| || | __/ __| |/ / __|
# | (__| __ | _| (__| ' <\__ \
#  \___|_||_|___\___|_|\_\___/

if ! git diff --quiet; then
    echo "The Git tree is dirty!!"
    echo "Make sure that to commit AND push all changes before running this migration script."
    exit 1
fi

if ! which git-filter-repo > /dev/null; then
    echo -e "git-filter-repo doesn't seem to be installed.\n"
    echo "To install it you can follow the instructions in the link below:"
    echo "https://github.com/newren/git-filter-repo/blob/main/INSTALL.md"
    echo ""
    echo "Tip: Mac users can simply run:"
    echo -e "\tbrew install git-filter-repo"
    exit 1
fi



###############################################################################################


#
#    _   ___ _____ _   _  _   _
#   /_\ / __|_   _| | | |/_\ | |
#  / _ \ (__  | | | |_| / _ \| |__
# /_/ \_\___| |_|  \___/_/ \_\____|
#  __  __ _  ___ ___    _ _____ _  ___  _  _
# |  \/  (_)/ __| _ \  /_\_   _(_)/ _ \| \| |
# | |\/| | | (_ |   / / _ \| | | | (_) | .` |
# |_|  |_|_|\___|_|_\/_/ \_\_| |_|\___/|_|\_|
#  _    ___   ___ _  ___
# | |  / _ \ / __(_)/ __|
# | |_| (_) | (_ | | (__
# |____\___/ \___|_|\___|

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
git remote add temp-remote ${TMP_REMOTE}
git push --force --all temp-remote

# Step 4: Go to monorepo
pushd "${MONOREPO_PATH}"

# Step 5: Add ${PROJECT_NAME}'s temporary remote to the monorepo. WARNING: if a remote with $TMP_REMOTE_NAME already exists it will be replaced!
if temporary_remote_already_exists_in_monorepo; then
    existing_tmp_remote=$(determine_push_url_of_git_remote "${TMP_REMOTE_NAME}")
    if  [ "${existing_tmp_remote}" != "${TMP_REMOTE}" ]; then
        echo "WARNING: Replacing remote url from '$existing_tmp_remote' to '$TMP_REMOTE'"
    fi
    git remote rm "${TMP_REMOTE_NAME}"
fi
git remote add ${TMP_REMOTE_NAME} ${TMP_REMOTE}

# Step 6: Fetch the whole history of a specific branch from TMP_REMOTE
git fetch ${TMP_REMOTE_NAME} ${UPSTREAMS_MAIN_BRANCH_NAME}

# Step 7: If integration branch exists
if integration_branch_already_exists; then

    # Go to integration branch and perform any work you deem necessary prior to integrating "pulling" the code from the upstream remote (i.e.: $TMP_REMOTE)

    # For example config files for the CI, gitignore, linter configs,
    # etc.
    git checkout ${INTEGRATION_BRANCH_NAME}

    # Because this script was tested in a contrived environment I
    # could not find anything interesting to do, so I'm just deleting
    # the target project path and appending the project name to a text
    # file containing the $PROJECT_NAME
    rm -rf projects/${PROJECT_NAME}
    echo -e "\n${PROJECT_NAME}" >> projects/with-pre-existing-integration-branch.txt

    # Finally, we make a commit with the pre-integration changes.
    git add .
    git commit -am "fix(${PROJECT_NAME}): downstream changes required for migration"
else # Branch does not exist yet, let's create it
    git branch ${INTEGRATION_BRANCH_NAME}

    # This script was originally designed to work only with an
    # existing integration branch, but I've added some placeholder logic
    # here for the sake of illustrating a scenario where it *does not*
    # exist yet.

    # Again, this is a contrived example, so let's just add the $PROJECT_NAME to some file
    echo -e "\n${PROJECT_NAME}" >> projects/without-pre-existing-integration-branch.txt

    # Finally, we make a commit with the pre-integration changes.
    git add .
    git commit -am "fix(${PROJECT_NAME}): downstream changes required for migration"
fi


# Step 8: *Magic Step* -> `--allow-unrelated-histories`
git merge --allow-unrelated-histories ${TMP_REMOTE_NAME}/${UPSTREAMS_MAIN_BRANCH_NAME}
echo -e "The history of ${OWNER_NAME}/${PROJECT_NAME} has been
successfully imported into the monorepo under the integration branch:
${INTEGRATION_BRANCH_NAME}"

# Step 9: Go back to monorepo branch: main
git checkout ${FINAL_MONOREPO_BRANCH_TARGET}

# Step 10: Merge the integration branch into main
git merge ${INTEGRATION_BRANCH_NAME}

# And we're done automating the steps, now we explain the next (manual) steps
echo "Now inspect your history, if everything looks fine, push to github"
echo "so that you can browse the final product and show of to your girlfriends"
# 5. push up that branch that has the new history and take another look at it
# 6. git checkout main \
#      && git merge my-branch-with-the-history-that-we-just-pulled-in \
#      && git push
