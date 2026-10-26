import readline from 'node:readline';
import bcrypt from 'bcryptjs';
import { pool, withTransaction } from '../src/db.js';
import { cleanEmail, cleanName, cleanPassword, cleanPhone } from '../src/lib/validate.js';

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const lines = rl[Symbol.asyncIterator]();

async function ask(question) {
  process.stdout.write(question);
  const { value } = await lines.next();
  return value || '';
}

try {
  const fullName = cleanName(await ask('Full name: '));
  const email = cleanEmail(await ask('Email: '));
  const phone = cleanPhone(await ask('Phone (+20...): '));
  const password = cleanPassword(await ask('Password: '));
  const passwordHash = await bcrypt.hash(password, 10);

  const id = await withTransaction(null, async (client) => {
    const { rows: [user] } = await client.query(
      `INSERT INTO users (full_name, email, phone, password_hash, email_verified_at)
       VALUES ($1, $2, $3, $4, now())
       RETURNING id`,
      [fullName, email, phone, passwordHash],
    );
    await client.query(
      "INSERT INTO user_roles (user_id, role_id) SELECT $1, id FROM roles WHERE code = 'admin'",
      [user.id],
    );
    return user.id;
  });

  console.log(`\nAdmin created with id ${id}`);
} catch (err) {
  process.exitCode = 1;
  console.error(`\nCould not create admin: ${err.message}`);
} finally {
  rl.close();
  await pool.end();
}
