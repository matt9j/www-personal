#!/bin/sh

# If a command fails then the deploy stops
set -e

if [ "`git status -s`" ]
then
    echo "The working directory is dirty. Please commit any pending changes."
    exit 1;
fi

echo "Get the local state"
sourceref=$(git describe --all --long --dirty)

echo "Local sourceref: $sourceref"

echo "Deleting old publication"
rm -rf public
mkdir public
git worktree prune
rm -rf .git/worktrees/public/

echo "Checking out gh-pages branch into public"
git worktree add -B gh-pages public origin/gh-pages

echo "Removing existing files"
rm -rf public/*

echo "Generating site"
hugo

echo "Synchronize root cname file"
cp CNAME public/CNAME

echo "Updating gh-pages branch"
cd public && git add --all && git commit -m "Publishing to gh-pages from sourceref: $sourceref"

echo "Pushing to github"
git push origin gh-pages
git push origin main
