import { Module } from '@nestjs/common';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';
import { TasksRepository } from './tasks.repository';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';

@Module({
  controllers: [TasksController],
  providers: [TasksService, TasksRepository, SupabaseAuthGuard],
  // Exported so other modules (e.g. Reminders) can reuse TasksService's
  // existing ownership-checked findOne() rather than duplicating repository
  // access.
  exports: [TasksService],
})
export class TasksModule {}
