import express from 'express';
import cors from 'cors';
import config from './config.js';
import { AppError, toAppError } from './errors.js';
import healthRouter from './routes/health.js';

const app = express();

app.disable('x-powered-by');
app.use(cors({ origin: config.corsOrigins }));
app.use(express.json({ limit: '1mb' }));

app.use('/api/health', healthRouter);

app.use((req, res, next) => {
  next(new AppError(404, 'NOT_FOUND', 'Route not found'));
});

app.use((err, req, res, next) => {
  const error = toAppError(err);
  if (error.status >= 500) {
    console.error(err);
  }

  const body = { error: { code: error.code, message: error.message } };
  if (config.env !== 'production' && error.detail) {
    body.error.detail = error.detail;
  }
  res.status(error.status).json(body);
});

export default app;
