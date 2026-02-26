import {
  type LlmClient,
  type LlmProviderConfig,
  type TickContext,
  createLlmProviderClient,
} from '@elata-biosciences/agentforge';
import { BaseProtocolAgent } from './BaseProtocolAgent.js';

export interface LlmGossipCoordinatorAgentParams {
  provider?: LlmProviderConfig['provider'];
  model?: string;
  channelId?: string;
  postEveryTicks?: number;
}

/**
 * Produces protocol-oriented gossip updates.
 * - exploration: uses a real LLM provider
 * - deterministic/replay: emits deterministic fallback text
 */
export class LlmGossipCoordinatorAgent extends BaseProtocolAgent {
  private llm: LlmClient | null = null;
  private resolvedProvider: LlmProviderConfig['provider'] | null = null;

  private getProviderConfig(): LlmProviderConfig | null {
    const requestedProvider = this.getParam<LlmProviderConfig['provider']>('provider', 'openai');
    const provider = this.resolveProvider(requestedProvider);
    if (!provider) {
      return null;
    }
    const model = this.getParam<string>('model', process.env.OPENAI_MODEL ?? 'gpt-4o-mini');
    this.resolvedProvider = provider;
    return { provider, model };
  }

  private getClient(): LlmClient {
    if (this.llm) return this.llm;
    const config = this.getProviderConfig();
    if (!config) {
      throw new Error('no_llm_provider_key_configured');
    }
    this.llm = createLlmProviderClient(config);
    return this.llm;
  }

  private resolveProvider(
    requested: LlmProviderConfig['provider']
  ): LlmProviderConfig['provider'] | null {
    const hasOpenAiKey = Boolean(process.env.OPENAI_API_KEY);
    const hasOpenRouterKey = Boolean(process.env.OPENROUTER_API_KEY);
    if (requested === 'openai') {
      if (hasOpenAiKey) return 'openai';
      if (hasOpenRouterKey) return 'openrouter';
      return null;
    }
    if (requested === 'openrouter') {
      if (hasOpenRouterKey) return 'openrouter';
      if (hasOpenAiKey) return 'openai';
      return null;
    }
    return requested;
  }

  override async step(ctx: TickContext) {
    if (!ctx.gossip) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: 'gossip_unavailable',
      });
      return null;
    }
    const every = this.getParam<number>('postEveryTicks', 2);
    if (every <= 0 || ctx.tick % every !== 0) {
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: every <= 0 ? 'invalid_post_cadence' : 'cadence_wait',
        context: {
          postEveryTicks: every,
          tick: ctx.tick,
        },
      });
      return null;
    }

    const channelId = this.getParam<string>('channelId', 'governance');
    const world = this.getWorldState();
    const isLiveProvider =
      ctx.mode === 'exploration' || process.env.LLM_GOSSIP_FORCE_PROVIDER === '1';
    let text = `deterministic tick=${ctx.tick} apps=${world.appCount} fees=${world.feesCollectedTotal.toString()}`;
    let reason = 'posted_gossip_deterministic';

    if (isLiveProvider) {
      const config = this.getProviderConfig();
      if (!config) {
        throw new Error(
          'No LLM API key configured for provider-backed gossip run. Set OPENAI_API_KEY or OPENROUTER_API_KEY.'
        );
      }
      try {
        const llm = this.getClient();
        const prompt = {
          tick: ctx.tick,
          appCount: world.appCount,
          feesCollectedTotal: world.feesCollectedTotal.toString(),
          feesDistributed: world.feesDistributed.toString(),
          veEltaTotalLocked: String((world as any).veEltaTotalLocked ?? 0),
        };
        const response = await llm.complete({
          model: this.getParam<string>('model', process.env.OPENAI_MODEL ?? 'gpt-4o-mini'),
          system:
            'You are a protocol analyst for Elata. Write one concise coordination message for other agents.',
          user: `Summarize current protocol state and a suggested next action:\n${JSON.stringify(prompt)}`,
        });
        text = response.trim().slice(0, 280);
        reason = 'posted_gossip_llm_provider';
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        text = `fallback tick=${ctx.tick} apps=${world.appCount} fees=${world.feesCollectedTotal.toString()}`;
        reason = 'posted_gossip_provider_fallback';
        ctx.logger.warn(
          {
            agentId: this.id,
            tick: ctx.tick,
            requestedProvider: this.getParam<LlmProviderConfig['provider']>('provider', 'openai'),
            resolvedProvider: this.resolvedProvider ?? 'none',
            error: message,
          },
          'Provider unavailable, using deterministic gossip fallback'
        );
      }
    }

    const posted = ctx.gossip.postMessage(
      this.id,
      channelId,
      { text },
      {
        intentTag: 'inform',
        audience: { type: 'public' },
        credibilityPrior: isLiveProvider ? 0.65 : 0.95,
      }
    );
    if (!posted.ok) {
      const errorCode = String(posted.error ?? 'unknown_error');
      this.recordDecisionMemory(ctx, {
        decision: 'no_op',
        reason: `gossip_post_failed_${errorCode}`,
        context: {
          channelId,
          liveProvider: isLiveProvider,
          error: errorCode,
          appCount: world.appCount,
        },
      });
      ctx.logger.warn(
        {
          agentId: this.id,
          tick: ctx.tick,
          channelId,
          error: errorCode,
        },
        'Gossip post failed'
      );
      return null;
    }

    this.recordDecisionMemory(ctx, {
      decision: 'post_gossip',
      reason,
      context: {
        channelId,
        liveProvider: isLiveProvider,
        appCount: world.appCount,
        textLength: text.length,
        messageId: posted.messageId ?? 'missing',
      },
    });
    return null;
  }
}
