/**
 * The shapes the app reads and writes: the cloud contract's rows, snake_case
 * exactly as PostgREST returns them. Screens import from here, never from the
 * contract directly, so swapping the vendored copy for the package is one line.
 */
import type { Message } from './contract';

export type {
  Agent,
  AgentRole,
  AgentStatus,
  Ask,
  AskAnswer,
  AskKind,
  AskOption,
  Conversation,
  Desk,
  Message,
  Project,
} from './contract';
export { NEEDS_YOU_STATUSES, isDeskOnline } from './contract';

/** A message the device has sent but the server has not echoed yet. */
export type LocalMessage = Message & { pending?: boolean };
