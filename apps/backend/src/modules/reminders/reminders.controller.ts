import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { SupabaseAuthGuard } from '../../common/auth/supabase-auth.guard';
import { CurrentUser } from '../../common/auth/current-user.decorator';
import { RemindersService } from './reminders.service';
import { CreateReminderDto } from './dto/create-reminder.dto';
import { UpdateReminderDto } from './dto/update-reminder.dto';

@Controller('reminders')
@UseGuards(SupabaseAuthGuard)
export class RemindersController {
  constructor(private readonly remindersService: RemindersService) {}

  @Get()
  findAll(@CurrentUser() userId: string) {
    return this.remindersService.findAll(userId);
  }

  @Post()
  create(@CurrentUser() userId: string, @Body() dto: CreateReminderDto) {
    return this.remindersService.create(userId, dto);
  }

  @Get(':id')
  findOne(
    @CurrentUser() userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.remindersService.findOne(userId, id);
  }

  @Patch(':id')
  update(
    @CurrentUser() userId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateReminderDto,
  ) {
    return this.remindersService.update(userId, id, dto);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @CurrentUser() userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.remindersService.remove(userId, id);
  }

  @Post(':id/cancel')
  cancel(
    @CurrentUser() userId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.remindersService.cancel(userId, id);
  }
}
