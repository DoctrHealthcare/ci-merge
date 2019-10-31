#!/bin/bash
#### ENV VARS NEEDED BY THIS SCRIPT
# BRANCH            - The current ready branch (set by TeamCity)
# SLACK_TOKEN       - For posting to slack
# SLACK_CHANNEL_ID  - For posting to slack
# BUILD_URL         - URL to the build on TeamCity, so we can link in slack messages

################################################
# Install dependencies
###############################################
teamcityinstall(){
	step_start "Installing dependencies"
	teamcityinstallscript=$(node -e "console.log(require('./package.json').scripts.teamcity-install || '')")
	if [ "$teamcityinstallscript" = '' ]
	then
		echo "No npm teamcity-install script available"
	else
		add_npm_token || _exit $? "Adding NPM_TOKEN env var to .npmrc failed"
		npm run teamcity-install || _exit $? "npm run teamcity-install failed"
		remove_npm_token || _exit $? "Removing NPM_TOKEN env var from .npmrc failed"
	fi
}

################################################
# Build
###############################################
prebuild(){
	step_start "Prebuilding"
	prebuildscript=$(node -e "console.log(require('./package.json').scripts.prebuild || '')")
	if [ "$prebuildscript" = '' ]
	then
		echo "No npm run prebuild script available"
	else
		add_npm_token || _exit $? "Adding NPM_TOKEN env var to .npmrc failed"
		npm run prebuild || _exit $? "npm run prebuild failed"
		remove_npm_token || _exit $? "Removing NPM_TOKEN env var from .npmrc failed"
	fi
}

build (){
	step_start "Building"
	buildscript=$(node -e "console.log(require('./package.json').scripts.build || '')")
	if [ "$buildscript" = '' ]
	then
		echo "No npm run build script available"
	else
		add_npm_token || _exit $? "Adding NPM_TOKEN env var to .npmrc failed"
		npm run build || _exit $? "npm run build failed"
		remove_npm_token || _exit $? "Removing NPM_TOKEN env var from .npmrc failed"
	fi
}

