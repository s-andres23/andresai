import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CreateCalendarEventDto } from './create-calendar-event.dto';

function validateDto(payload: Record<string, unknown>) {
  const dto = plainToInstance(CreateCalendarEventDto, payload);
  return validate(dto);
}

describe('CreateCalendarEventDto', () => {
  const validPayload = {
    title: 'Team sync',
    startAt: '2026-08-20T09:00:00.000Z',
    endAt: '2026-08-20T09:30:00.000Z',
  };

  it('accepts a minimal valid payload', async () => {
    const errors = await validateDto(validPayload);
    expect(errors).toHaveLength(0);
  });

  it('accepts a fully populated valid payload', async () => {
    const errors = await validateDto({
      ...validPayload,
      description: 'Weekly sync with the team',
      allDay: true,
      location: 'Conference room A',
    });
    expect(errors).toHaveLength(0);
  });

  it('rejects a missing title', async () => {
    const payload: Record<string, unknown> = { ...validPayload };
    delete payload.title;
    const errors = await validateDto(payload);
    expect(errors.some((e) => e.property === 'title')).toBe(true);
  });

  it('rejects an empty title', async () => {
    const errors = await validateDto({ ...validPayload, title: '' });
    expect(errors.some((e) => e.property === 'title')).toBe(true);
  });

  it('rejects a title over 200 characters', async () => {
    const errors = await validateDto({
      ...validPayload,
      title: 'a'.repeat(201),
    });
    expect(errors.some((e) => e.property === 'title')).toBe(true);
  });

  it('rejects a missing startAt', async () => {
    const payload: Record<string, unknown> = { ...validPayload };
    delete payload.startAt;
    const errors = await validateDto(payload);
    expect(errors.some((e) => e.property === 'startAt')).toBe(true);
  });

  it('rejects a missing endAt', async () => {
    const payload: Record<string, unknown> = { ...validPayload };
    delete payload.endAt;
    const errors = await validateDto(payload);
    expect(errors.some((e) => e.property === 'endAt')).toBe(true);
  });

  it('rejects a non-ISO-8601 startAt', async () => {
    const errors = await validateDto({
      ...validPayload,
      startAt: 'not-a-date',
    });
    expect(errors.some((e) => e.property === 'startAt')).toBe(true);
  });

  it('rejects a non-ISO-8601 endAt', async () => {
    const errors = await validateDto({ ...validPayload, endAt: 'tomorrow' });
    expect(errors.some((e) => e.property === 'endAt')).toBe(true);
  });

  it('rejects a description over 2000 characters', async () => {
    const errors = await validateDto({
      ...validPayload,
      description: 'a'.repeat(2001),
    });
    expect(errors.some((e) => e.property === 'description')).toBe(true);
  });

  it('rejects a non-boolean allDay', async () => {
    const errors = await validateDto({ ...validPayload, allDay: 'yes' });
    expect(errors.some((e) => e.property === 'allDay')).toBe(true);
  });

  it('rejects a location over 200 characters', async () => {
    const errors = await validateDto({
      ...validPayload,
      location: 'a'.repeat(201),
    });
    expect(errors.some((e) => e.property === 'location')).toBe(true);
  });
});
