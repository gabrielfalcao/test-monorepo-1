#!/usr/bin/env bash


git filter-repo \
	--commit-callback '
    commit.message = re.sub(
        b"\(\#([0-9]+)\)",
        lambda m: b"(gabrielfalcao/lettuce#%b)" % m.group(1),
        commit.message
    )
    commit.message += (b"\nMigrated to gabrielfalcao/test-monorepo-1 from gabrielfalcao/lettuce@%s"
        % commit.original_id[0:7])
    ' \
    --path-rename :projects/lettuce/ \
    --path-rename projects/lettuce/.github/:.artifacts/lettuce/.github/
