---
name: executing-plan
description: Executa um plano de implementação Markdown já criado em ./docs/plan/, revisando-o antes de começar, retomando pelo primeiro checkbox pendente, implementando uma tarefa por vez, verificando cada etapa, marcando o progresso e atualizando flows afetados. Use quando o usuário pedir para executar, implementar, continuar ou retomar um plano existente, como "execute o plano", "implemente o plano", "continue o plano" ou "retome de onde parou".
license: MIT
metadata:
  version: "2.4.0"
---

# Executing Plan

Executa um plano existente sem misturar planejamento e implementação. O plano em `./docs/plan/` é a fonte de verdade do progresso: cada tarefa é verificada antes de ser marcada.

Não cria planos novos; para isso, encaminhe a `writing-plan`. A entrada ideal tem **Design de Origem**, que preserva a decisão aprovada durante o tratamento de drift. A saída é código verificado, plano atualizado e flows afetados relinkados ao plano.

### Referências

Resolvida a partir do diretório desta skill:

| Arquivo | Quando ler |
|---------|-----------|
| `references/multi-part-execution.md` | No passo 1, quando o plano for uma pasta com índice e partes |
| `references/completion-review.md` | No passo 7 — lida pelo revisor independente ou pela própria thread |

---

## Fluxo de execução

### 1. Localizar e ler o plano completo

Use o caminho informado. Se o usuário disser apenas "o plano", liste `./docs/plan/` e selecione o candidato compatível; pergunte somente se houver ambiguidade real.

**Plano multi-parte** (pasta com `00-indice.md` + partes numeradas): leia `references/multi-part-execution.md` antes de continuar.

**Plano de arquivo único:** leia-o inteiro antes de alterar código e identifique objetivo, critérios, **Design de Origem**, arquivos, ordem/dependências, verificações, riscos, rollback, flows relacionados e o primeiro checkbox pendente.

### 2. Revisar criticamente antes de executar

Confronte o plano com o repositório: procure arquivos movidos, contratos incompatíveis, passos vagos, dependências ausentes, ordem inexequível e verificações insuficientes. Confronte cada fase com as **Restrições globais** do Design de Origem — restrição violada é conflito, não detalhe.

Antes do primeiro checkbox, rode a análise estática e a suíte existente do projeto (no harness, sem subir o app) e registre o resultado e `git rev-parse --short HEAD` no cabeçalho do plano (`> **Base da execução:** abc1234 — análise limpa, 42/42 testes`). Baseline vermelho não é seu para corrigir: relate e pergunte se segue — falha que já existia não pode virar achado da revisão final. O commit-base é o início do range que a revisão final (passo 7) recebe.

Se estiver em `main`/`master`, pergunte uma vez se cria uma branch antes de começar — sem criar por conta própria.

Se estiver executável, informe em uma frase por onde começa. Ajuste apenas drift pequeno e inequívoco, registrando o motivo no plano. Se mudar escopo, arquitetura, comportamento, critérios ou contrariar a **Decisão aprovada**, pare e apresente o conflito ao usuário.

### 3. Retomar pelo progresso real

Comece no primeiro checkbox pendente com dependências satisfeitas. Não repita itens marcados, salvo evidência invalidada por mudança posterior; nesse caso, rerode apenas a verificação afetada e registre o motivo. Checkbox representa trabalho comprovado.

### 4. Executar uma tarefa por vez

Para cada checkbox, leia os arquivos relacionados, faça apenas a alteração necessária, rode a verificação definida, confira saída/status/falhas, marque `- [x]` só com evidência e avance.

Verificação que falha pede causa antes de correção: leia a saída inteira, reproduza, mude uma coisa por vez. Três correções falhas na mesma tarefa não pedem a quarta — pedem parar e relatar o que foi tentado. Se falhar, mantenha desmarcado e corrija dentro do escopo.

Ambiguidade que a **Decisão aprovada** e as **Restrições globais** não contradizem é sua para resolver: escolha, registre no plano sob `## Decisões durante a execução` como `Decisão: o quê — por quê — custo se estiver errada` e siga. Escolha de design que aparece durante uma tarefa não é drift pequeno — é decisão nova, tratada como acima. Pare somente por: operação destrutiva ou irreversível; credencial, segredo ou permissão que você não tem; efeito fora do repositório (push, publicação, merge, chamada externa com side effect); contradição com o Design de Origem; ou plano em que todo caminho adiante é chute. Nunca troque verificação indisponível por afirmação; registre o que foi comprovado.

### 5. Manter o arquivo do plano atualizado

Além dos checkboxes, atualize o plano somente para registrar caminho alterado por drift, comando corrigido, bloqueio/desvio aprovado ou evidência concreta. Não o reescreva nem amplie o escopo.

### 6. Atualizar flows afetados

Depois da implementação e antes da revisão final, atualize um flow existente se mudarem arquivos participantes, responsabilidade, ordem, regra de negócio, erro/fallback, rota, DI, persistência ou integração externa.

