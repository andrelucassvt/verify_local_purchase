---
name: brainstorming
description: Explora intenção, requisitos e design antes da implementação. Use antes de qualquer trabalho criativo — criar features, construir componentes, adicionar funcionalidade ou modificar comportamento existente.
license: MIT
metadata:
  version: "2.4.0"
---

# Brainstorming

Explora intenção e design antes de qualquer implementação e encerra com um design aprovado + um bloco **Handoff** que o `writing-plan` consome. Não escreve código nem gera o plano.

**Entrada:** o pedido do usuário — primeiro elo da cadeia, não depende de artefato anterior. **Saída:** design aprovado + bloco **Handoff para o Plano** (Fase 4), que sobrevive à compactação de contexto entre as skills.

### Referências

Resolvida a partir do diretório desta skill:

| Arquivo | Quando ler |
|---------|-----------|
| `references/design-review.md` | Na Fase 3, com o design escrito e ainda não apresentado — rubrica de aceite com anti-padrões por dimensão |

---

## Fase 0 — Vale brainstorming?

Siga o fluxo completo quando houver criação ou decisão de comportamento, experiência, arquitetura, regra de negócio ou interação entre componentes.

Dispense quando a mudança for puramente mecânica — nenhuma decisão a tomar porque a solução já está determinada pelo pedido, pelo padrão existente ou pela natureza da correção. Nesse caso, registre em uma frase por que não há design a decidir e libere a execução direta. Se surgir qualquer escolha com impacto observável, volte ao fluxo completo. A classificação só sobe: complexidade descoberta no meio leva ao fluxo completo; nada volta a mecânico.

Se o pedido for uma **pergunta de viabilidade** ("dá para…?", "é possível…?"), a saída é uma resposta, não um design: diga em 2–3 linhas o que vai investigar, investigue pelo caminho mais barato que ainda responda com precisão e devolva uma recomendação. Código produzido nesse caminho é descartável e sai rotulado como tal — mantê-lo é um pedido novo, que volta à Fase 0.

---

## Fase 1 — Intenção e contexto

Primeiro fixe **o quê** o usuário quer, **por quê**, **onde** (features, telas e camadas afetadas) e **qual o impacto** no comportamento atual. Antes de perguntar detalhes, olhe o escopo: se o pedido descreve subsistemas independentes, diga isso primeiro, proponha a ordem e trate só o primeiro nesta rodada — cada subsistema tem o próprio ciclo brainstorming → plano → execução. Multi-parte (`writing-plan`) é para **um** design com várias entregas, não para vários designs num pedido. Se o pedido for ambíguo, faça **uma pergunta de clarificação por vez**, de preferência com opções, começando pela que mais altera o design; não pergunte o que dá para inferir com segurança do código; pare quando houver contexto para comparar abordagens.

Depois reúna o contexto já existente:

- **Flows**: rode `grep -n '\*\*Resumo:\*\*' docs/flow/*.md` para ver nome + resumo de **todos** os flows de uma vez e escolher por **relevância semântica** — não só por correspondência de nome — quais abrir por completo (use `project-structure.md` para o geral). Leia integralmente só os relevantes, aproveitando arquivos envolvidos, ordem de execução, regras de negócio, pontos frágeis e dependências. Se o `grep` não retornar nada (flows sem a linha de resumo), caia para `ls ./docs/flow/` e selecione pelo nome. Sem pasta ou flows: siga sem contexto documental e sugira `flow-init` ao final, sem bloquear.
- **Skill `*-expert`** da stack: procure candidatos `*-expert` em **uma única fonte** — o catálogo de skills da plataforma, ou a raiz nativa (`.claude/skills` no Claude Code, `.agents/skills` no Codex), usando a outra raiz apenas como fallback; nunca agregue as duas. Se achar, leia só o `SKILL.md` (nunca os `references/`) e extraia stack, arquitetura proposta e a tabela de "quando ler cada referência". A brainstorming **referencia** a expert — não invoca, não copia código. Se não achar, use só o arquivo nativo de instruções (`CLAUDE.md` no Claude Code, `AGENTS.md` no Codex).

---

## Fase 2 — Entrega única

Contexto, alternativas e design saem em **uma única resposta**. Briefing e design em turnos separados dobram o texto sem acrescentar informação.

**O que entra:** só o que o usuário ainda não sabe. Ele conhece o próprio projeto — descreva o estado atual apenas onde algum detalhe muda o design. Seção sem conteúdo real é **omitida**, nunca preenchida com texto de encher.

