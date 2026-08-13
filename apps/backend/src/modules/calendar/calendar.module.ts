import { Module } from '@nestjs/common';
import { CalendarController } from './calendar.controller';
import { CalendarService } from './calendar.service';
import { CalendarRepository } from './calendar.repository';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';

@Module({
  controllers: [CalendarController],
  providers: [CalendarService, CalendarRepository, SupabaseAuthGuard],
})
export class CalendarModule {}
