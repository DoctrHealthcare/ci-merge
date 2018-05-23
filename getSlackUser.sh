#!/usr/bin/env bash
# Usage
# author=$(./getSlackUser.sh)
# or
# author=$(curl –silent -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)


#Map of emails -> slack user name
getSlackName(){
	 node -e "console.log({
	'allan@878.dk': 'ebdrup',
	'36155117+lopes-d@users.noreply.github.com': 'Diana Lopes',
	'nunodelisboa@gmail.com': 'Nuno Mendes'
}['$1']||'Not found')"
}


email=$(git log --pretty=format:'%ae' -n 1)
if [ "${email}" = 'build@practio.com' ]
then
	echo "TeamCity"
else
	slackUser=$(getSlackName "${email}")
	users=$(curl -X POST "https://slack.com/api/users.list?token=${SLACK_TOKEN}" -s)
	slackUserId=$(node -e "let users =  ${users}; console.log(users.members.reduce((acc,m)=>{ if(m.name==='${slackUser}'||m.profile.email==='${email}'||m.profile.display_name==='${slackUser}||m.profile.real_name==='${slackUser}''){return m.id} return acc;}, ''))")
	slackUser=$(node -e "let users =  ${users}; console.log(users.members.reduce((acc,m)=>{ if(m.name==='${slackUser}'||m.profile.email==='${email}'||m.profile.display_name==='${slackUser}'||m.profile.real_name==='${slackUser}'){return m.name} return acc;}, ''))")
	if [ "${slackUserId}" = '' ]
	then
		echo "${slackUser}|${email} (could not find this slack-username or email in slack?! Fix it here: https://github.com/practio/ci-merge/blob/master/getSlackUser.sh)"
	else
		echo "<@${slackUserId}|${slackUser}>"
	fi
fi
