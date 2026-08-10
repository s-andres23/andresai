import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

@Injectable()
export class SupabaseService {
  readonly client: SupabaseClient<any, any, any>;

  constructor(configService: ConfigService) {
    const url = configService.get<string>('SUPABASE_URL');
    const secretKey = configService.get<string>('SUPABASE_SECRET_KEY');

    if (!url || !secretKey) {
      throw new Error(
        'Missing Supabase configuration: SUPABASE_URL and SUPABASE_SECRET_KEY must be set',
      );
    }

    this.client = createClient<any, any, any>(url, secretKey);
  }
}
