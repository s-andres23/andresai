import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { createClient } from '@supabase/supabase-js';
import { AppModule } from '../src/app.module';

interface CalendarEventResponse {
  id: string;
  title: string;
  description: string | null;
  startAt: string;
  endAt: string;
  allDay: boolean;
  location: string | null;
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY;
const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL;
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD;

jest.setTimeout(30000);

describe('Calendar (e2e)', () => {
  let app: INestApplication<App>;
  let accessToken: string;
  let createdEventId: string | undefined;

  beforeAll(async () => {
    if (
      !SUPABASE_URL ||
      !SUPABASE_SECRET_KEY ||
      !TEST_USER_EMAIL ||
      !TEST_USER_PASSWORD
    ) {
      throw new Error(
        'Missing SUPABASE_URL, SUPABASE_SECRET_KEY, TEST_USER_EMAIL or ' +
          'TEST_USER_PASSWORD environment variables required for the calendar e2e test',
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
    if (createdEventId && app) {
      await request(app.getHttpServer())
        .delete(`/api/v1/calendar-events/${createdEventId}`)
        .set('Authorization', `Bearer ${accessToken}`);
    }

    if (app) {
      await app.close();
    }
  });

  it('runs the full authenticated calendar event lifecycle', async () => {
    const authHeader = `Bearer ${accessToken}`;
    const server = app.getHttpServer();

    const startAt = '2026-09-01T09:00:00.000Z';
    const endAt = '2026-09-01T09:30:00.000Z';

    await request(server)
      .get('/api/v1/calendar-events')
      .set('Authorization', authHeader)
      .expect(200)
      .expect((res) => {
        expect(Array.isArray(res.body)).toBe(true);
      });

    const createRes = await request(server)
      .post('/api/v1/calendar-events')
      .set('Authorization', authHeader)
      .send({
        title: 'E2E test event',
        startAt,
        endAt,
        location: 'Conference room A',
      })
      .expect(201);

    const createdEvent = createRes.body as CalendarEventResponse;
    createdEventId = createdEvent.id;
    expect(createdEventId).toEqual(expect.any(String));
    expect(createdEvent.title).toBe('E2E test event');
    // Postgres/PostgREST may render the timestamp with a `+00:00` offset
    // instead of a `Z` suffix; compare the instant, not the exact string.
    expect(new Date(createdEvent.startAt).getTime()).toBe(
      new Date(startAt).getTime(),
    );
    expect(new Date(createdEvent.endAt).getTime()).toBe(
      new Date(endAt).getTime(),
    );
    expect(createdEvent.allDay).toBe(false);
    expect(createdEvent.location).toBe('Conference room A');

    const listRes = await request(server)
      .get('/api/v1/calendar-events')
      .set('Authorization', authHeader)
      .expect(200);
    const listedIds = (listRes.body as CalendarEventResponse[]).map(
      (event) => event.id,
    );
    expect(listedIds).toContain(createdEventId);

    // A range fully covering the event should include it (overlap test).
    const matchingRangeRes = await request(server)
      .get('/api/v1/calendar-events')
      .query({
        from: '2026-09-01T00:00:00.000Z',
        to: '2026-09-02T00:00:00.000Z',
      })
      .set('Authorization', authHeader)
      .expect(200);
    const matchingIds = (matchingRangeRes.body as CalendarEventResponse[]).map(
      (event) => event.id,
    );
    expect(matchingIds).toContain(createdEventId);

    // A disjoint range should exclude it.
    const nonMatchingRangeRes = await request(server)
      .get('/api/v1/calendar-events')
      .query({
        from: '2026-10-01T00:00:00.000Z',
        to: '2026-10-02T00:00:00.000Z',
      })
      .set('Authorization', authHeader)
      .expect(200);
    const nonMatchingIds = (
      nonMatchingRangeRes.body as CalendarEventResponse[]
    ).map((event) => event.id);
    expect(nonMatchingIds).not.toContain(createdEventId);

    const getRes = await request(server)
      .get(`/api/v1/calendar-events/${createdEventId}`)
      .set('Authorization', authHeader)
      .expect(200);
    expect((getRes.body as CalendarEventResponse).id).toBe(createdEventId);

    const patchRes = await request(server)
      .patch(`/api/v1/calendar-events/${createdEventId}`)
      .set('Authorization', authHeader)
      .send({ title: 'E2E test event (updated)', allDay: true })
      .expect(200);
    const patchedEvent = patchRes.body as CalendarEventResponse;
    expect(patchedEvent.title).toBe('E2E test event (updated)');
    expect(patchedEvent.allDay).toBe(true);

    // A partial update that would move startAt after the event's existing
    // endAt must be rejected using the *effective* interval.
    await request(server)
      .patch(`/api/v1/calendar-events/${createdEventId}`)
      .set('Authorization', authHeader)
      .send({ startAt: '2026-09-01T10:00:00.000Z' })
      .expect(400);

    await request(server)
      .delete(`/api/v1/calendar-events/${createdEventId}`)
      .set('Authorization', authHeader)
      .expect(204);

    await request(server)
      .get(`/api/v1/calendar-events/${createdEventId}`)
      .set('Authorization', authHeader)
      .expect(404);

    // Already deleted above; clear so afterAll doesn't attempt a redundant delete.
    createdEventId = undefined;
  });

  it('rejects a range query where to is before from', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/calendar-events')
      .query({
        from: '2026-09-02T00:00:00.000Z',
        to: '2026-09-01T00:00:00.000Z',
      })
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(400);
  });

  it('rejects an unauthenticated request', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/calendar-events')
      .expect(401);
  });
});
