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
<<<<<<< HEAD
=======

const DOCUMENT_NAMES = {
  profile_photo: ['الصورة الشخصية', 'profile photo'],
  national_id_front: ['وش البطاقة', 'national ID front'],
  national_id_back: ['ضهر البطاقة', 'national ID back'],
  driving_license_front: ['وش رخصة القيادة', 'driving license front'],
  driving_license_back: ['ضهر رخصة القيادة', 'driving license back'],
  vehicle_license_front: ['وش رخصة العربية', 'vehicle license front'],
  vehicle_license_back: ['ضهر رخصة العربية', 'vehicle license back'],
  vehicle_photo_front: ['صورة العربية من قدام', 'vehicle front photo'],
  vehicle_photo_side: ['صورة العربية من الجنب', 'vehicle side photo'],
  vehicle_photo_rear: ['صورة العربية من ورا', 'vehicle rear photo'],
  vehicle_photo_cargo: ['صورة صندوق العربية', 'cargo area photo'],
};

const REJECTION_TEXT = {
  blurry: ['الصورة مش واضحة', 'the photo is not clear'],
  expiry_unreadable: ['تاريخ الانتهاء مش باين', 'the expiry date cannot be read'],
  expired: ['المستند منتهي', 'the document is expired'],
  name_mismatch: ['الاسم مش مطابق', 'the name does not match'],
  wrong_document: ['ده مش المستند المطلوب', 'this is not the right document'],
  invalid_account: ['رقم الحساب مش صحيح', 'the account number is not valid'],
  unsupported_bank: ['البنك ده مش مدعوم', 'this bank is not supported'],
  other: ['سبب تاني', 'another reason'],
};

const NOTICES = {
  driver_approved: {
    ar: () => [
      'طلبك اتقبل',
      'مبروك، طلبك كسواق في وصلة اتقبل. تقدر تبدأ تستقبل طلبات من التطبيق.',
    ],
    en: () => [
      'Your application was approved',
      'Your Wasla driver application was approved. You can start receiving requests in the app.',
    ],
  },
  driver_rejected: {
    ar: (p) => ['طلبك اترفض', `للأسف طلبك كسواق في وصلة اترفض. السبب: ${p.reason}`],
    en: (p) => ['Your application was not approved', `Your Wasla driver application was not approved. Reason: ${p.reason}`],
  },
  document_rejected: {
    ar: (p) => [
      `محتاجين صورة جديدة: ${DOCUMENT_NAMES[p.type][0]}`,
      `مقدرناش نقبل ${DOCUMENT_NAMES[p.type][0]} لأن ${REJECTION_TEXT[p.code][0]}. ${p.reason}\n`
        + 'ارفع صورة جديدة من التطبيق، وباقي طلبك محفوظ.',
    ],
    en: (p) => [
      `Please upload a new ${DOCUMENT_NAMES[p.type][1]}`,
      `Your ${DOCUMENT_NAMES[p.type][1]} was rejected because ${REJECTION_TEXT[p.code][1]}. ${p.reason}\n`
        + 'Upload a new photo in the app, the rest of your application is saved.',
    ],
  },
  payout_rejected: {
    ar: (p) => [
      'حساب التحويل اترفض',
      `مقدرناش نقبل حساب التحويل بتاعك لأن ${REJECTION_TEXT[p.code][0]}. ${p.reason}\nضيف حساب تاني من التطبيق.`,
    ],
    en: (p) => [
      'Your payout account was rejected',
      `Your payout account was rejected because ${REJECTION_TEXT[p.code][1]}. ${p.reason}\nAdd another account in the app.`,
    ],
  },
};

const HTML_CHARS = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (c) => HTML_CHARS[c]);
}

export async function sendNotice(email, language, kind, params = {}) {
  const lang = language === 'en' ? 'en' : 'ar';
  const [subject, text] = NOTICES[kind][lang](params);

  if (!config.mail.brevoKey && !transporter) {
    console.log(`Notice for ${email} (${kind})`);
    return;
  }

  const paragraphs = escapeHtml(text).split('\n').map((line) => `<p>${line}</p>`).join('');
  const html = `<div dir="${lang === 'en' ? 'ltr' : 'rtl'}">${paragraphs}</div>`;
  try {
    if (config.mail.brevoKey) {
      await sendWithBrevo(email, subject, text, html);
    } else {
      await transporter.sendMail({ from: config.mail.from, to: email, subject, text, html });
    }
  } catch (err) {
    console.error(`Notice email failed (${kind}):`, err.message);
  }
}
>>>>>>> d781b645a8017bd6c14b7fd5c192cd82dd60251a
