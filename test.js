import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';

fs.readdirSync(__dirname)
.filter(filename => filename.endsWith('.sh'))
.forEach(file => {
    exec('shellcheck ' + path.join(__dirname, file), function(err, stdout, stderr) {
        if (null !== err){
            console.error(stderr);
            console.error(stdout);
            process.exit(1);
        }
    });
    console.log(`${file} OK`);
});
