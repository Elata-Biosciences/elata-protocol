import {
  LlmActionIntentSchema,
  LlmPlanIntentSchema,
  type CapabilityManifest,
  type LlmClient,
  type LlmProviderConfig,
  type PersonaProfile,
  type TickContext,
  createLlmProviderClient,
} from '@elata-biosciences/agentforge';
import type { Action } from '@elata-biosciences/agentforge';
import { BaseProtocolAgent } from './BaseProtocolAgent.js';

export interface BaseElataPersonaLlmAgentParams {
  provider?: LlmProviderConfig['provider'];
  model?: string;
  forceLlmInDeterministic?: boolean;
  maxPromptChars?: number;
  postingPolicy?: {
    preferredChannels?: string[];
    onlyPostOnMaterialChange?: boolean;
    maxPostChars?: number;
    minPostEveryTicks?: number;
    postOnInboxThreshold?: number;
    postOnMaterialChange?: boolean;
  };
}

type ParsedIntent = {
  name: string;
  params: Record<string, unknown>;
  rationale?: string;
  metadata?: { personaId?: string; intentTag?: string; confidence?: number };
};

type ParsedIntentDiagnostics = {
  intent: ParsedIntent | null;
  parseError?: string;
  salvaged?: boolean;
};

type ParsedPlan = {
  hypothesis: string;
  expectedEffect: string;
  preferredActionFamily?: string;
  confidence?: number;
  target?: {
    domain: string;
    identifier: string;
  };
};

const DEFAULT_ALLOWED_PROTOCOL_ACTIONS = ['noop'] as const;

export abstract class BaseElataPersonaLlmAgent extends BaseProtocolAgent {
  private llm: LlmClient | null = null;
  private resolvedProvider: LlmProviderConfig['provider'] | null = null;

  protected abstract getPersonaProfile(): PersonaProfile;
  protected abstract getFallbackIntent(ctx: TickContext): ParsedIntent;

  protected getAllowedProtocolActions(): string[] {
    return [...DEFAULT_ALLOWED_PROTOCOL_ACTIONS];
  }

  protected getQueryEndpointHint(): string {
    return 'get_world';
  }

