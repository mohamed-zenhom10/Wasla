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

export async function sendCode(email, purpose, code, language = 'ar') {
  const [subject, line] = TEMPLATES[purpose][language === 'en' ? 'en' : 'ar'];
  const footer = language === 'en'
    ? 'The code expires in 10 minutes. If you did not ask for it, ignore this email.'
    : 'الكود صالح لمدة 10 دقايق. لو مطلبتش الكود ده، تجاهل الرسالة.';

  if (!transporter) {
    console.log(`Code for ${email} (${purpose}): ${code}`);
    return;
  }

  try {
    await transporter.sendMail({
      from: config.mail.from,
      to: email,
      subject,
      text: `${line} ${code}\n\n${footer}`,
    });
  } catch (err) {
    console.error('Email failed:', err.message);
    throw new AppError(503, 'EMAIL_FAILED', 'Could not send the email, try again');
  }
}
