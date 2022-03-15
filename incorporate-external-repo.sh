#!/usr/bin/env bash
tput clear
#
# Make sure you have the following tools installed:
# - Git version 2.35 or newer
# - The git-filter-repo tool: brew install git-filter-repo

#########################################################################
# __        ___    ____  _   _ ___ _   _  ____
# \ \      / / \  |  _ \| \ | |_ _| \ | |/ ___|
#  \ \ /\ / / _ \ | |_) |  \| || ||  \| | |  _
#   \ V  V / ___ \|  _ <| |\  || || |\  | |_| |
#    \_/\_/_/   \_\_| \_\_| \_|___|_| \_|\____|
#
# THIS SCRIPT SHOULD BE RUN ONLY DURING A CODE FREEZE!!
#
# MAKE SURE YOU UNDERSTAND EVERYTHING IT DOES BEFORE RUNNING IT
# BECAUSE EVEN THOUGH IT AUTOMATES A LOT OF STUFF AND YOU WILL NEED TO
# INTERVENE MANUALLY IF ANY STEP FAILS
#
# TIP: you might want to change the line below to "set -ex" to have
# bash print every single command
set -e
#########################################################################

#########################################################################
#  ____   ____ ____  ___ ____ _____
# / ___| / ___|  _ \|_ _|  _ \_   _|
# \___ \| |   | |_) || || |_) || |
#  ___) | |___|  _ < | ||  __/ | |
# |____/ \____|_| \_\___|_|    |_|
#  ___ _   _ ____  _   _ _____ ____
# |_ _| \ | |  _ \| | | |_   _/ ___|
#  | ||  \| | |_) | | | | | | \___ \
#  | || |\  |  __/| |_| | | |  ___) |
# |___|_| \_|_|    \___/  |_| |____/

FINALIZE_LOCAL_MERGE_TO_MAIN_INTEGRATION_BRANCH="yes"   # set to "yes"
MAIN_INTEGRATION_BRANCH_NAME="main"  # NOTE: Preferably on something other than the `main` branch, maybe create a "staging" branch...
MONOREPO_PATH="$(pwd)"
TMP_DIR="$(mktemp -d)"

# <upstream project info>
OWNER_NAME="gabrielfalcao"
PROJECT_NAME="lettuce"
UPSTREAMS_MAIN_BRANCH_NAME=master  # this should be "main" for newer github projects or "master" for old ones :/
# </upstream project info>

HISTORY_INTEGRATION_BRANCH_NAME="integrate-${PROJECT_NAME}"
TMP_REMOTE="git@github.com:${OWNER_NAME}/${PROJECT_NAME}-pre-monorepo.git"
TMP_REMOTE_NAME="${PROJECT_NAME}-pre-monorepo"
TMP_CLONE_PATH="${TMP_DIR}/${PROJECT_NAME}"
#########################################################################



#########################################################################
#  _  _ ___ _    ___ ___ ___
# | || | __| |  | _ \ __| _ \
# | __ | _|| |__|  _/ _||   /
# |_||_|___|____|_| |___|_|_\
#  ___ _   _ _  _  ___ _____ ___ ___  _  _ ___
# | __| | | | \| |/ __|_   _|_ _/ _ \| \| / __|
# | _|| |_| | .` | (__  | |  | | (_) | .` \__ \
# |_|  \___/|_|\_|\___| |_| |___\___/|_|\_|___/
function integration_branch_already_exists() {
    git branch --list | grep "[[:space:]]\+\b${HISTORY_INTEGRATION_BRANCH_NAME}\$" > /dev/null
}
function temporary_remote_already_exists_in_monorepo() {
    git remote show | grep "^${TMP_REMOTE_NAME}\$" > /dev/null
}
function determine_push_url_of_git_remote() {
    name="$@"
    git remote show -n "${name}" | grep -i 'push.*url' | awk '{ print $NF }'
}
#########################################################################

#########################################################################
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
#########################################################################


#########################################################################
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
git filter-repo \
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
    --path-rename projects/${PROJECT_NAME}/.github/:.artifacts/${PROJECT_NAME}/.github/

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
    git checkout ${HISTORY_INTEGRATION_BRANCH_NAME}

    # Because this script was tested in a contrived environment I
    # could not find anything interesting to do, so I'm just deleting
    # the target project path and appending the project name to a text
    # file containing the $PROJECT_NAME
    rm -rf projects/${PROJECT_NAME}
    echo -e "\n${PROJECT_NAME}" >> projects-with-pre-existing-integration-branch.txt

    # Finally, we make a commit with the pre-integration changes.
    git add .
    git commit -am "fix(${PROJECT_NAME}): downstream changes required for migration"
else # Branch does not exist yet, let's create it
    git branch ${HISTORY_INTEGRATION_BRANCH_NAME}

    # This script was originally designed to work only with an
    # existing integration branch, but I've added some placeholder logic
    # here for the sake of illustrating a scenario where it *does not*
    # exist yet.

    # Again, this is a contrived example, so let's just add the $PROJECT_NAME to some dummy file
    echo -e "\n${PROJECT_NAME}" >> projects-without-pre-existing-integration-branch.txt

    # Finally, we make a commit with the pre-integration changes.
    git add .
    git commit -am "fix(${PROJECT_NAME}): downstream changes required for migration"
fi


# Step 8: *Magic Step* -> `--allow-unrelated-histories`
git merge --allow-unrelated-histories --no-commit ${TMP_REMOTE_NAME}/${UPSTREAMS_MAIN_BRANCH_NAME}
git commit -am "Migrated ${OWNER_NAME}/${PROJECT_NAME} into the monorepo."
echo -e "The history of ${OWNER_NAME}/${PROJECT_NAME} has been
successfully imported into the monorepo under the integration branch:
${HISTORY_INTEGRATION_BRANCH_NAME}"

# Step 9: Merge the integration branch into the main integration
#         branch of the upstream project in the monorepo
#         (i.e.: $MAIN_INTEGRATION_BRANCH_NAME)
#
if [ "${FINALIZE_LOCAL_MERGE_TO_MAIN_INTEGRATION_BRANCH}" == "yes" ]; then
    git checkout ${MAIN_INTEGRATION_BRANCH_NAME}
    git merge ${HISTORY_INTEGRATION_BRANCH_NAME}
    echo "Hurray! The upstream code has been successfully incorported into the local '${MAIN_INTEGRATION_BRANCH_NAME}' branch."
    echo "Now inspect your history with 'git log' to confirm that it looks good."
    echo "Once that's done, run 'git push'."
else
    echo "Now inspect your history with 'git log' to confirm that the migration worked fine"
    echo "Once that's done, switch to the main branch of the monorepo and run 'git merge'."
    echo
    echo "Here is the exact list of commands:"

    echo "git checkout ${MAIN_INTEGRATION_BRANCH_NAME}"
    echo "git merge ${HISTORY_INTEGRATION_BRANCH_NAME}"
fi
#########################################################################
