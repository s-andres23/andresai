import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { SupabaseAuthGuard } from './supabase-auth.guard';
import { SupabaseService } from '../supabase/supabase.service';
import { RequestWithUser } from './request-with-user.interface';

describe('SupabaseAuthGuard', () => {
  const getUser = jest.fn();
  const supabaseService = {
    client: { auth: { getUser } },
  } as unknown as SupabaseService;

  const guard = new SupabaseAuthGuard(supabaseService);

  const buildContext = (headers: Record<string, string>) => {
    const request = { headers } as unknown as RequestWithUser;
    return {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;
  };

  afterEach(() => jest.clearAllMocks());

  it('throws when no authorization header is present', async () => {
    await expect(guard.canActivate(buildContext({}))).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('throws when the token is rejected by Supabase', async () => {
    getUser.mockResolvedValue({
      data: { user: null },
      error: new Error('invalid'),
    });

    await expect(
      guard.canActivate(buildContext({ authorization: 'Bearer bad-token' })),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('attaches the authenticated user and allows the request', async () => {
    getUser.mockResolvedValue({
      data: { user: { id: 'user-1' } },
      error: null,
    });
    const context = buildContext({ authorization: 'Bearer good-token' });

    await expect(guard.canActivate(context)).resolves.toBe(true);

    const request = context.switchToHttp().getRequest<RequestWithUser>();
    expect(request.user).toEqual({ id: 'user-1' });
    expect(getUser).toHaveBeenCalledWith('good-token');
  });
});
