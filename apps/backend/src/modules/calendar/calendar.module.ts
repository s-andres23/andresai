import { Module } from '@nestjs/common';
import { CalendarController } from './calendar.controller';
import { CalendarService } from './calendar.service';
import { CalendarRepository } from './calendar.repository';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { ReminderSyncModule } from '../reminders/reminder-sync.module';

@Module({
  // ReminderSyncModule (not RemindersModule) so CalendarService can sync
  // reminders after an event moves without creating a circular module
  // dependency -- RemindersModule already imports CalendarModule.
  imports: [ReminderSyncModule],
  controllers: [CalendarController],
  providers: [CalendarService, CalendarRepository, SupabaseAuthGuard],
  // Exported so other modules (e.g. Reminders) can reuse CalendarService's
  // existing ownership-checked findOne() rather than duplicating repository
  // access.
  exports: [CalendarService],
})
export class CalendarModule {}