add_npm_token(){
	if [ -n "$NPM_TOKEN" ]; then
		if [ -f .npmrc ]; then
			mv .npmrc .npmrc-backup
		fi
		# shellcheck disable=SC2016
		if [ -f .npmrc ]; then
			echo '//registry.npmjs.org/:_authToken=${NPM_TOKEN}' | cat - .npmrc-backup >  .npmrc
		else
			echo '//registry.npmjs.org/:_authToken=${NPM_TOKEN}' > .npmrc
		fi

		# if it is a monorepo, add the .npmrc to each subdir
		if [ -d packages ];
			then for subdir in packages/*; do
				cp .npmrc "$subdir"/.npmrc
			done
		fi
	fi
}

remove_npm_token(){
	if [ -n "$NPM_TOKEN" ]; then
		rm .npmrc
		if [ -f .npmrc-backup ]; then
    		mv .npmrc-backup .npmrc
		fi

		# if it is a monorepo, remove the .npmrc from each subdir
		if [ -d packages ];
			then for subdir in packages/*; do
				rm "$subdir"/.npmrc
			done
		fi
	fi
}

################################################
# Build done(fail or success)
################################################
build_done (){
	step_start "Post to slack"
	if [ "$1" = '0' ]
	then
		if [ "$2" != '' ]
		then
			slack "Pull-Request Warning: ${slackPR} $2 ${slackProject} ${slackUser} - <${BUILD_URL}|view build log> " yellow
			message="Pull-Request Warning $2
${BRANCH}
${project} ${slackUser}
${BUILD_URL}"
		else
			slack "Pull Request Success: ${slackPR} ${slackProject} ${slackUser} - <${BUILD_URL}|view build log> " green
			message="Pull Request Success ${BRANCH}
${project}
${slackUser}
"
			_exit 0
		fi
	else
		slack "Pull Request failure: ${slackPR} $2 ${slackProject} ${slackUser} - <${BUILD_URL}|view build log> " red "$3"
		message="Pull Request failure: $2
${BRANCH}
${project} ${slackUser}
${BUILD_URL}
$3"
	fi
	step_end
	echo "
${message}"
	exit "$1"
}

################################################
# Exit with slack output
################################################
_exit (){
	step_end
	if [ "$1" = '0' ]
	then
		exit
	else
		slack "Pull Request failure: ${slackPR} $2 ${slackProject} ${slackUser} - <${BUILD_URL}|view build log> " red "$3"
		exit "$1"
	fi
}

################################################
# TeamCity step helper functions
################################################
stepName=""
step_end(){
	echo "##teamcity[blockClosed name='${stepName}']"
}
step_start(){
	if [ "${stepName}" != '' ]
	then
		step_end
	fi
	stepName=$(echo "-- $1 --")
	echo "##teamcity[blockOpened name='${stepName}']"
}

################################################
# Posting messages to slack
################################################
slack(){
	if [ "$2" = 'green' ]
	then
		symbol="✅"
	elif [ "$2" = 'yellow' ]
	then
		symbol="❗"
	elif [ "$2" = 'red' ]
	then
		symbol="❌"
	fi
	curl -sS -X POST \
		"https://slack.com/api/chat.postMessage?token=${SLACK_TOKEN}&channel=${SLACK_CHANNEL_ID}" \
		--data-urlencode "text=$symbol $1" \
		-s > /dev/null
	if [ "$3" != '' ]
	then
		step_start "Post error log to slack"
		curl -sS -X POST "https://slack.com/api/files.upload?token=${SLACK_TOKEN}&filetype=text&filename=${githubProject}.txt&channels=${SLACK_CHANNEL_ID}" -s \
			-F content="$3"
	fi
}

### After teamcity script
after_teamcity_script(){
  ## get exit code of "npm run teamcity"
  code="$1"
  err=$(node -e "
  const fs = require('fs');
  const path = require('path');
  let log = fs.readFileSync(path.join(__dirname, 'err.log'), 'utf-8')
    .split('\\n')
    .filter(line => !/^npm (ERR|WARN)/.test(line))
    .join('\\n')
    .replace(/\\|n/g, '\\n');
  console.log(log);
  " && rm -f err.log)

  if [ "${code}" != 0 ]
  then
    build_done "${code}" "Failing test(s)"	"${err}"
  fi
  build_done 0
}


################################################
### START OF SCRIPT - HERE WE GO!
################################################
#npmpath=$(which npm)
#alias npm="node --max_old_space_size=8000 ${npmpath}"
if [ "$BRANCH" = 'refs/heads/master' ]
then
	echo "master branch, doing nothing"
	exit 0
fi
BRANCH=${BRANCH#"pull/"} ## remove "pull/" prefix
project=$(node -e "console.log(require('./package.json').name || '')")
githubRemote=$(git remote -v | grep origin | grep fetch | grep github)
githubProject=$(node -e "console.log('$githubRemote'.split(':').pop().split('.').shift())")
slackProject="<https://github.com/${githubProject}|${project}>"
slackPR="<https://github.com/${githubProject}/pull/${BRANCH}|PR#${BRANCH}>"
slackUser=$(curl -sS -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)
git config user.email "build@practio.com" || build_done $? "Could not set git email"
git config user.name "Teamcity" || build_done $? "Could not set git user name"

################################################
# Make sure git fetches (hidden) Pull Requests
# by adding:
# fetch = +refs/pull/*/head:refs/remotes/origin/pullrequest/*
# to .git/config under the origin remote
################################################

step_start "Ensuring fetch of pull requests to .git/config"

currentFetch=$(grep '	fetch =.\+refs/pull/\*/head:refs/remotes/origin/pullrequest/\*' .git/config)
if [ "$currentFetch" = '' ]
then
	# Avoid -i flag for sed, because of platform differences
	sed 's/\[remote \"origin\"\]/[remote "origin"]'\
'	fetch = +refs\/pull\/*\/head:refs\/remotes\/origin\/pullrequest\/*/g' .git/config >.git/config_with_pull_request || build_done $? "Could not sed .git/config"
	cp .git/config .git/config.backup || build_done $? "Could not copy .git/config"
	mv .git/config_with_pull_request .git/config || build_done $? "Could not mv .git/config"
	echo 'Added fetch of pull request to .git/config:'
	cat .git/config
else
	echo 'Fetch of pull request already in place in .git/config'
fi
git fetch --prune || build_done $? "Could not git fetch"

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard, clean -fx)
# And pull master
#####################################################################