Use a skill `flow` como fonte de verdade, preserve seções customizadas e renove seus metadados de verificação. Ao atualizar um flow, inclua o caminho deste plano no campo `related_plans` do frontmatter dele, fechando a rastreabilidade `plano → flow`. Mudanças internas que preservam a estrutura e o comportamento documentado não exigem atualização.

Se não existir flow relacionado, não crie um automaticamente: registre a ausência e sugira invocar a skill `flow` para documentá-lo na entrega.

### 7. Revisar a conclusão

Ao chegar ao fim, rode as verificações finais definidas no plano para detectar regressões. Em seguida leia `references/completion-review.md` e aplique a rubrica de conclusão às cinco dimensões (cobertura, evidência, fidelidade, integridade, rastreabilidade), corrigindo o que ela reprovar.

Um zero em qualquer dimensão impede declarar o plano concluído. Se ele não se resolver dentro do escopo — dependência externa, verificação indisponível, correção que mudaria o design aprovado — relate o bloqueio e o que ficou comprovado, em vez de fechar o plano.

**Revisão independente:** quando a mudança for `Logic` ou o plano tiver 3+ fases, e o ambiente oferecer subagente, despache um revisor em contexto limpo com o caminho do plano (incluindo Design de Origem, critérios e **Restrições globais** como lente), o **arquivo** de diff (`git log --oneline`, `git diff --stat` e `git diff -U10 <base>..HEAD` redirecionados para um único arquivo fora do repositório, ex.: o scratchpad da sessão — o diff não entra no seu contexto) e os arquivos novos/não rastreados do escopo, e o caminho de `references/completion-review.md`. Se o despacho contiver "não sinalize", "no máximo menor" ou "o plano escolheu" — pare, você está poupando a si mesmo de uma rodada. O revisor devolve nota por dimensão e achados com arquivo/linha; a thread corrige os achados e só então declara conclusão. Fora dessas condições, ou sem subagente, aplique a rubrica na própria thread. Achado sem evidência do revisor não reprova; "concluído" sem evidência do revisor não aprova.

Corrigido um achado, a re-verificação é **escopada**: só os achados abertos e o diff da correção, com veredito por achado (atendido / não atendido) e quebra nova nesse diff — nunca uma revisão completa de novo; achado fora do diff da correção entra como observação, não reabre o loop. Em parte delegada, quem corrige é o mesmo subagente (retomado, ou redespachado com o arquivo da parte + achados). Duas rodadas; na terceira, adjudique cada achado aberto com uma Decisão registrada e siga — pare só se o achado contrariar o Design de Origem ou bloquear fase posterior.

Só declare o plano concluído quando todos os itens obrigatórios estiverem marcados e as verificações atuais sustentarem essa afirmação.

---

## Regras gerais

**Plano como fonte de verdade** — o estado dos checkboxes deve permitir retomar o trabalho após interrupção ou compactação de contexto.

**Escopo controlado** — problemas não relacionados encontrados durante a execução devem ser relatados, não incorporados silenciosamente.

**Verificação proporcional** — use exatamente as evidências previstas no plano e amplie apenas quando a alteração revelar risco de regressão diretamente relacionado. Testes no harness (unitários e de componente headless) são evidência válida; subir app, servidor, emulador, simulador, dispositivo, browser real, screenshot ou interação visual não é — a validação funcional é do usuário.

**Idioma do plano** — preserve o idioma em que o plano foi escrito ao atualizá-lo.

**Narração mínima** — entre tarefas, no máximo uma linha; o plano e as saídas das verificações são o registro.

**Disciplina sob pressão** — a forma da regra segue o tipo de falha:

| Pensamento | Realidade |
|---|---|
| "Marco agora e verifico no fim" | Checkbox é trabalho comprovado. Verificação depois é afirmação. |
| "A verificação de antes ainda vale" | Vale para o código de antes. Mudou, rerode. |
| "Subo o app só para confirmar" | Validação funcional é do usuário. Análise, build e harness são o seu limite. |
| "Corrijo isso já que estou aqui" | Escopo infiltrado (E6). Relate, não incorpore. |
| "Achado pequeno, pulo a re-verificação" | Correção sem verificação é como regressão entra. Re-verifique escopado. |
| "Paro e pergunto, é mais seguro" | Se não contraria o Design de Origem nem é irreversível, decida e registre. Parar custa o dia do usuário. |

---

## Ao finalizar

Informe:

- Caminho do plano executado
- Tarefas e arquivos principais concluídos
- Verificações rodadas e seus resultados
- Flows atualizados, se houver
- Decisões tomadas durante a execução, na ordem e **exaustivas**, cada uma com o custo se estiver errada — é o único lugar em que elas chegam ao usuário
- Itens pendentes ou validações manuais do usuário, se houver

Não chame um plano de concluído se restar bloqueio ou critério obrigatório sem evidência.
