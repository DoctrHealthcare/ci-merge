#!/bin/bash
#### ENV VARS NEEDED BY THIS SCRIPT
# BRANCH            - The current ready branch (set by TeamCity)
# SLACK_TOKEN       - For posting to slack
# SLACK_CHANNEL_ID  - For posting to slack
# BUILD_URL         - URL to the build on TeamCity, so we can link in slack messages

################################################
# Build
###############################################
build(){
	step_start "Building"
	buildscript=$(node -e "console.log(require('./package.json').scripts.build || '')")
	if [ "$buildscript" = '' ]
	then
		echo "No npm run build script available"
	else
		npm run build || _exit $? "npm run build failed"
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
			slack "Pull-Request Warning ${BRANCH}
			$2 ${project} ${slackUser}
 - <${BUILD_URL}|view build log> " yellow
			message="Pull-Request Warning $2
${BRANCH}
${project} ${slackUser}
${BUILD_URL}"
		else
			slack "Pull Request Success ${BRANCH}
			${project} ${slackUser}
- <${BUILD_URL}|view build log> " green
			message="Pull Request Success ${BRANCH}
${project}
${slackUser}
"
			_exit 0
		fi
	else
		slack "Pull Request failure: ${BRANCH}
		$2 ${project} ${slackUser}
- <${BUILD_URL}|view build log> " red "$3"
		message="Pull Request failure: $2
${BRANCH}
${project} ${slackUser}
${BUILD_URL}
$3"
	fi
	step_end
	echo "
${message}"
	reset_npm
	exit "$1"
}

################################################
# Temporary reset of npm to 4.2.0 until we get all builds on ready builds
################################################
reset_npm (){
	npmSpecified="4.2.0"
	npmCurrent=$(npm --version)
	if [ "${npmSpecified}" != "${npmCurrent}" ]
	then
		step_start "Changing npm v${npmCurrent}->v${npmSpecified}"
		sudo npm install -g "npm@${npmSpecified}" || slack "WARNING: Could not reset npm to v 4.2.0" red
	fi
}

_exit (){
	step_end
	reset_npm
	if [ "$1" = '0' ]
	then
		exit
	else
		slack "Pull Request Failure: ${BRANCH}
		$2 ${project} ${slackUser}
 - <${BUILD_URL}|view build log> " red
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
		curl -sS -X POST "https://slack.com/api/files.upload?token=${SLACK_TOKEN}&filetype=text&filename=${project}.txt&channels=${SLACK_CHANNEL_ID}" -s \
			-F content="$3"
	fi
}



################################################
### START OF SCRIPT - HERE WE GO!
################################################
#npmpath=$(which npm)
#alias npm="node --max_old_space_size=8000 ${npmpath}"

project=$(node -e "console.log(require('./package.json').name || '')")
slackUser=$(curl -sS -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)
git config user.email "build@practio.com" || build_done $? "Could not set git email"
git config user.name "Teamcity" || build_done $? "Could not set git user name"

step_start "Finding author"

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard, clean -fx)
# And pull master
#####################################################################

step_start "Checking out master, resetting (hard), pulling from origin and cleaning"

git checkout master || build_done $? "Could not checkout master"
git reset --hard origin/master || build_done $? "Could not reset to master"
git pull || build_done $? "Could not pull master"
git clean -fx || build_done $? "Could not git clean on master"


################################################
# Merge into master
# You will want to use you own email here
################################################

step_start "Merging ready branch into master"

git merge --squash "${BRANCH}" || build_done $? "Merge conflicts (could not merge with master)"

################################################
# Check node.js version
################################################
nodeSpecified=$(node -e "console.log(require('./package.json').engines.node || '')")
nodeCurrent=$(node --version | sed -e 's/v//g')
if [ "${nodeSpecified}" != "${nodeCurrent}" ]
then
	step_start "Changing node.js v${nodeCurrent}->v${nodeSpecified}"
	if [ ! -f "$HOME/.nvm/nvm.sh" ]; then
		(curl -sS -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash) || build_done 1 "Could not install nvm to change node version from ${nodeCurrent} to ${nodeSpecified}"
	fi
	(source "$HOME/.nvm/nvm.sh" && nvm install "${nodeSpecified}") || build_done 1 "Nvm failed to change node version from ${nodeCurrent} to ${nodeSpecified}"
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
# Build
################################################

build

################################################
# Run tests, and capture output to stderr
################################################

step_start "Running tests with >npm run teamcity "

## file descriptor 5 is stdout
exec 5>&1
## redirect stderr to stdout for capture by tee, and redirect stdout to file descriptor 5 for output on stdout (with no capture by tee)
## after capture of stderr on stdout by tee, redirect back to stderr
npm run teamcity 2>&1 1>&5 | tee err.log 1>&2

## get exit code of "npm run teamcity"
code="${PIPESTATUS[0]}"
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