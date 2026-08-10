import { ConfigService } from '@nestjs/config';
import { SupabaseService } from './supabase.service';

describe('SupabaseService', () => {
  const buildConfigService = (values: Record<string, string | undefined>) =>
    ({ get: (key: string) => values[key] }) as ConfigService;

  it('creates a client when configuration is present', () => {
    const service = new SupabaseService(
      buildConfigService({
        SUPABASE_URL: 'https://example.supabase.co',
        SUPABASE_SECRET_KEY: 'secret-key',
      }),
    );

    expect(service.client).toBeDefined();
  });

  it('throws when SUPABASE_URL is missing', () => {
    expect(
      () =>
        new SupabaseService(
          buildConfigService({ SUPABASE_SECRET_KEY: 'secret-key' }),
        ),
    ).toThrow('Missing Supabase configuration');
  });

  it('throws when SUPABASE_SECRET_KEY is missing', () => {
    expect(
      () =>
        new SupabaseService(
          buildConfigService({ SUPABASE_URL: 'https://example.supabase.co' }),
        ),
    ).toThrow('Missing Supabase configuration');
  });
});
