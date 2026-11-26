# Painel de Suporte TI

Painel em PowerShell para o suporte do dia a dia em máquinas Windows. Reúne num menu só as rotinas que a TI mais repete: limpeza de temporários, reparo do Windows, rede, fila de impressão, drivers, Intune, cache do Teams, ficha completa do hardware e outras. Tudo o que é feito fica registrado em log no próprio PC.

```
============================================================
              PAINEL DE SUPORTE DA TI
============================================================
 PC: NOTE-FINANCEIRO02   Usuário logado: EMPRESA\maria.souza

--- MANUTENÇÃO DO SISTEMA ---
 [ 1] Limpeza de arquivos temporários
 [ 2] Limpeza de disco avançada
 ...
```

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 (já vem no Windows)
- Conta com permissão de administrador
- Internet para DISM, drivers, Windows Update e testes de conexão

## Como usar

1. Copie a pasta inteira para o PC (ou extraia o `.zip`). Os dois arquivos precisam ficar juntos.
2. Dê dois cliques em **`Abrir Painel TI.bat`**.
3. Aceite o pedido de administrador do Windows.
4. Digite o número da opção e Enter. `0` sai do painel.

O `.bat` abre o PowerShell como administrador com `-ExecutionPolicy Bypass`, então não é preciso mudar a política de execução da máquina. Se o script for aberto sem permissão de admin, ele avisa e fecha.

### Usuário logado x conta da TI

Quando a TI entra com a própria conta de admin no PC de outra pessoa, o Windows roda o script no perfil da TI. Por isso o painel descobre **quem está logado na máquina** e aplica a limpeza de Temp, o cache do Teams e as entradas de inicialização do registro no perfil dessa pessoa, e não no do admin. O nome dela aparece no topo do menu.

## Configuração

Antes de distribuir, ajuste o endereço do SharePoint da empresa no início do [`PainelTI.ps1`](PainelTI.ps1). Ele é usado no teste de conectividade (opção 9):

```powershell
$SharePointEmpresa = 'suaempresa.sharepoint.com'
```

## Opções

### Manutenção do sistema

| Nº | Opção | O que faz |
|---:|---|---|
| 1 | Limpeza de arquivos temporários | Limpa o Temp do Windows e o do usuário logado. Mantém arquivos em uso e os com menos de 1 dia. Mostra quanto foi liberado. |
| 2 | Limpeza de disco avançada | Abre a Limpeza de Disco do Windows (`cleanmgr`), que inclui arquivos de sistema e de atualizações. |
| 3 | Verificar e reparar arquivos do Windows | Roda `sfc /scannow`. Leva de 10 a 20 minutos. |
| 4 | Reparar a imagem do Windows | Roda `DISM /RestoreHealth`. Precisa de internet; depois, rode o SFC de novo. |
| 5 | Verificar o disco C: | Roda `chkdsk C: /scan` (somente leitura, sem reiniciar). |
| 6 | Saúde do disco (HD/SSD) | Mostra saúde, temperatura, desgaste e erros de leitura de cada disco, e o espaço livre das unidades. |
| 25 | Corrigir registro do Windows | Procura programas de inicialização e "programas fantasma" em *Aplicativos instalados* cujos arquivos não existem mais. Lista o que achou, pede confirmação, cria ponto de restauração e backup `.reg` antes de remover. |
| 27 | Criar ponto de restauração | Cria um ponto de restauração com a descrição informada, confere se o Windows o registrou e lista os últimos pontos. Se a Proteção do Sistema estiver desligada, oferece ligar. |

### Rede e internet

| Nº | Opção | O que faz |
|---:|---|---|
| 7 | Reset de rede | Libera e renova o IP, limpa o DNS e redefine Winsock e TCP/IP. **Exige reiniciar o PC.** |
| 8 | Informações de rede | IP, gateway e DNS das placas conectadas, e SSID e sinal do Wi-Fi. |
| 9 | Testes de conectividade | Testa roteador, internet, DNS, Microsoft 365, SharePoint da empresa e Teams, e explica como ler o resultado. |
| 10 | Limpar cache de DNS | `ipconfig /flushdns`. |
| 11 | Abrir Conexões de Rede | Abre o `ncpa.cpl`. |

