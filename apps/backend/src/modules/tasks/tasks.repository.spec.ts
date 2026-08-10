import { TasksRepository } from './tasks.repository';
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

describe('TasksRepository', () => {
  const userId = 'user-1';
  const row = {
    id: 'task-1',
    user_id: userId,
    title: 'Write report',
    description: null,
    status: 'open',
    priority: 'normal',
    due_date: null,
    due_time: null,
    created_at: '2026-08-10T00:00:00.000Z',
    updated_at: '2026-08-10T00:00:00.000Z',
    completed_at: null,
  };

  const buildRepository = (
    queryBuilder: ReturnType<typeof createQueryBuilder>,
  ) => {
    const from = jest.fn(() => queryBuilder);
    const supabaseService = {
      client: { from },
    } as unknown as SupabaseService;

    return { repository: new TasksRepository(supabaseService), from };
  };

  it('maps rows to camelCase tasks on findAll', async () => {
    const queryBuilder = createQueryBuilder({ data: [row], error: null });
    const { repository, from } = buildRepository(queryBuilder);

    const tasks = await repository.findAll(userId);

    expect(from).toHaveBeenCalledWith('tasks');
    expect(queryBuilder.eq).toHaveBeenCalledWith('user_id', userId);
    expect(tasks).toEqual([
      {
        id: 'task-1',
        userId,
        title: 'Write report',
        description: null,
        status: 'open',
        priority: 'normal',
        dueDate: null,
        dueTime: null,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        completedAt: null,
      },
    ]);
  });

  it('returns null when a task is not found', async () => {
    const queryBuilder = createQueryBuilder({ data: null, error: null });
    const { repository } = buildRepository(queryBuilder);

    await expect(repository.findById(userId, 'missing')).resolves.toBeNull();
  });

  it('throws when Supabase returns an error', async () => {
    const queryBuilder = createQueryBuilder({
      data: null,
      error: new Error('db error'),
    });
    const { repository } = buildRepository(queryBuilder);

    await expect(repository.findAll(userId)).rejects.toThrow('db error');
  });

  it('sets completed_at when marking a task as completed', async () => {
    const queryBuilder = createQueryBuilder({
      data: {
        ...row,
        status: 'completed',
        completed_at: '2026-08-10T01:00:00.000Z',
      },
      error: null,
    });
    const { repository } = buildRepository(queryBuilder);

    const task = await repository.setStatus(userId, row.id, 'completed');

    expect(queryBuilder.update).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'completed' }),
    );
    expect(task.status).toBe('completed');
    expect(task.completedAt).toBe('2026-08-10T01:00:00.000Z');
  });
});
