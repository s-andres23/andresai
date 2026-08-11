import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { createClient } from '@supabase/supabase-js';
import { AppModule } from '../src/app.module';

interface TaskResponse {
  id: string;
  title: string;
  status: string;
  completedAt: string | null;
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY;
const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL;
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD;

jest.setTimeout(30000);

describe('Tasks (e2e)', () => {
  let app: INestApplication<App>;
  let accessToken: string;
  let createdTaskId: string | undefined;

  beforeAll(async () => {
    if (
      !SUPABASE_URL ||
      !SUPABASE_SECRET_KEY ||
      !TEST_USER_EMAIL ||
      !TEST_USER_PASSWORD
    ) {
      throw new Error(
        'Missing SUPABASE_URL, SUPABASE_SECRET_KEY, TEST_USER_EMAIL or ' +
          'TEST_USER_PASSWORD environment variables required for the tasks e2e test',
      );
    }

    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();

    const authClient = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY);
    const { data, error } = await authClient.auth.signInWithPassword({
      email: TEST_USER_EMAIL,
      password: TEST_USER_PASSWORD,
    });

    if (error || !data.session) {
      throw new Error(
        `Failed to sign in as the e2e test user: ${error?.message ?? 'no session returned'}`,
      );
    }

    accessToken = data.session.access_token;
  });

  afterAll(async () => {
    if (createdTaskId && app) {
      await request(app.getHttpServer())
        .delete(`/api/v1/tasks/${createdTaskId}`)
        .set('Authorization', `Bearer ${accessToken}`);
    }

    if (app) {
      await app.close();
    }
  });

  it('runs the full authenticated task lifecycle', async () => {
    const authHeader = `Bearer ${accessToken}`;
    const server = app.getHttpServer();

    await request(server)
      .get('/api/v1/tasks')
      .set('Authorization', authHeader)
      .expect(200)
      .expect((res) => {
        expect(Array.isArray(res.body)).toBe(true);
      });

    const createRes = await request(server)
      .post('/api/v1/tasks')
      .set('Authorization', authHeader)
      .send({ title: 'E2E test task', priority: 'normal' })
      .expect(201);

    const createdTask = createRes.body as TaskResponse;
    createdTaskId = createdTask.id;
    expect(createdTaskId).toEqual(expect.any(String));
    expect(createdTask.title).toBe('E2E test task');
    expect(createdTask.status).toBe('open');

    const getRes = await request(server)
      .get(`/api/v1/tasks/${createdTaskId}`)
      .set('Authorization', authHeader)
      .expect(200);
    expect((getRes.body as TaskResponse).id).toBe(createdTaskId);

    const patchRes = await request(server)
      .patch(`/api/v1/tasks/${createdTaskId}`)
      .set('Authorization', authHeader)
      .send({ title: 'E2E test task (updated)' })
      .expect(200);
    expect((patchRes.body as TaskResponse).title).toBe(
      'E2E test task (updated)',
    );

    const completeRes = await request(server)
      .post(`/api/v1/tasks/${createdTaskId}/complete`)
      .set('Authorization', authHeader)
      .expect(201);
    const completedTask = completeRes.body as TaskResponse;
    expect(completedTask.status).toBe('completed');
    expect(completedTask.completedAt).not.toBeNull();

    const reopenRes = await request(server)
      .post(`/api/v1/tasks/${createdTaskId}/reopen`)
      .set('Authorization', authHeader)
      .expect(201);
    const reopenedTask = reopenRes.body as TaskResponse;
    expect(reopenedTask.status).toBe('open');
    expect(reopenedTask.completedAt).toBeNull();

    await request(server)
      .delete(`/api/v1/tasks/${createdTaskId}`)
      .set('Authorization', authHeader)
      .expect(204);

    await request(server)
      .get(`/api/v1/tasks/${createdTaskId}`)
      .set('Authorization', authHeader)
      .expect(404);

    // Already deleted above; clear so afterAll doesn't attempt a redundant delete.
    createdTaskId = undefined;
  });
});
