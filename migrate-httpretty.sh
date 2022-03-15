#!/usr/bin/env bash


git filter-repo \
	--commit-callback '
    commit.message = re.sub(
        b"\(\#([0-9]+)\)",
        lambda m: b"(gabrielfalcao/HTTPretty#%b)" % m.group(1),
        commit.message
    )
    commit.message += (b"\nMigrated to gabrielfalcao/test-monorepo-1 from gabrielfalcao/HTTPretty@%s"
        % commit.original_id[0:7])
    ' \
    --path-rename :projects/HTTPretty/ \
    --path-rename projects/HTTPretty/.github/:.artifacts/HTTPretty/.github/
