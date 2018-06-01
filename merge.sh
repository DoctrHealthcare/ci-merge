#!/bin/bash
#### ENV VARS NEEDED BY THIS SCRIPT
# BRANCH            - The current ready branch (set by TeamCity)
# SLACK_TOKEN       - For posting to slack
# SLACK_CHANNEL_ID  - For posting to slack
# BUILD_URL         - URL to the build on TeamCity, so we can link in slack messages
# COMMIT_URL        - URL to the commit on GitHub. This script will add the commit SHA


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
# Deploy to production
###############################################
deploy(){
	step_start "Deploying to production"
	commitMessage=$(git log -1 --pretty=%B)
	lastCommitAuthor=$(git log --pretty=format:'%an' -n 1)
	deployscript=$(node -e "console.log(require('./package.json').scripts.deploy || '')")
	if [ "$deployscript" = '' ]
	then
		_exit 0 "No npm run deploy script available"
	else
		npm run deploy || _exit $? "npm run deploy failed"
	fi
	slack "Success deploying <https://github.com/practio/${project}|${project}> ${slackUser} ${pullRequestLink}
${commitMessage} - <${COMMIT_URL}${mergeCommitSha}|view commit> - <${BUILD_URL}|view build log>" green

	################################################
	# Add git tag and push to GitHub
	################################################

	step_start "Adding git tag and pushing to GitHub"
	git config user.email "build@practio.com" || _exit $? "Could not set git user.email"
	git config user.name "Teamcity" || _exit $? "Could not set git user.name"
	datetime=$(date +%Y-%m-%d_%H-%M-%S)
	git tag -a "${project}.production.${datetime}" -m "${commitMessage}" || _exit $? "Could not create git tag"
	git push origin --tags || _exit $? "Could not push git tag to GitHub"
}

################################################
# Delete Ready branch
# Always last thing done after merge (fail or success)
################################################
build_done (){
	step_start "Deleting ready branch on github"
	git push origin ":ready/${BRANCH}"
	step_start "Post to slack"
	if [ "$1" = '0' ]
	then
		if [ "$2" != '' ]
		then
			slack "Warning merging: $2 <https://github.com/practio/${project}|${project}> ${slackUser} ${pullRequestLink}
${commitMessage} - <${BUILD_URL}|view build log> " yellow
			message="$2
${project} ${slackUser}
${BUILD_URL}
${commitMessage}"
		else
			slack "Success merging: <https://github.com/practio/${project}|${project}> ${slackUser} ${pullRequestLink}
${commitMessage} - <${COMMIT_URL}${mergeCommitSha}|view commit> - <${BUILD_URL}|view build log>" green
			message="Success merging ${project}
${slackUser}
${COMMIT_URL}${mergeCommitSha}
${commitMessage}"
			deploy
			_exit 0
		fi
	else
		slack "Failure merging: $2 <https://github.com/practio/${project}|${project}> ${slackUser} ${pullRequestLink}
${commitMessage} - <${BUILD_URL}|view build log> " red "$3"
		message="Failure merging: $2
${project} ${slackUser}
${BUILD_URL}
${commitMessage}
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
		slack "Failure: $2 <https://github.com/practio/${project}|${project}> ${slackUser}
${commitMessage} - <${BUILD_URL}|view build log> " red
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

if [ "$BRANCH" = 'refs/heads/master' ]
then
	echo "master branch, doing nothing"
	exit 0
fi

pullRequestLink=""
project=$(node -e "console.log(require('./package.json').name || '')")
slackUser=$(curl -sS -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)
commitMessage="${BRANCH}"
git config user.email "build@practio.com" || build_done $? "Could not set git email"
git config user.name "Teamcity" || build_done $? "Could not set git user name"

step_start "Finding author"

lastCommitAuthor=$(git log --pretty=format:'%an' -n 1)

echo "This will be the author of the merge commit in master: ${lastCommitAuthor} (the last commit in branch was done by this person)"

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

########################################################################################
# Lookup PR number
# By looking the SHA checksum of the current branchs latests commit
# And finding a pull request that has a matching SHA checksum as the lastest commit
# This enforces a restriction that you can only merge branches that match a pull request
# And using the number of the pull request later, we can close the pull request
# by making the squash merge commit message include "fixes #[pull request number] ..."
########################################################################################

step_start "Finding pull request that matches current branch"

currentSha=$(git log -1 --format="%H")
echo "Current SHA:"
echo "${currentSha}"


error='
Did you try to deploy a branch that is not a pull request?
Or did you forget to push your changes to github?'

matchingPullRequest=$(git show-ref | grep "$currentSha" | grep 'refs/remotes/origin/pullrequest/')
if [ "$matchingPullRequest" = '' ] ; then
	echo "Error finding matching pull request: ${error}" >&2; build_done 1 "Could not find matching pull request"
fi
echo "Matching pull request:"
echo "${matchingPullRequest}"

pullRequestNumber=$(echo "${matchingPullRequest}" | sed 's/[0-9a-z]* refs\/remotes\/origin\/pullrequest\///g' | sed 's/\s//g')
echo "Extracted pull request number:"
echo "${pullRequestNumber}"
case ${pullRequestNumber} in
	''|*[!0-9]*) echo "Error pull request number does not match number regExp (weird!): ${error}" >&2; build_done 1 "Could not find pull request number";;
	*) echo "Success. Pull request number passes regExp test for number. Exporting pullRequestNumber=${pullRequestNumber}" ;;
esac
pullRequestLink="<https://github.com/practio/${project}/pull/${pullRequestNumber}|PR#${pullRequestNumber}>"

#####################################################################
# Checkout master
# Cleanup any leftovers for previous failed merges (reset --hard, clean -fx)
# And pull master
#####################################################################

step_start "Checking out master, resetting (hard), pulling from origin and cleaning"

git checkout master || build_done $? "Could not checkout master"
git branch --set-upstream-to=origin/master master || build_done $? "Could not set upstream for master to origin/master"
git reset --hard origin/master || build_done $? "Could not reset to master"
git pull || build_done $? "Could not pull master"
git clean -fx || build_done $? "Could not git clean on master"


################################################
# Merge into master
# You will want to use you own email here
################################################

step_start "Merging ready branch into master, with commit message that closes pull request number ${pullRequestNumber}"

message_on_commit_error(){
	commitErrorCode=$1
	echo "Commiting changes returned an error (status: ${commitErrorCode}). We are assuming that this is due to no changes, and exiting gracefully"
	build_done 0 "No changes in ready build"
}

git merge --squash "ready/${BRANCH}" || build_done $? "Merge conflicts (could not merge)"
branchWithUnderscore2SpacesAndRemovedTimestamp=$(echo "${BRANCH}" | sed -e 's/_/ /g' | sed -e 's/\/[0-9]*s$//g')
if [ "$pullRequestNumber" = 'none' ]
then
	commitMessage="${branchWithUnderscore2SpacesAndRemovedTimestamp}"
else
	commitMessage="fixes #${pullRequestNumber} - ${branchWithUnderscore2SpacesAndRemovedTimestamp}"
fi
echo "Committing squashed merge with message: \"${message}\""
git commit -m "${commitMessage}" --author "${lastCommitAuthor}" || message_on_commit_error $?


mergeCommitSha=$(git log -1 --format="%H")


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
# Build
################################################

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

################################################
# Push changes to github
################################################

step_start "Pushing changes to github master branch"

git push origin master || build_done $? "Could not push changes to GitHub"

build_done 0
