#!/usr/bin/env bash
# Usage
# author=$(./getSlackUser.sh)
# or
# author=$(curl –silent -L 'https://raw.githubusercontent.com/practio/ci-merge/master/getSlackUser.sh' | bash)


#Map of emails -> slack user name
getSlackName(){
	 node -e "console.log({
	'allan@878.dk': 'ebdrup',
	'36155117+lopes-d@users.noreply.github.com': 'dl',
	'nunodelisboa@gmail.com': 'nuno',
	'mhcservenka@gmail.com': 'martincservenka',
	'sotirovicj@gmail.com': 'Jelena',
	'flaviofernandes004@gmail.com': 'Flávio Fernandes',
	'renato.filipe.vieira@gmail.com': 'Renato',
	'diogo.sim.melo@gmail.com': 'Diogo Simões Melo',
	'negrei.ruslan@gmail.com': 'Ruslan Negrei',
}['$1']||'Not found')"
}

email=$(git log --pretty=format:'%ae' -n 1)
if [ "${email}" = 'build@practio.com' ]
then
	echo "TeamCity"
else
	slackUser=$(getSlackName "${email}")
	users=$(curl -X POST "https://slack.com/api/users.list?token=${SLACK_TOKEN}" -s)
	slackUserId=$(echo "let users =  ${users}; console.log(users.members.reduce((acc,m)=>{ if(m.name==='${slackUser}'||m.profile.email==='${email}'||m.profile.display_name==='${slackUser}'||m.profile.real_name==='${slackUser}'){return m.id} return acc;}, ''))" | node -)
	slackUser=$(echo "let users =  ${users}; console.log(users.members.reduce((acc,m)=>{ if(m.name==='${slackUser}'||m.profile.email==='${email}'||m.profile.display_name==='${slackUser}'||m.profile.real_name==='${slackUser}'){return m.name} return acc;}, ''))" | node -)
	if [ "${slackUserId}" = '' ]
	then
		echo "|${slackUserId}|${slackUser}|${email} (could not find user?! <https://github.com/practio/ci-merge/blob/master/getSlackUser.sh|Fix it here>)"
	else
		echo "<@${slackUserId}|${slackUser}>"
	fi
fi
