import { exec } from 'child_process';
import fs from 'fs';
import path from 'path';
const __dirname = path.dirname(new URL(import.meta.url).pathname);
fs.readdirSync(__dirname)
.filter(filename => filename.endsWith('.sh'))
.forEach(file => {
    exec('shellcheck ' + path.join(__dirname, file), function(err, stdout, stderr) {
        if (null !== err){
            console.log(`${file}\t❌ ERROR`);
            console.error(stderr);
            console.error(stdout);
            process.exit(1);
        }
    });
    console.log(`${file}\t✅ OK`);
});
