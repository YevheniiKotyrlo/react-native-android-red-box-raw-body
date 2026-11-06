// Reads Metro's answer to the reproducer's own bundle request — the request (the first argument), the HTTP status curl
// wrote (the second) and the body (the file the third names) — and prints its type and the place it names.
// Exits 0 when Metro answered 500 with an InternalError that names no file, line and column, the answer whose red box
// this reproducer reads, and 2 for any other answer or none.
import { readFileSync } from 'node:fs';

const [request, status, bodyFile] = process.argv.slice(2);
const describePlace = value =>
  value === undefined ? 'none' : JSON.stringify(value);

const judge = () => {
  if (status === '000') {
    console.log(`GET ${request} -> no answer`);
    return 2;
  }
  if (status !== '500') {
    console.log(`GET ${request} -> ${status}, not 500`);
    return 2;
  }
  const text = readFileSync(bodyFile, 'utf8');
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    console.log(
      `GET ${request} -> 500, a body that is not JSON: ${text.slice(0, 120)}`,
    );
    return 2;
  }
  console.log(
    `GET ${request} -> 500: type ${body.type}, filename ${describePlace(
      body.filename,
    )}, lineNumber ${describePlace(body.lineNumber)}, column ${describePlace(
      body.column,
    )}`,
  );
  const namesPlace = ['filename', 'lineNumber', 'column'].some(
    field => body[field] !== undefined,
  );
  if (body.type !== 'InternalError' || namesPlace) {
    console.log(
      'this is not the InternalError without a place whose red box this reproducer reads',
    );
    return 2;
  }
  return 0;
};

let verdict;
try {
  verdict = judge();
} catch (error) {
  console.log(`the answer could not be read: ${error.message}`);
  verdict = 2;
}
process.exit(verdict);
