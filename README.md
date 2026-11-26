# Painel de Suporte TI

Menu em PowerShell com as rotinas de suporte mais comuns em PCs Windows. Registra tudo o que foi feito em log.

## Como usar

Copie a pasta inteira para o PC e dê dois cliques em **`Abrir Painel TI.bat`** (pede permissão de administrador). Precisa de Windows 10/11.

As limpezas e o cache do Teams agem no perfil de **quem está logado no PC**, mesmo que a TI tenha aberto o painel com a própria conta de admin.

Antes de distribuir, troque o endereço do SharePoint no início do `PainelTI.ps1` (usado no teste de conexão):

```powershell
$SharePointEmpresa = 'suaempresa.sharepoint.com'
```

## Opções

- **Manutenção:** limpar temporários, Limpeza de Disco, SFC, DISM, chkdsk, saúde do disco, corrigir registro (com backup) e criar ponto de restauração.
- **Rede:** reset de rede, informações de rede, teste de conectividade (roteador, internet, Microsoft 365, Teams), limpar DNS.
- **Impressão:** destravar a fila e listar impressoras.
- **Diagnóstico:** informações do sistema, ficha completa do hardware (salva em `.txt`) e processos que mais usam memória.
- **Drivers e atualizações:** dispositivos com erro, atualizar drivers, backup de drivers e Windows Update.
- **Microsoft 365:** vínculo com Entra ID, sincronizar Intune e limpar cache do Teams.
- **Segurança:** ligar/desligar Defender e Firewall.

Log, fichas e backups ficam em `C:\ProgramData\PainelTI\`.

## Cuidados

- Desligar Defender/Firewall deixa o PC exposto: ligue de novo depois do teste.
- O reset de rede exige reiniciar o PC.
- SFC, DISM e drivers podem levar vários minutos: não feche a janela.
