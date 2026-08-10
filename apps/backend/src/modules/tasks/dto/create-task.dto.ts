import {
  IsDateString,
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { TASK_PRIORITIES } from '../interfaces/task.interface';
import type { TaskPriority } from '../interfaces/task.interface';

const TIME_FORMAT = /^([01]\d|2[0-3]):([0-5]\d)(:([0-5]\d))?$/;

export class CreateTaskDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  title: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsIn(TASK_PRIORITIES)
  priority?: TaskPriority;

  @IsOptional()
  @IsDateString()
  dueDate?: string;

  @IsOptional()
  @Matches(TIME_FORMAT, {
    message: 'dueTime must be a valid time in HH:mm or HH:mm:ss format',
  })
  dueTime?: string;
}
