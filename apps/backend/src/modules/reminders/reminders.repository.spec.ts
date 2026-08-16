import { RemindersRepository } from './reminders.repository';
import { SupabaseService } from '../../common/supabase/supabase.service';

type QueryResult = { data: unknown; error: unknown };

function createQueryBuilder(result: QueryResult) {
  const builder: Record<string, jest.Mock> = {};
  const chainMethods = ['select', 'eq', 'order', 'insert', 'update', 'delete'];

  for (const method of chainMethods) {
    builder[method] = jest.fn(() => builder);
  }

  builder.single = jest.fn(() => Promise.resolve(result));
  builder.maybeSingle = jest.fn(() => Promise.resolve(result));
  // `await`-ing the chain directly (findAll/delete) resolves via `then`.
  builder.then = (onFulfilled: (value: QueryResult) => unknown) =>
    Promise.resolve(result).then(onFulfilled);

  return builder;
}

describe('RemindersRepository', () => {
  const userId = 'user-1';
  const row = {
    id: 'reminder-1',
    user_id: userId,
    task_id: null,
    calendar_event_id: null,
    title: 'Stand up',
    trigger_type: 'absolute',
    offset_minutes: null,
    remind_at: '2026-08-20T09:00:00.000Z',
    status: 'pending',
    created_at: '2026-08-14T00:00:00.000Z',
    updated_at: '2026-08-14T00:00:00.000Z',
  };

  const buildRepository = (
    queryBuilder: ReturnType<typeof createQueryBuilder>,
  ) => {
    const from = jest.fn(() => queryBuilder);
    const supabaseService = {
      client: { from },
    } as unknown as SupabaseService;

    return { repository: new RemindersRepository(supabaseService), from };
  };

  it('maps rows to camelCase reminders on findAll, ordered by remind_at', async () => {
    const queryBuilder = createQueryBuilder({ data: [row], error: null });
    const { repository, from } = buildRepository(queryBuilder);

    const reminders = await repository.findAll(userId);

    expect(from).toHaveBeenCalledWith('reminders');
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.order).toHaveBeenCalledWith('remind_at', {
      ascending: true,
    });
    expect(reminders).toEqual([
      {
        id: 'reminder-1',
        userId,
        taskId: null,
        calendarEventId: null,
        title: 'Stand up',
        triggerType: 'absolute',
        offsetMinutes: null,
        remindAt: row.remind_at,
        status: 'pending',
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
    ]);
  });

  it('returns null when a reminder is not found', async () => {
    const queryBuilder = createQueryBuilder({ data: null, error: null });
    const { repository } = buildRepository(queryBuilder);

    await expect(repository.findById(userId, 'missing')).resolves.toBeNull();
  });

  it('scopes findById by both user_id and id', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.findById(userId, row.id);

    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
  });

  it('throws when Supabase returns an error', async () => {
    const queryBuilder = createQueryBuilder({
      data: null,
      error: new Error('db error'),
    });
    const { repository } = buildRepository(queryBuilder);

    await expect(repository.findAll(userId)).rejects.toThrow('db error');
  });

  it('inserts a new reminder scoped to the user', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.create(userId, {
      title: 'Stand up',
      taskId: null,
      calendarEventId: null,
      triggerType: 'absolute',
      offsetMinutes: null,
      remindAt: '2026-08-20T09:00:00.000Z',
    });

    expect(queryBuilder.insert).toHaveBeenCalledWith({
      user_id: userId,
      title: 'Stand up',
      task_id: null,
      calendar_event_id: null,
      trigger_type: 'absolute',
      offset_minutes: null,
      remind_at: '2026-08-20T09:00:00.000Z',
    });
  });

  it('writes all definition fields plus updated_at when updating', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.update(userId, row.id, {
      title: 'Stand up (updated)',
      taskId: null,
      calendarEventId: null,
      triggerType: 'absolute',
      offsetMinutes: null,
      remindAt: '2026-08-21T09:00:00.000Z',
    });

    expect(queryBuilder.update).toHaveBeenCalledWith({
      title: 'Stand up (updated)',
      task_id: null,
      calendar_event_id: null,
      trigger_type: 'absolute',
      offset_minutes: null,
      remind_at: '2026-08-21T09:00:00.000Z',
      updated_at: expect.any(String) as unknown,
    });
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
  });

  it('scopes delete by both user_id and id', async () => {
    const queryBuilder = createQueryBuilder({ data: null, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.delete(userId, row.id);

    expect(queryBuilder.delete).toHaveBeenCalled();
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
  });

  it('sets status and updated_at, scoped by user_id and id', async () => {
    const queryBuilder = createQueryBuilder({
      data: { ...row, status: 'cancelled' },
      error: null,
    });
    const { repository } = buildRepository(queryBuilder);

    const reminder = await repository.setStatus(userId, row.id, 'cancelled');

    expect(queryBuilder.update).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'cancelled' }),
    );
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
    expect(reminder.status).toBe('cancelled');
  });

  it('findPendingRelativeByCalendarEvent filters by user, calendar event, trigger type, and status', async () => {
    const relativeRow = {
      ...row,
      calendar_event_id: 'event-1',
      trigger_type: 'relative',
      offset_minutes: -15,
    };
    const queryBuilder = createQueryBuilder({
      data: [relativeRow],
      error: null,
    });
    const { repository, from } = buildRepository(queryBuilder);

    const reminders = await repository.findPendingRelativeByCalendarEvent(
      userId,
      'event-1',
    );

    expect(from).toHaveBeenCalledWith('reminders');
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith(
      'calendar_event_id',
      'event-1',
    );
    expect(queryBuilder.eq).toHaveBeenCalledWith('trigger_type', 'relative');
    expect(queryBuilder.eq).toHaveBeenCalledWith('status', 'pending');
    expect(reminders).toHaveLength(1);
    expect(reminders[0].calendarEventId).toBe('event-1');
  });

  it('findPendingRelativeByCalendarEvent throws when Supabase returns an error', async () => {
    const queryBuilder = createQueryBuilder({
      data: null,
      error: new Error('db error'),
    });
    const { repository } = buildRepository(queryBuilder);

    await expect(
      repository.findPendingRelativeByCalendarEvent(userId, 'event-1'),
    ).rejects.toThrow('db error');
  });

  it('updateRemindAt writes remind_at and updated_at, scoped by user_id and id', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.updateRemindAt(userId, row.id, '2026-08-21T08:45:00.000Z');

    expect(queryBuilder.update).toHaveBeenCalledWith({
      remind_at: '2026-08-21T08:45:00.000Z',
      updated_at: expect.any(String) as unknown,
    });
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
  });

  it('reactivate writes status pending, remind_at, and updated_at, scoped by user_id and id', async () => {
    const queryBuilder = createQueryBuilder({
      data: { ...row, status: 'pending' },
      error: null,
    });
    const { repository } = buildRepository(queryBuilder);

    const reminder = await repository.reactivate(
      userId,
      row.id,
      '2099-01-01T08:45:00.000Z',
    );

    expect(queryBuilder.update).toHaveBeenCalledWith({
      status: 'pending',
      remind_at: '2099-01-01T08:45:00.000Z',
      updated_at: expect.any(String) as unknown,
    });
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.eq).toHaveBeenCalledWith('id', row.id);
    expect(reminder.status).toBe('pending');
  });

  it('reactivate throws when Supabase returns an error', async () => {
    const queryBuilder = createQueryBuilder({
      data: null,
      error: new Error('db error'),
    });
    const { repository } = buildRepository(queryBuilder);

    await expect(
      repository.reactivate(userId, row.id, '2099-01-01T08:45:00.000Z'),
    ).rejects.toThrow('db error');
  });
});