**Orçamento:** mudança pequena ≤ 15 linhas, mudança ampla ≤ 40 (sem contar o Handoff). Estourou, corte uma seção — não comprima a prosa.

```markdown
**[decisão recomendada em uma linha]** · [UI-only|Logic] · [N] arquivos

⚠️ [risco, conflito ou deprecated com substituto — linha inteira omitida se não houver]

| Opção | O que muda | Trade-off |
|---|---|---|
| **A — [nome]** ✅ | [uma frase] | [o critério deste projeto que a escolheu] |
| B — [nome] | [uma frase] | [o que a derrubou] |

**Design**
- `caminho/real.ext` — [o que muda ali]
- Fluxo: [origem → destino, uma linha]
- Erros: [caso limite e resposta]
- Verificação: [teste ou checagem, se houver comportamento testável]
```

A tabela só existe quando há **decisão real** — duas abordagens plausíveis que mudam responsabilidades, dependências, experiência, manutenção, risco ou testabilidade. No caminho direto, troque a tabela por uma linha dizendo o que determina a abordagem (padrão existente ou o próprio pedido) e vá direto ao Design.

O ✅ marca a recomendação — o Trade-off dela precisa apontar o padrão, a regra de negócio ou o custo concreto **deste** repositório, nunca adjetivo genérico ("mais simples", "mais escalável"). Mudança ampla se apresenta em partes coesas, cada uma dentro do orçamento.

---

## Fase 3 — Auditar antes de apresentar

Com o design escrito e ainda não apresentado, leia `references/design-review.md` e aplique a rubrica de aceite às seis dimensões (fidelidade à intenção, alternativas honestas, proporcionalidade, densidade, handoff derivável, precisão). Corrija o que a rubrica reprovar e só então leve o design ao usuário.

Esta é a única passada de auto-crítica da skill, e é o gate de entrada da cadeia: um defeito que passa daqui chega ao plano como escopo aprovado e à execução como código. Em design apresentado em partes coesas, audite cada parte antes de apresentá-la.

---

## Fase 4 — Aprovação e handoff

Peça **aprovação explícita** do design antes de criar um plano ou implementar. Se o usuário pedir ajustes, revise só as partes afetadas e reconfirme. Aprovação de design **não** autoriza alterar código.

Após a aprovação:

- Mudança com múltiplas etapas → recomende ou use `writing-plan` para gerar o plano e entregue o **Handoff** abaixo.
- Mudança pequena e direta → informe que pode seguir direto à implementação, se o usuário preferir; o handoff é dispensável.

### Handoff para o Plano

Interface de máquina, não leitura humana: o `writing-plan` copia este bloco para a seção **Design de Origem** do plano, tornando-o auto-contido. Entregue-o no fim, depois da aprovação, sob a linha `<!-- para o writing-plan -->`, para o usuário saber que pode pular. Preencha só o que se aplica:

```markdown
<!-- para o writing-plan -->
## Handoff para o Plano
- **Decisão aprovada:** [opção escolhida em uma frase]
- **Alternativas descartadas:** [opção + motivo curto, ou "nenhuma — caminho direto"]
- **Tipo de mudança:** UI-only | Logic
  <!-- UI-only: só View/layout/estilo/rota sem lógica nova, textos, assets.
       Logic: toca estado/domínio/serviço/repositório/datasource/HTTP/banco.
       Você acabou de desenhar a solução — decida aqui, não deixe o writing-plan re-derivar. -->
- **Arquivos-chave:** [caminhos reais citados no design]
- **Skill expert:** `<nome-expert>` + referências relevantes, ou "nenhuma encontrada"
- **Flows a revisitar após implementação:** `docs/flow/<nome>.md` — [seções], ou "nenhum"
- **Restrições globais:** [valor exato, piso de versão, nome/texto obrigatório, dependência proibida — uma por linha, ou omitir a linha]
```

**Tipo de mudança** é a única classificação de TDD da cadeia — o `writing-plan` a reutiliza em vez de reclassificar. A atualização final dos flows pertence à execução (`executing-plan`), não ao brainstorming.

---

## Regras Gerais

**Não bloqueie** — sem flows, a entrega ainda vale (design + próximo passo). Nunca impeça o trabalho por falta de documentação.

Precisão das citações e uso de API deprecated são auditados na Fase 3 (B10 e B11 do catálogo), não repetidos aqui.
