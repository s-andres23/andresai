import { Module } from '@nestjs/common';
import { RemindersController } from './reminders.controller';
import { RemindersService } from './reminders.service';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { TasksModule } from '../tasks/tasks.module';
import { CalendarModule } from '../calendar/calendar.module';
import { ReminderSyncModule } from './reminder-sync.module';

@Module({
  // RemindersRepository comes from ReminderSyncModule (see its docstring),
  // shared with ReminderSyncService rather than provided twice.
  imports: [TasksModule, CalendarModule, ReminderSyncModule],
  controllers: [RemindersController],
  providers: [RemindersService, SupabaseAuthGuard],
})
export class RemindersModule {}
