# ci-merge

Bash scripts for the CI server

## Contributing

You need to do `brew install shellcheck` to be able to run `npm test` to test all the shell scripts.

## Scripts

- `merge.sh` Is used in ready builds to merge to master, run tests and deploy.
- `deploy-only.sh` Is used when the merge to master completed sucessfully, but the deploy to production failed, and you just want to re-run the deploy part
- `pull-request.sh` Is used on pull request builds, to merge to master and run tests
- `getSlackUser.sh` Is a utility function to get the slack user of the author of the commit