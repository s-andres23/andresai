import { Request } from 'express';

export interface AuthenticatedUser {
  id: string;
}

export interface RequestWithUser extends Request {
  user: AuthenticatedUser;
}
