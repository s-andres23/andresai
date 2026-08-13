import { CalendarRepository } from './calendar.repository';
import { SupabaseService } from '../../common/supabase/supabase.service';

type QueryResult = { data: unknown; error: unknown };

function createQueryBuilder(result: QueryResult) {
  const builder: Record<string, jest.Mock> = {};
  const chainMethods = [
    'select',
    'eq',
    'gte',
    'lte',
    'order',
    'insert',
    'update',
    'delete',
  ];

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

describe('CalendarRepository', () => {
  const userId = 'user-1';
  const row = {
    id: 'event-1',
    user_id: userId,
    title: 'Team sync',
    description: null,
    start_at: '2026-08-20T09:00:00.000Z',
    end_at: '2026-08-20T09:30:00.000Z',
    all_day: false,
    location: null,
    created_at: '2026-08-13T00:00:00.000Z',
    updated_at: '2026-08-13T00:00:00.000Z',
  };

  const buildRepository = (
    queryBuilder: ReturnType<typeof createQueryBuilder>,
  ) => {
    const from = jest.fn(() => queryBuilder);
    const supabaseService = {
      client: { from },
    } as unknown as SupabaseService;

    return { repository: new CalendarRepository(supabaseService), from };
  };

  it('maps rows to camelCase calendar events on findAll', async () => {
    const queryBuilder = createQueryBuilder({ data: [row], error: null });
    const { repository, from } = buildRepository(queryBuilder);

    const events = await repository.findAll(userId);

    expect(from).toHaveBeenCalledWith('calendar_events');
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(queryBuilder.order).toHaveBeenCalledWith('start_at', {
      ascending: true,
    });
    expect(events).toEqual([
      {
        id: 'event-1',
        userId,
        title: 'Team sync',
        description: null,
        startAt: row.start_at,
        endAt: row.end_at,
        allDay: false,
        location: null,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      },
    ]);
  });

  it('does not apply range filters when from/to are absent', async () => {
    const queryBuilder = createQueryBuilder({ data: [], error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.findAll(userId);

    expect(queryBuilder.gte).not.toHaveBeenCalled();
    expect(queryBuilder.lte).not.toHaveBeenCalled();
  });

  it('filters by end_at >= from when only from is provided', async () => {
    const queryBuilder = createQueryBuilder({ data: [], error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.findAll(userId, '2026-08-20T00:00:00.000Z');

    expect(queryBuilder.gte).toHaveBeenCalledWith(
      'end_at',
      '2026-08-20T00:00:00.000Z',
    );
    expect(queryBuilder.lte).not.toHaveBeenCalled();
  });

  it('filters by start_at <= to when only to is provided', async () => {
    const queryBuilder = createQueryBuilder({ data: [], error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.findAll(userId, undefined, '2026-08-21T00:00:00.000Z');

    expect(queryBuilder.lte).toHaveBeenCalledWith(
      'start_at',
      '2026-08-21T00:00:00.000Z',
    );
    expect(queryBuilder.gte).not.toHaveBeenCalled();
  });

  it('applies both overlap bounds when from and to are provided', async () => {
    const queryBuilder = createQueryBuilder({ data: [], error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.findAll(
      userId,
      '2026-08-20T00:00:00.000Z',
      '2026-08-21T00:00:00.000Z',
    );

    expect(queryBuilder.gte).toHaveBeenCalledWith(
      'end_at',
      '2026-08-20T00:00:00.000Z',
    );
    expect(queryBuilder.lte).toHaveBeenCalledWith(
      'start_at',
      '2026-08-21T00:00:00.000Z',
    );
  });

  it('returns null when an event is not found', async () => {
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

  it('inserts a new event scoped to the user with defaults applied', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.create(userId, {
      title: 'Team sync',
      startAt: '2026-08-20T09:00:00.000Z',
      endAt: '2026-08-20T09:30:00.000Z',
    });

    expect(queryBuilder.insert).toHaveBeenCalledWith({
      user_id: userId,
      title: 'Team sync',
      description: null,
      start_at: '2026-08-20T09:00:00.000Z',
      end_at: '2026-08-20T09:30:00.000Z',
      all_day: false,
      location: null,
    });
  });

  it('only includes defined fields when updating', async () => {
    const queryBuilder = createQueryBuilder({ data: row, error: null });
    const { repository } = buildRepository(queryBuilder);

    await repository.update(userId, row.id, { title: 'Updated title' });

    expect(queryBuilder.update).toHaveBeenCalledWith({
      title: 'Updated title',
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
});
