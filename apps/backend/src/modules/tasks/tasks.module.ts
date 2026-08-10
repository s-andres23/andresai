import { Module } from '@nestjs/common';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';
import { TasksRepository } from './tasks.repository';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';

@Module({
  controllers: [TasksController],
  providers: [TasksService, TasksRepository, SupabaseAuthGuard],
})
export class TasksModule {}
