import nodemailer from 'nodemailer';
import config from '../config.js';
import { AppError } from '../errors.js';

const transporter = config.mail.host
  ? nodemailer.createTransport({
      host: config.mail.host,
      port: config.mail.port,
      secure: config.mail.port === 465,
      auth: { user: config.mail.user, pass: config.mail.password },
    })
  : null;

const TEMPLATES = {
  verify_email: {
    ar: ['كود تأكيد الإيميل', 'كود تأكيد حسابك في وصلة هو'],
    en: ['Your verification code', 'Your Wasla verification code is'],
  },
  reset_password: {
    ar: ['كود تغيير الباسورد', 'كود تغيير الباسورد في وصلة هو'],
    en: ['Your password reset code', 'Your Wasla password reset code is'],
  },
};

function parseSender(from) {
  const match = /^\s*(.*?)\s*<([^>]+)>\s*$/.exec(from || '');
  return match ? { name: match[1] || undefined, email: match[2] } : { email: from };
}

async function sendWithBrevo(to, subject, text, html) {
  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': config.mail.brevoKey,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify({
      sender: parseSender(config.mail.from),
      to: [{ email: to }],
      subject,
      textContent: text,
      htmlContent: html,
    }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) {
    throw new Error(`Brevo answered ${res.status}: ${await res.text()}`);
  }
}

export async function sendCode(email, purpose, code, language = 'ar') {
  const [subject, line] = TEMPLATES[purpose][language === 'en' ? 'en' : 'ar'];
  const footer = language === 'en'
    ? 'The code expires in 10 minutes. If you did not ask for it, ignore this email.'
    : 'الكود صالح لمدة 10 دقايق. لو مطلبتش الكود ده، تجاهل الرسالة.';
  const text = `${line} ${code}\n\n${footer}`;
  const dir = language === 'en' ? 'ltr' : 'rtl';
  const html = `<div dir="${dir}"><p>${line} <b>${code}</b></p><p>${footer}</p></div>`;

  if (!config.mail.brevoKey && !transporter) {
    console.log(`Code for ${email} (${purpose}): ${code}`);
    return;
  }

  try {
    if (config.mail.brevoKey) {
      await sendWithBrevo(email, subject, text, html);
    } else {
      await transporter.sendMail({ from: config.mail.from, to: email, subject, text, html });
    }
  } catch (err) {
    console.error('Email failed:', err.message);
    throw new AppError(503, 'EMAIL_FAILED', 'Could not send the email, try again');
  }
}
