#!/bin/bash
#### ENV VARS NEEDED BY THIS SCRIPT
# SLACK_TOKEN       - For posting to slack
# SLACK_CHANNEL_ID  - For posting to slack
# BUILD_URL         - URL to the build on TeamCity, so we can link in slack messages
# COMMIT_URL        - URL to the commit on GitHub. This script will add the commit SHA

################################################
# Deploy to production
###############################################
deploy(){
	step_start "Deploying to production"
	commitMessage=$(git log -1 --pretty=%B)
	deployscript=$(node -e "console.log(require('./package.json').scripts.deploy || '')")
	if [ "$deployscript" = '' ]
	then
		_exit 0 "No npm run deploy script available"
	else
		npm run deploy || _exit $? "npm run deploy failed"
	fi
	slack "Success deploying ${slackProject} ${slackUser}
${commitMessage} - <${COMMIT_URL}${mergeCommitSha}|view commit> " green
}

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

_exit (){
	step_end
	if [ "$1" = '0' ]
	then
		exit
	else
		slack "Failure: $2 ${slackProject} ${slackUser}
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
		curl -sS -X POST "https://slack.com/api/files.upload?token=${SLACK_TOKEN}&filetype=text&filename=${githubProject}.txt&channels=${SLACK_CHANNEL_ID}" -s \
			-F content="$3"
	fi
}

################################################
### START OF SCRIPT - HERE WE GO!
################################################
#npmpath=$(which npm)
#alias npm="node --max_old_space_size=8000 ${npmpath}"

project=$(node -e "console.log(require('./package.json').name || '')")
githubRemote=$(git remote -v | grep origin | grep fetch | grep github)
githubProject=$(node -e "console.log('$githubRemote'.split(':').pop().split('.').shift())")
slackProject="<https://github.com/${githubProject}|${project}>"
slackUser=$(curl -sS -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)
mergeCommitSha=$(git log -1 --format="%H")

################################################
# Check that we are on master branch
################################################

step_start "Checking branch is master"
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" = 'master' ]
then
	echo "Master branch"
else
	echo "Error: Not master branch" >&2
	_exit 1 "Not master branch"
fi

##########################################################
# Check that the committer is Teamcity (from a ready build)
##########################################################

step_start "Checking committer is Teamcity"
committer=$(git log --pretty=format:'%cn' -n 1)
if [ "$committer" = 'Teamcity' ]
then
	echo "Latest commit to master is by Teamcity"
else
	echo "Error: Latest commit to master is NOT by Teamcity" >&2
	_exit 1 "Latest commit to master is NOT by Teamcity"
fi

################################################
# Check that we have not already deployed
################################################

step_start "Checking that latest commit has no tag. If it has a tag it is already deployed"
git fetch --tags || _exit $? "Can not fet git tags"
returnValueWhenGettingTag=$(git describe --exact-match --abbrev=0 2>&1 >/dev/null; echo $?)
if [ "$returnValueWhenGettingTag" = '0' ]
then
	echo "Master already has a tag, it is already deployed. Skipping deploy"
	_exit 0
else
	echo "Master has no tag yet, lets deploy (return value when getting tag: ${returnValueWhenGettingTag})"
fi

build
deploy
_exit 0