### Impressão

| Nº | Opção | O que faz |
|---:|---|---|
| 12 | Limpar fila de impressão travada | Para o Spooler, apaga os trabalhos presos e inicia o serviço de novo. |
| 13 | Listar impressoras | Nome, status, porta e qual é a padrão. |

### Diagnóstico

| Nº | Opção | O que faz |
|---:|---|---|
| 14 | Informações do sistema | Modelo, número de série, Windows, processador, memória, espaço no C: e há quantos dias o PC está ligado. |
| 15 | Especificações completas | Ficha da máquina: computador, BIOS, processador, memória pente a pente, discos, vídeo, monitores, rede e bateria (em notebooks). Pode salvar em `.txt` e copiar para a área de transferência. |
| 16 | Monitor de recursos e processos | Os 10 processos que mais usam memória e abre o Monitor de Recursos. |

### Drivers e atualizações

| Nº | Opção | O que faz |
|---:|---|---|
| 17 | Dispositivos com erro | Lista dispositivos com problema no Gerenciador de Dispositivos e oferece buscar drivers. |
| 18 | Atualizar drivers | Busca drivers pendentes no Windows Update, lista e instala após confirmação. |
| 19 | Backup dos drivers | Exporta todos os drivers instalados para uma pasta. |
| 20 | Procurar atualizações do Windows | Inicia a busca e abre a tela do Windows Update. |

### Microsoft 365

| Nº | Opção | O que faz |
|---:|---|---|
| 21 | Vínculo com a Microsoft | Mostra pelo `dsregcmd /status` se o PC está ligado ao Entra ID (Azure AD). |
| 22 | Sincronizar com o Intune | Dispara a sincronização de políticas e apps do Intune. |
| 23 | Limpar cache do Teams | Fecha o Teams do usuário logado e limpa o cache (Teams novo e clássico). Conversas e arquivos não são apagados. |

### Segurança e TI

| Nº | Opção | O que faz |
|---:|---|---|
| 26 | Desligar/ligar Defender e Firewall | Mostra a situação atual e liga ou desliga a proteção em tempo real do Defender e o Firewall em todos os perfis. |
| 24 | Ver registro de ações deste PC | Últimas 20 linhas do log. |

## Arquivos gerados

Tudo fica em `C:\ProgramData\PainelTI\`:

| Arquivo | Conteúdo |
|---|---|
| `painel.log` | Cada ação: data, PC, conta que rodou e o que foi feito. Erros também entram aqui. |
| `Ficha_<PC>_<data>.txt` | Ficha da opção 15, quando salva. |
| `Registro_<PC>_<data>\*.reg` | Backup feito pela opção 25 antes de remover entradas. Dois cliques num `.reg` desfazem a correção. |
| `Drivers_<PC>_<data>\` | Drivers exportados pela opção 19. |

## Cuidados

- **Defender e Firewall (26):** desligar deixa o PC exposto. Use só para um teste rápido e volte para ligar. Com a Proteção contra Adulteração ativa, o Windows não deixa desligar o Defender por script.
- **Reset de rede (7):** o PC perde a rede na hora e precisa reiniciar.
- **Corrigir registro (25):** só remove o que você confirmar, e sempre depois do backup. Se o backup falhar, nada é removido.
- **SFC, DISM e drivers** podem levar muitos minutos. Não feche a janela no meio.

## Estrutura

```
Abrir Painel TI.bat   atalho que abre o painel como administrador
PainelTI.ps1          o painel (menu e todas as rotinas)
README.md             este arquivo
```

Para incluir uma opção nova: crie a função no `PainelTI.ps1`, adicione uma entrada em `$opcoes` com o próximo número e coloque esse número no grupo certo em `$grupos`.
