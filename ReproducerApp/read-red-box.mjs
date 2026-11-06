// Reads the red box from a uiautomator dump, the file the first argument names, and prints what its title shows: its
// first lines, with this folder's path written as <app>, and how much of Metro's raw answer it shows as text.
// Exits 1 while the red box shows the raw answer (its "Body:", its JSON escapes or its ANSI escape sequences), 0 once it
// shows the answer's message without them, and 2 when there is no red box or it shows another error.
import { readFileSync } from 'node:fs';

const xml = readFileSync(process.argv[2], 'utf8');

const readAttributes = tag =>
  Object.fromEntries(
    [...tag.matchAll(/([\w:-]+)=(?:"([^"]*)"|'([^']*)')/g)].map(
      ([, name, doubleQuoted, singleQuoted]) => [
        name,
        doubleQuoted ?? singleQuoted,
      ],
    ),
  );
const decode = text =>
  text.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, entity) => {
    const named = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
    if (entity[0] !== '#') return named[entity.toLowerCase()];
    return String.fromCodePoint(
      entity[1].toLowerCase() === 'x'
        ? parseInt(entity.slice(2), 16)
        : parseInt(entity.slice(1), 10),
    );
  });

const titleTag = [...xml.matchAll(/<node\s(?:[^>"']|"[^"]*"|'[^']*')*>/g)]
  .map(([tag]) => readAttributes(tag))
  .find(attributes =>
    attributes['resource-id']?.endsWith(':id/catalyst_redbox_title'),
  );
if (!titleTag) {
  console.log('no red box on screen');
  process.exit(2);
}
const appFolder = process.cwd();
const title = decode(titleTag.text ?? '')
  .replaceAll(JSON.stringify(appFolder).slice(1, -1), '<app>')
  .replaceAll(appFolder, '<app>');

const escapeSequences =
  (title.match(/\\u001b\[[0-9;]*m/g) ?? []).length +
  (title.match(/\u001b\[[0-9;]*m/g) ?? []).length;
const showsBody = /^Body:$/m.test(title);
const showsJsonEscapes = /\\n/.test(title);
console.log('the red box shows, in its first lines:');
for (const line of title.split('\n').slice(0, 8)) {
  console.log(`  ${line.length > 160 ? `${line.slice(0, 160)}…` : line}`);
}
console.log(
  `"Body:" ${showsBody ? 'shown' : 'not shown'}; JSON escapes shown as text: ${showsJsonEscapes ? 'yes' : 'no'}; ANSI escape sequences shown as text: ${escapeSequences}`,
);
if (!title.includes('this resolver throws')) {
  console.log("this is not the red box for the resolver's error");
  process.exit(2);
}
process.exit(showsBody || showsJsonEscapes || escapeSequences > 0 ? 1 : 0);
