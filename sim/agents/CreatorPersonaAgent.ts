import type { PersonaProfile, TickContext } from '@elata-biosciences/agentforge';
import { createApp } from '../actions/index.js';
import { BaseElataPersonaLlmAgent } from './BaseElataPersonaLlmAgent.js';

export class CreatorPersonaAgent extends BaseElataPersonaLlmAgent {
  protected getPersonaProfile(): PersonaProfile {
    return {
      id: 'creator',
      style: 'optimistic builder',
      goals: ['Launch useful apps', 'Expand app ecosystem breadth'],
      riskProfile: 'medium',
      constraints: ['Avoid spam app creation when app count is already high'],
      preferredTools: ['QueryWorld', 'create_app'],
    };
  }

  protected getAllowedProtocolActions(): string[] {
    return ['create_app', 'noop'];
  }

  protected getFallbackIntent(ctx: TickContext) {
    const world = this.getWorldState();
    if (world.appCount >= 18 || ctx.tick % 2 !== 0) {
      return { name: 'noop', params: { reason: 'creator_wait' } };
    }
    const suffix = `${this.id}-${ctx.tick}`;
    const action = createApp(`PersonaApp-${suffix}`, `PA${ctx.tick % 100}`, `ipfs://persona/${suffix}`);
    return {
      name: 'create_app',
      params: {
        name: action.name,
        symbol: action.symbol,
        metadataUri: action.metadataUri,
      },
      rationale: 'Expand protocol surface with a fresh app launch.',
      metadata: { confidence: 0.7 },
    };
  }
}
