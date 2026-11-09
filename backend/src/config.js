const required = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD', 'JWT_SECRET', 'NATIONAL_ID_KEY'];
const missing = required.filter((key) => !process.env[key]);

if (missing.length > 0) {
  console.error(`Missing environment variables: ${missing.join(', ')}`);
  process.exit(1);
}

if (process.env.JWT_SECRET.length < 32) {
  console.error('JWT_SECRET must be at least 32 characters');
  process.exit(1);
}

if (process.env.NATIONAL_ID_KEY.length < 32) {
  console.error('NATIONAL_ID_KEY must be at least 32 characters');
  process.exit(1);
}

function readCloudinary(value) {
  if (!value) {
    return null;
  }
  try {
    const url = new URL(value);
    if (url.protocol !== 'cloudinary:' || !url.username || !url.password || !url.hostname) {
      throw new Error('bad');
    }
    return {
      cloudName: url.hostname,
      apiKey: decodeURIComponent(url.username),
      apiSecret: decodeURIComponent(url.password),
    };
  } catch {
    console.error('CLOUDINARY_URL must look like cloudinary://<api_key>:<api_secret>@<cloud_name>');
    process.exit(1);
  }
}

const cloudinary = readCloudinary(process.env.CLOUDINARY_URL);
if (process.env.NODE_ENV === 'production' && !cloudinary) {
  console.error('CLOUDINARY_URL is needed in production, photos cannot be saved on the server');
  process.exit(1);
}

if (process.env.BREVO_API_KEY && !process.env.MAIL_FROM) {
  console.error('MAIL_FROM is needed when BREVO_API_KEY is set');
  process.exit(1);
}

const config = {
  env: process.env.NODE_ENV || 'development',
  port: Number(process.env.PORT) || 3000,
  db: {
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: true } : false,
  },
  trustProxy: process.env.TRUST_PROXY === 'true',
  clientIpHeader: process.env.CLIENT_IP_HEADER,
  corsOrigins: (process.env.CORS_ORIGINS || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  jwtSecret: process.env.JWT_SECRET,
  nationalIdKey: process.env.NATIONAL_ID_KEY,
  cloudinary,
  mail: {
    host: process.env.SMTP_HOST,
    port: Number(process.env.SMTP_PORT) || 587,
    user: process.env.SMTP_USER,
    password: process.env.SMTP_PASSWORD,
    from: process.env.MAIL_FROM || process.env.SMTP_USER,
    brevoKey: process.env.BREVO_API_KEY,
  },
};

export default config;