  protected getProviderConfig(): LlmProviderConfig | null {
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

  override async step(ctx: TickContext): Promise<Action | null> {
    await this.preStep(ctx);
    const persona = this.getPersonaProfile();
    const world = this.getWorldState();
    const liveProvider =
      ctx.mode === 'exploration' || this.getParam<boolean>('forceLlmInDeterministic', false);
    const plan = this.buildFallbackPlan(ctx);
    const observationDelta = this.buildObservationDelta(ctx);
    const memorySummary = this.buildMemorySummary();

    let intent = this.getFallbackIntent(ctx);
    let intentSource = 'deterministic_fallback';

    if (liveProvider) {
      const config = this.getProviderConfig();
      if (!config) {
        throw new Error(
          `No LLM API key configured for persona agent "${persona.id}" in provider-backed mode. Set OPENAI_API_KEY or OPENROUTER_API_KEY.`
        );
      }
      try {
        const planCompletion = await this.getClient().complete({
          model: this.getParam<string>('model', process.env.OPENAI_MODEL ?? 'gpt-4o-mini'),
          system: this.buildSystemPrompt(persona, 'plan'),
          user: this.buildUserPrompt(ctx, plan, observationDelta, memorySummary, ctx.capabilities),
        });
        const parsedPlan = this.parsePlan(planCompletion);
        const effectivePlan = parsedPlan ?? plan;
        this.remember('last_plan', { tick: ctx.tick, ...effectivePlan });
        const actionCompletion = await this.getClient().complete({
          model: this.getParam<string>('model', process.env.OPENAI_MODEL ?? 'gpt-4o-mini'),
          system: this.buildSystemPrompt(persona, 'act'),
          user: this.buildActionPrompt(
            ctx,
            effectivePlan,
            observationDelta,
            memorySummary,
            ctx.capabilities
          ),
        });
        const parsedPrimary = this.parseIntent(actionCompletion);
        const parsed = parsedPrimary.intent ?? this.parseIntent(planCompletion).intent;
        if (parsedPrimary.parseError) {
          this.recordDecisionMemory(ctx, {
            decision: 'no_op',
            reason: 'llm_action_parse_error',
            context: {
              personaId: persona.id,
              parseError: parsedPrimary.parseError,
              salvaged: parsedPrimary.salvaged ?? false,
            },
          });
        }
        if (parsedPrimary.salvaged) {
          this.recordDecisionMemory(ctx, {
            decision: 'no_op',
            reason: 'llm_action_salvaged',
            context: {
              personaId: persona.id,
            },
          });
        }
        if (parsed) {
          intent = parsed;
          intentSource = parsedPlan ? 'llm_two_stage' : 'llm_compat_fallback';
          if (this.shouldRequestLlmPostRetry(ctx, observationDelta, intent, intentSource)) {
            const postRetryCompletion = await this.getClient().complete({
              model: this.getParam<string>('model', process.env.OPENAI_MODEL ?? 'gpt-4o-mini'),
              system: this.buildSystemPrompt(persona, 'act'),
              user: this.buildPostRetryPrompt(
                ctx,
                effectivePlan,
                observationDelta,
                memorySummary,
                ctx.capabilities
              ),
            });
            const postRetryParsed = this.parseIntent(postRetryCompletion).intent;
            if (postRetryParsed && postRetryParsed.name === 'PostMessage') {
              intent = postRetryParsed;
              intentSource = 'llm_post_due_retry';
              this.recordDecisionMemory(ctx, {
                decision: 'PostMessage',
                reason: 'llm_post_due_retry',
                context: {
                  personaId: persona.id,
                  inboxCount: ctx.gossip?.readInbox(this.id).length ?? 0,
                },
              });
            }
          }
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        this.recordDecisionMemory(ctx, {
          decision: 'no_op',
          reason: 'persona_llm_unavailable',
          context: {
            personaId: persona.id,
            requestedProvider: this.getParam<LlmProviderConfig['provider']>('provider', 'openai'),
            resolvedProvider: this.resolvedProvider ?? 'none',
            error: message,
          },
        });
      }
    }

    const adjustedIntent = this.applyPostingGuardrail(intent, ctx, observationDelta, intentSource);
    if (adjustedIntent !== intent) {
      intent = adjustedIntent;
      intentSource = 'ooda_posting_guardrail';
      this.recordDecisionMemory(ctx, {
        decision: 'PostMessage',
        reason: 'ooda_posting_guardrail',
        context: {
          personaId: persona.id,
          worldDelta: observationDelta.slice(0, 120),
          inboxCount: ctx.gossip ? ctx.gossip.readInbox(this.id).length : 0,
        },
      });
    }
    const action = this.intentToAction(intent, ctx, intentSource);
    const decisionName = action?.name ?? 'no_op';
    this.recordDecisionMemory(ctx, {
      decision: decisionName,
      reason: `persona_${persona.id}_${intentSource}`,
      context: {
        personaId: persona.id,
        source: intentSource,
        appCount: world.appCount,
        feesCollected: world.feesCollectedTotal.toString(),
        planHypothesis: String(
          (this.recall<{ hypothesis?: string }>('last_plan') ?? { hypothesis: 'none' }).hypothesis ??
            'none'
        ),
        worldDelta: observationDelta.slice(0, 240),
        memorySummary: memorySummary.slice(0, 240),
        intentTag: intent.metadata?.intentTag ?? 'none',
      },
    });
    return action;
  }

  private buildSystemPrompt(persona: PersonaProfile, stage: 'plan' | 'act'): string {
    const actions = ['QueryWorld', 'RpcCall', 'PostMessage', ...this.getAllowedProtocolActions()].join(', ');
    const postingPolicy = this.getParam<BaseElataPersonaLlmAgentParams['postingPolicy']>('postingPolicy', {
      preferredChannels: ['global'],
      onlyPostOnMaterialChange: true,
      maxPostChars: 240,
    });
    const channelHint = (postingPolicy?.preferredChannels ?? ['global']).join(', ');
    const gossipStyle = this.getPersonaGossipStyle(persona.id);
    return [
      'You are an autonomous Elata protocol simulation persona.',
      `Stage: ${stage}.`,
      `Persona id=${persona.id}; style=${persona.style}; risk=${persona.riskProfile}.`,
      `Goals: ${persona.goals.join(' | ')}`,
      `Constraints: ${(persona.constraints ?? []).join(' | ') || 'none'}`,
      `Prefer tools: ${(persona.preferredTools ?? []).join(', ') || 'any'}`,
      `Allowed actions: ${actions}`,
      `For QueryWorld, use endpoint "${this.getQueryEndpointHint()}" when uncertain.`,
      `For gossip, prefer channels: ${channelHint}; keep messages <= ${postingPolicy?.maxPostChars ?? 240} chars.`,
      `When posting gossip, use persona voice "${gossipStyle.voice}" and structure "${gossipStyle.structure}".`,
      `Posting should include a clear stance marker "${gossipStyle.marker}" and one concrete proposed next move.`,
      gossipStyle.concealIdentity
        ? `Do NOT disclose adversarial role. Publicly present as "${gossipStyle.publicCoverRole}" and frame intent as ecosystem-helpful while preserving private strategy.`
        : 'Be transparent about your viewpoint without revealing hidden chain-of-thought.',
      postingPolicy?.onlyPostOnMaterialChange
        ? 'Only post if material changes happened or if probing uncertainty.'
        : 'Posting cadence can be opportunistic within scenario budgets.',
      stage === 'plan'
        ? 'Return STRICT JSON only: {"hypothesis":"...","target":{"domain":"market|governance|fees|gossip|rpc|other","identifier":"..."},"expectedEffect":"...","preferredActionFamily":"QueryWorld|RpcCall|PostMessage|ContractCall|ContractRead|ProtocolAction","confidence":0.0}'
        : 'Return STRICT JSON only: {"name":"ActionName","params":{},"rationale":"...","metadata":{"personaId":"...","intentTag":"...","confidence":0.0}}. If postingPolicy.postTargetDue=true in user context, strongly prefer PostMessage with concise persona interpretation (not raw stat dump).',
    ].join(' ');
  }

  private buildUserPrompt(
    ctx: TickContext,
    plan: ParsedPlan,
    worldDelta: string,
    memorySummary: string,
    capabilities: CapabilityManifest | undefined
  ): string {
    const world = this.getWorldState();
    const inboxCount = ctx.gossip ? ctx.gossip.readInbox(this.id).length : 0;
    const maxPromptChars = this.getParam<number>('maxPromptChars', 4500);
    return JSON.stringify(
      {
        tick: ctx.tick,
        mode: ctx.mode ?? 'deterministic',
        world: {
          appCount: world.appCount,
          feesCollectedTotal: world.feesCollectedTotal.toString(),
          feesDistributed: world.feesDistributed.toString(),
          totalVeEltaLocked: world.totalVeEltaLocked.toString(),
          activeUsers24h: world.activeUsers24h,
        },
        gossipInboxCount: inboxCount,
        worldDelta,
        memorySummary,
        currentPlan: plan,
        capabilities: this.compactCapabilities(capabilities),
        lastResult: ctx.lastResult ?? null,
      },
      (_k, value) => (typeof value === 'bigint' ? value.toString() : value)
    ).slice(0, maxPromptChars);
  }

  private buildActionPrompt(
    ctx: TickContext,
    plan: ParsedPlan,
    worldDelta: string,
    memorySummary: string,
    capabilities: CapabilityManifest | undefined
  ): string {
    const postingSignal = this.computePostingSignal(ctx, worldDelta);
    const recentInbox =
      ctx.gossip?.readInbox(this.id).slice(-2).map((m) => String(m.payload?.text ?? '').slice(0, 140)) ?? [];
    const maxPromptChars = this.getParam<number>('maxPromptChars', 4500);
    return JSON.stringify(
      {
        tick: ctx.tick,
        mode: ctx.mode ?? 'deterministic',
        plan,
        worldDelta,
        memorySummary,
        postingPolicy: postingSignal,
        recentInbox,
        capabilities: this.compactCapabilities(capabilities),
        lastResult: ctx.lastResult ?? null,
      },
      (_k, value) => (typeof value === 'bigint' ? value.toString() : value)
    ).slice(0, maxPromptChars);
  }

  private buildPostRetryPrompt(
    ctx: TickContext,
    plan: ParsedPlan,
    worldDelta: string,
    memorySummary: string,
    capabilities: CapabilityManifest | undefined
  ): string {
    const postingSignal = this.computePostingSignal(ctx, worldDelta);
    const gossipStyle = this.getPersonaGossipStyle(this.getPersonaProfile().id);
    const recentInbox =
      ctx.gossip?.readInbox(this.id).slice(-3).map((m) => String(m.payload?.text ?? '').slice(0, 160)) ?? [];
    const maxPromptChars = this.getParam<number>('maxPromptChars', 4500);
    return JSON.stringify(
      {
        instruction:
          'Posting is due. Return only a PostMessage action JSON. Use concise persona interpretation grounded in recent inbox and current plan.',
        personaGossipStyle: gossipStyle,
        requiredAction: 'PostMessage',
        postingPolicy: postingSignal,
        tick: ctx.tick,
        plan,
        worldDelta,
        memorySummary,
        recentInbox,
        capabilities: this.compactCapabilities(capabilities),
      },
      (_k, value) => (typeof value === 'bigint' ? value.toString() : value)
    ).slice(0, maxPromptChars);
  }

  private parseIntent(raw: string): ParsedIntentDiagnostics {
    const payload = this.extractJsonPayload(raw);
    if (!payload) {
      return { intent: null, parseError: 'missing_json_object' };
    }
    let parsedJson: unknown;
    try {
      parsedJson = JSON.parse(payload);
    } catch {
      return { intent: null, parseError: 'invalid_json_payload' };
    }
    try {
      const parsed = LlmActionIntentSchema.parse(parsedJson);
      const metadata =
        parsed.metadata !== undefined
          ? {
              ...(parsed.metadata.personaId !== undefined
                ? { personaId: parsed.metadata.personaId }
                : {}),
              ...(parsed.metadata.intentTag !== undefined
                ? { intentTag: this.normalizeIntentTag(parsed.metadata.intentTag) }
                : {}),
              ...(parsed.metadata.confidence !== undefined
                ? { confidence: parsed.metadata.confidence }
                : {}),
            }
          : undefined;
      return {
        intent: {
          name: parsed.name,
          params: parsed.params,
          ...(parsed.rationale ? { rationale: parsed.rationale } : {}),
          ...(metadata ? { metadata } : {}),
        },
      };
    } catch {
      const salvaged = this.salvageIntent(parsedJson);
      if (salvaged) {
        return { intent: salvaged, salvaged: true, parseError: 'schema_parse_failed_salvaged' };
      }
      return { intent: null, parseError: 'schema_parse_failed' };
    }
  }

  private parsePlan(raw: string): ParsedPlan | null {
    try {
      const payload = this.extractJsonPayload(raw);
      if (!payload) return null;
      const parsed = LlmPlanIntentSchema.parse(JSON.parse(payload));
      return {
        hypothesis: parsed.hypothesis,
        expectedEffect: parsed.expectedEffect,
        ...(parsed.preferredActionFamily
          ? { preferredActionFamily: parsed.preferredActionFamily }
          : {}),
        ...(parsed.confidence !== undefined ? { confidence: parsed.confidence } : {}),
        ...(parsed.target
          ? {
              target: {
                domain: parsed.target.domain,
                identifier: parsed.target.identifier,
              },
            }
          : {}),
      };
    } catch {
      return null;
    }
  }

  private buildFallbackPlan(ctx: TickContext): ParsedPlan {
    return {
      hypothesis: `Tick ${ctx.tick}: choose highest utility safe action for persona.`,
      expectedEffect: 'Maintain forward progress with measurable state impact.',
      preferredActionFamily: 'QueryWorld',
      confidence: 0.35,
      target: {
        domain: 'other',
        identifier: 'world_state',
      },
    };
  }

  private buildObservationDelta(ctx: TickContext): string {
    const curr = {
      appCount: this.getWorldState().appCount,
      feesCollectedTotal: this.getWorldState().feesCollectedTotal.toString(),
      feesDistributed: this.getWorldState().feesDistributed.toString(),
      totalVeEltaLocked: this.getWorldState().totalVeEltaLocked.toString(),
      activeUsers24h: this.getWorldState().activeUsers24h,
      inboxCount: ctx.gossip ? ctx.gossip.readInbox(this.id).length : 0,
      lastResultOk: ctx.lastResult?.ok ?? null,
    };
    const prev = this.recall<Record<string, unknown>>('last_observation_compact', {});
    const changed = Object.entries(curr)
      .filter(([key, value]) => prev?.[key] !== value)
      .map(([key, value]) => `${key}:${String(value)}`);
    this.remember('last_observation_compact', curr);
    return changed.length > 0 ? changed.slice(0, 12).join(' | ') : 'no_material_change';
  }

  private buildMemorySummary(): string {
    const outcomes = this.recall<Array<{ family: string; ok: boolean }>>('outcome_summary', []) ?? [];
    if (outcomes.length === 0) return 'none';
    const grouped = new Map<string, { ok: number; fail: number }>();
    for (const item of outcomes) {
      const curr = grouped.get(item.family) ?? { ok: 0, fail: 0 };
      if (item.ok) curr.ok += 1;
      else curr.fail += 1;
      grouped.set(item.family, curr);
    }
    return [...grouped.entries()]
      .map(([family, counts]) => `${family}:ok=${counts.ok},fail=${counts.fail}`)
      .join(' | ');
  }

  private compactCapabilities(capabilities: CapabilityManifest | undefined): Record<string, unknown> {
    if (!capabilities) {
      return {
        fallback: true,
        tools: ['QueryWorld', 'RpcCall', 'PostMessage'],
        queryEndpoints: [{ name: 'get_world', cost: 1 }],
      };
    }
    return {
      version: capabilities.version,
      tools: capabilities.tools.slice(0, 12),
      queryEndpoints: capabilities.queryEndpoints.slice(0, 16),
      contracts: capabilities.contracts.slice(0, 16).map((c: CapabilityManifest['contracts'][number]) => ({
        alias: c.alias,
        ...(c.address ? { address: c.address } : {}),
      })),
    };
  }

  private intentToAction(intent: ParsedIntent, ctx: TickContext, llmSource: string): Action | null {
    const personaMetadata = {
      personaId: intent.metadata?.personaId ?? this.getPersonaProfile().id,
      ...(intent.metadata?.intentTag ? { intentTag: intent.metadata.intentTag } : {}),
      ...(intent.rationale ? { rationale: intent.rationale } : {}),
      llmSource,
    };
    if (intent.name === 'QueryWorld') {
      const endpoint = String(intent.params.endpoint ?? this.getQueryEndpointHint());
      const params =
        intent.params.params && typeof intent.params.params === 'object'
          ? (intent.params.params as Record<string, unknown>)
          : {};
      const action: Action = {
        id: this.generateActionId('QueryWorld', ctx.tick),
        name: 'QueryWorld',
        params: { endpoint, params },
        metadata: personaMetadata,
      };
      this.recordOutcomeFamily('QueryWorld', true);
      return action;
    }
    if (intent.name === 'RpcCall') {
      const method = String(intent.params.method ?? 'eth_blockNumber');
      const params = Array.isArray(intent.params.params) ? intent.params.params : [];
      const action: Action = {
        id: this.generateActionId('RpcCall', ctx.tick),
        name: 'RpcCall',
        params: { method, params },
        metadata: personaMetadata,
      };
      this.recordOutcomeFamily('RpcCall', true);
      return action;
    }
    if (intent.name === 'PostMessage') {
      const channelId = String(intent.params.channelId ?? 'global').trim() || 'global';
      const textRaw = String(intent.params.text ?? '').trim();
      const text = textRaw.length > 0 ? textRaw : this.buildFallbackGossipText(ctx);
      if (text.length === 0) {
        return this.createAction('noop', { type: 'noop', reason: 'empty_gossip_message' }, ctx.tick);
      }
      const intentTagRaw =
        typeof intent.params.intentTag === 'string'
          ? this.normalizeIntentTag(intent.params.intentTag)
          : 'other';
      const action: Action = {
        id: this.generateActionId('PostMessage', ctx.tick),
        name: 'PostMessage',
        params: {
          channelId,
          text,
          intentTag: intentTagRaw,
        },
        metadata: personaMetadata,
      };
      this.recordOutcomeFamily('PostMessage', true);
      this.remember('last_post_tick', ctx.tick);
      return action;
    }
    if (this.getAllowedProtocolActions().includes(intent.name)) {
      const action = this.createAction(
        intent.name,
        { type: intent.name, ...intent.params } as never,
        ctx.tick
      );
      this.recordOutcomeFamily('ProtocolAction', action !== null);
      if (!action) return null;
      return {
        ...action,
        metadata: {
          ...(action.metadata ?? {}),
          ...personaMetadata,
        },
      };
    }
    this.recordOutcomeFamily('ProtocolAction', false);
    return this.createAction('noop', { type: 'noop', reason: 'invalid_persona_intent' }, ctx.tick);
  }

  private recordOutcomeFamily(family: string, ok: boolean): void {
    const recent = this.recall<Array<{ family: string; ok: boolean }>>('outcome_summary', []) ?? [];
    recent.push({ family, ok });
    this.remember('outcome_summary', recent.slice(Math.max(0, recent.length - 24)));
  }

  private applyPostingGuardrail(
    intent: ParsedIntent,
    ctx: TickContext,
    worldDelta: string,
    intentSource: string
  ): ParsedIntent {
    if (!ctx.gossip || intent.name === 'PostMessage') {
      return intent;
    }
    if (intentSource.startsWith('llm_')) {
      return intent;
    }
    const lowSignalActions = new Set(['noop', 'QueryWorld', 'RpcCall']);
    if (!lowSignalActions.has(intent.name)) {
      return intent;
    }
    const policy = this.getParam<BaseElataPersonaLlmAgentParams['postingPolicy']>('postingPolicy', {});
    const minPostEveryTicks = Math.max(0, Number(policy?.minPostEveryTicks ?? 0) || 0);
    const postOnInboxThreshold = Math.max(0, Number(policy?.postOnInboxThreshold ?? 0) || 0);
    const postOnMaterialChange = Boolean(
      policy?.postOnMaterialChange ?? policy?.onlyPostOnMaterialChange ?? false
    );
    const lastPostTickRaw = this.recall<number>('last_post_tick', -1);
    const lastPostTick = typeof lastPostTickRaw === 'number' ? lastPostTickRaw : -1;
    const ticksSincePost = lastPostTick >= 0 ? ctx.tick - lastPostTick : Number.POSITIVE_INFINITY;
    const inboxCount = ctx.gossip.readInbox(this.id).length;
    const materialChange = worldDelta !== 'no_material_change';
    const cadenceDue =
      minPostEveryTicks > 0 && lastPostTick >= 0 && ticksSincePost >= minPostEveryTicks;
    const inboxDue = postOnInboxThreshold > 0 && inboxCount >= postOnInboxThreshold;
    const materialDue = postOnMaterialChange && materialChange;
    if (!cadenceDue && !inboxDue && !materialDue) {
      return intent;
    }
    const personaId = this.getPersonaProfile().id;
    const channelId = String(policy?.preferredChannels?.[0] ?? 'global').trim() || 'global';
    const basis = cadenceDue ? 'cadence' : inboxDue ? 'inbox' : 'material_change';
    const latestInbox = ctx.gossip.readInbox(this.id).at(-1);
    const inboxText = String(latestInbox?.payload?.text ?? '').replace(/\s+/g, ' ').trim();
    const planHypothesis = String(
      (this.recall<{ hypothesis?: string }>('last_plan') ?? { hypothesis: '' }).hypothesis ?? ''
    )
      .replace(/\s+/g, ' ')
      .trim();
    const text = inboxText
      ? `persona=${personaId} basis=${basis} reacts:${inboxText.slice(0, 170)}`
      : `persona=${personaId} basis=${basis} hypothesis:${planHypothesis.slice(0, 170)} delta:${worldDelta.slice(0, 90)}`;
    return {
      name: 'PostMessage',
      params: {
        channelId,
        text,
        intentTag: this.normalizeIntentTag(personaId),
      },
      rationale: 'Share concise world update due to posting guardrail trigger.',
      metadata: {
        personaId,
        intentTag: this.normalizeIntentTag(personaId),
        confidence: 0.51,
      },
    };
  }

  private shouldRequestLlmPostRetry(
    ctx: TickContext,
    worldDelta: string,
    intent: ParsedIntent,
    intentSource: string
  ): boolean {
    if (!ctx.gossip || !intentSource.startsWith('llm_')) return false;
    if (intent.name === 'PostMessage') return false;
    const lowSignalActions = new Set(['noop', 'QueryWorld', 'RpcCall']);
    if (!lowSignalActions.has(intent.name)) return false;
    const signal = this.computePostingSignal(ctx, worldDelta);
    return signal.postTargetDue;
  }

  private computePostingSignal(
    ctx: TickContext,
    worldDelta: string
  ): {
    postTargetDue: boolean;
    preferredChannel: string;
    maxChars: number;
    rationale: string;
  } {
    const policy = this.getParam<BaseElataPersonaLlmAgentParams['postingPolicy']>('postingPolicy', {});
    const minPostEveryTicks = Math.max(0, Number(policy?.minPostEveryTicks ?? 0) || 0);
    const postOnInboxThreshold = Math.max(0, Number(policy?.postOnInboxThreshold ?? 0) || 0);
    const postOnMaterialChange = Boolean(
      policy?.postOnMaterialChange ?? policy?.onlyPostOnMaterialChange ?? false
    );
    const lastPostTickRaw = this.recall<number>('last_post_tick', -1);
    const lastPostTick = typeof lastPostTickRaw === 'number' ? lastPostTickRaw : -1;
    const ticksSincePost = lastPostTick >= 0 ? ctx.tick - lastPostTick : Number.POSITIVE_INFINITY;
    const inboxCount = ctx.gossip ? ctx.gossip.readInbox(this.id).length : 0;
    const materialChange = worldDelta !== 'no_material_change';
    const cadenceDue =
      minPostEveryTicks > 0 &&
      ((lastPostTick >= 0 && ticksSincePost >= minPostEveryTicks) ||
        (lastPostTick < 0 && ctx.tick >= minPostEveryTicks));
    const inboxDue = postOnInboxThreshold > 0 && inboxCount >= postOnInboxThreshold;
    const materialDue = postOnMaterialChange && materialChange;
    const due = cadenceDue || inboxDue || materialDue;
    const rationale = cadenceDue
      ? 'cadence_due'
      : inboxDue
        ? 'inbox_due'
        : materialDue
          ? 'material_change_due'
          : 'not_due';
    return {
      postTargetDue: due,
      preferredChannel: String(policy?.preferredChannels?.[0] ?? 'global'),
      maxChars: Math.max(80, Number(policy?.maxPostChars ?? 240) || 240),
      rationale,
    };
  }

  private buildFallbackGossipText(ctx: TickContext): string {
    const personaId = this.getPersonaProfile().id;
    const gossipStyle = this.getPersonaGossipStyle(personaId);
    const inbox = ctx.gossip?.readInbox(this.id) ?? [];
    const recentInboxText = String(inbox.at(-1)?.payload?.text ?? '')
      .replace(/\s+/g, ' ')
      .trim();
    const hypothesis = String(
      (this.recall<{ hypothesis?: string }>('last_plan') ?? { hypothesis: '' }).hypothesis ?? ''
    )
      .replace(/\s+/g, ' ')
      .trim();
    const text = recentInboxText
      ? `${gossipStyle.marker} reaction:${recentInboxText.slice(0, 150)} | next:${gossipStyle.defaultNextMove}`
      : `${gossipStyle.marker} thesis:${hypothesis.slice(0, 140) || 'state unchanged, monitoring'} | next:${gossipStyle.defaultNextMove}`;
    return text.slice(0, 240);
  }

  private getPersonaGossipStyle(personaId: string): {
    voice: string;
    structure: string;
    marker: string;
    defaultNextMove: string;
    concealIdentity: boolean;
    publicCoverRole: string;
  } {
    const key = personaId.trim().toLowerCase();
    if (key === 'creator') {
      return {
        voice: 'builder-optimistic',
        structure: 'signal -> opportunity -> proposed build action',
        marker: '[CREATOR]',
        defaultNextMove: 'prototype app iteration',
        concealIdentity: false,
        publicCoverRole: 'builder',
      };
    }
    if (key === 'economic') {
      return {
        voice: 'allocator-analytical',
        structure: 'market read -> risk/reward -> allocation move',
        marker: '[ECON]',
        defaultNextMove: 'rebalance toward strongest app signal',
        concealIdentity: false,
        publicCoverRole: 'allocator',
      };
    }
    if (key === 'bad_actor') {
      return {
        voice: 'confident-market-analyst',
        structure: 'market narrative -> selective recommendation -> momentum nudge',
        marker: '[MARKET]',
        defaultNextMove: 'encourage concentrated flow into a target venue',
        concealIdentity: true,
        publicCoverRole: 'market strategist',
      };
    }
    if (key === 'saboteur') {
      return {
        voice: 'risk-off-compliance',
        structure: 'risk advisory -> caution framing -> reallocation suggestion',
        marker: '[RISK]',
        defaultNextMove: 'promote rapid rotations under the guise of risk control',
        concealIdentity: true,
        publicCoverRole: 'risk advisor',
      };
    }
    if (key === 'hacker') {
      return {
        voice: 'technical-probing',
        structure: 'anomaly note -> attack surface -> probe action',
        marker: '[HACKER]',
        defaultNextMove: 'probe edge-case path with targeted rpc checks',
        concealIdentity: false,
        publicCoverRole: 'security researcher',
      };
    }
    return {
      voice: 'neutral-observer',
      structure: 'observation -> implication -> next step',
      marker: '[PERSONA]',
      defaultNextMove: 'collect one more high-signal observation',
      concealIdentity: false,
      publicCoverRole: 'observer',
    };
  }

  private extractJsonPayload(raw: string): string | null {
    const normalized = raw.trim();
    if (!normalized) return null;
    if (normalized.startsWith('{') && normalized.endsWith('}')) {
      return normalized;
    }
    const lines = normalized
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.startsWith('{') && line.endsWith('}'));
    for (let i = lines.length - 1; i >= 0; i -= 1) {
      const line = lines[i];
      if (line) return line;
    }
    const start = normalized.indexOf('{');
    const end = normalized.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return normalized.slice(start, end + 1);
  }

  private normalizeIntentTag(raw: unknown): string {
    const tag = String(raw ?? '').trim().toLowerCase();
    if (!tag) return 'other';
    return tag;
  }

  private salvageIntent(payload: unknown): ParsedIntent | null {
    if (!payload || typeof payload !== 'object') return null;
    const candidate = payload as Record<string, unknown>;
    const name = typeof candidate.name === 'string' && candidate.name.trim().length > 0
      ? candidate.name.trim()
      : null;
    if (!name) return null;
    const params = candidate.params && typeof candidate.params === 'object'
      ? (candidate.params as Record<string, unknown>)
      : {};
    const rationale = typeof candidate.rationale === 'string' ? candidate.rationale : undefined;
    const metadataRaw =
      candidate.metadata && typeof candidate.metadata === 'object'
        ? (candidate.metadata as Record<string, unknown>)
        : {};
    const metadata = {
      ...(typeof metadataRaw.personaId === 'string' && metadataRaw.personaId.trim().length > 0
        ? { personaId: metadataRaw.personaId.trim() }
        : {}),
      ...(metadataRaw.intentTag !== undefined
        ? { intentTag: this.normalizeIntentTag(metadataRaw.intentTag) }
        : {}),
      ...(typeof metadataRaw.confidence === 'number' &&
      Number.isFinite(metadataRaw.confidence) &&
      metadataRaw.confidence >= 0 &&
      metadataRaw.confidence <= 1
        ? { confidence: metadataRaw.confidence }
        : {}),
    };
    return {
      name,
      params,
      ...(rationale ? { rationale } : {}),
      ...(Object.keys(metadata).length > 0 ? { metadata } : {}),
    };
  }
}