step_start "Checking out master, resetting (hard), pulling from origin and cleaning"

git checkout master || build_done $? "Could not checkout master. Try to merge master into your Pull Request-branch and solve any merge conflicts"
git branch --set-upstream-to=origin/master master || build_done $? "Could not set upstream for master to origin/master"
git reset --hard origin/master || build_done $? "Could not reset to master"
git pull || build_done $? "Could not pull master"
git clean -fx || build_done $? "Could not git clean on master"


################################################
# Merge into master
# You will want to use you own email here
################################################

step_start "Merging ready branch into master"

echo "BRANCH: ${BRANCH}"

git merge --squash "origin/pullrequest/${BRANCH}" || build_done $? "Merge conflicts (could not merge with master)"

################################################
# Check node.js version
################################################
nodeSpecified=$(node -e "console.log(require('./package.json').engines.node || '')")
nodeCurrent=$(node --version | sed -e 's/v//g')
if [ "${nodeSpecified}" != "${nodeCurrent}" ]
then
	step_start "Changing node.js v${nodeCurrent}->v${nodeSpecified}"
	sudo npm install -g n || build_done 1 "Could not install n module to change node version from ${nodeCurrent} to ${nodeSpecified}"
	sudo n "${nodeSpecified}" || build_done 1 "n module failed to change node version from ${nodeCurrent} to ${nodeSpecified}"
	echo "Running node.js:"
	node --version
fi

################################################
# Check npm version
################################################
npmSpecified=$(node -e "console.log(require('./package.json').engines.npm || '')")
npmCurrent=$(npm --version)
if [ "${npmSpecified}" != "${npmCurrent}" ]
then
	step_start "Changing npm v${npmCurrent}->v${npmSpecified}"
	sudo npm install -g "npm@${npmSpecified}" || build_done 1 "Could not install npm version ${npmSpecified}. Changing from current npm version ${npmCurrent}"
fi

################################################
# Install dependencies
################################################

teamcityinstall

################################################
# Build
################################################

prebuild
build

################################################
# Run tests, and capture output to stderr
################################################

step_start "Running tests with >npm run teamcity "
teamcityscript=$(node -e "console.log(require('./package.json').scripts.teamcity || '')")
if [ "$teamcityscript" = '' ]
then
	build_done 1 "No 'teamcity' script in package.json"
fi

## file descriptor 5 is stdout
exec 5>&1
## redirect stderr to stdout for capture by tee, and redirect stdout to file descriptor 5 for output on stdout (with no capture by tee)
## after capture of stderr on stdout by tee, redirect back to stderr
npm run teamcity 2>&1 1>&5 | tee err.log 1>&2
exit_code=${PIPESTATUS[0]}

## Executes e2e tests
## In the end the server process gets killed
## which causes this main process to die too
## To avoid that, we run e2e tests in a different process
## and wait for it to finish
teamcity_e2e_script=$(node -e "console.log(require('./package.json').scripts['teamcity:e2e'] || '')")
if [ "$exit_code" == "0" ] && [ "$teamcity_e2e_script" != '' ]
then
  npm run teamcity:e2e &
  proc=$!
  wait $proc
  exit_code=${PIPESTATUS[0]}
fi

after_teamcity_script "$exit_code"
