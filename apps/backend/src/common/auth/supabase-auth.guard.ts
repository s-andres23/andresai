import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { RequestWithUser } from './request-with-user.interface';

@Injectable()
export class SupabaseAuthGuard implements CanActivate {
  constructor(private readonly supabaseService: SupabaseService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<RequestWithUser>();
    const token = this.extractBearerToken(request);

    if (!token) {
      throw new UnauthorizedException('Missing authentication token');
    }

    const { data, error } =
      await this.supabaseService.client.auth.getUser(token);

    if (error || !data.user) {
      throw new UnauthorizedException(
        'Invalid or expired authentication token',
      );
    }

    request.user = { id: data.user.id };
    return true;
  }

  private extractBearerToken(request: RequestWithUser): string | null {
    const header = request.headers.authorization;
    if (!header) {
      return null;
    }

    const [type, token] = header.split(' ');
    return type === 'Bearer' && token ? token : null;
  }
}
