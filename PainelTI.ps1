<#
  Painel de Suporte da TI
  ----------------------------------------
  Uso exclusivo da TI. Rodar como administrador (o "Abrir Painel TI.bat" já pede).
  Quando a TI entra com a própria conta de admin no PC de outra pessoa, o Windows
  roda o script com o perfil da TI. Por isso as limpezas e o cache do Teams agem
  no perfil de QUEM ESTÁ LOGADO na máquina (detectado abaixo), não no do admin.

  Registro de tudo o que foi feito: C:\ProgramData\PainelTI\painel.log
#>

#Requires -Version 5.1
$ErrorActionPreference = 'Continue'
# Esconde a barra azul padrão do PowerShell: o painel usa a própria barra (Barra-Progresso).
$ProgressPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = 'Painel de Suporte TI'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ---------- Base ----------

# Ajuste aqui o endereço do SharePoint da sua empresa (usado no teste de conexão).
$SharePointEmpresa = 'suaempresa.sharepoint.com'

$PastaTI = Join-Path $env:ProgramData 'PainelTI'
$Log = Join-Path $PastaTI 'painel.log'
New-Item -ItemType Directory -Path $PastaTI -Force | Out-Null

function Escrever-Log([string]$texto) {
    $linha = '{0:yyyy-MM-dd HH:mm:ss} | {1} | {2} | {3}' -f (Get-Date), $env:COMPUTERNAME, $env:USERNAME, $texto
    Add-Content -Path $Log -Value $linha -Encoding UTF8
}

function Eh-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------- Barra de progresso ----------
# Uma linha só, reescrita a cada passo:  [██████░░░░░░░░░░░░░░] 3/6  Testando Teams...
# Ela some sozinha antes de qualquer mensagem (Ok, Aviso, Erro, Titulo, perguntas).

$script:BarraAtiva = $false
$script:EtapaN = 0
$script:EtapaTotal = 1

function Barra-Progresso([int]$atual, [int]$total, [string]$texto) {
    $largura = 20
    $total = [math]::Max(1, $total)
    $atual = [math]::Min([math]::Max(0, $atual), $total)
    $cheio = [math]::Round($largura * $atual / $total)
    $barra = ([string][char]0x2588 * $cheio) + ([string][char]0x2591 * ($largura - $cheio))
    $linha = ('  [{0}] {1}/{2}  {3}' -f $barra, $atual, $total, $texto)
    Write-Host ("`r" + $linha.PadRight(78).Substring(0, 78)) -NoNewline -ForegroundColor DarkCyan
    $script:BarraAtiva = $true
}

function Limpar-Linha {
    if ($script:BarraAtiva) { Write-Host ("`r" + (' ' * 78) + "`r") -NoNewline; $script:BarraAtiva = $false }
}

# Para tarefas com várias etapas: Iniciar-Etapas 3; Etapa 'Parando...'; Etapa 'Limpando...'; ...
function Iniciar-Etapas([int]$total) { $script:EtapaN = 0; $script:EtapaTotal = [math]::Max(1, $total) }
function Etapa([string]$texto) { $script:EtapaN++; Barra-Progresso $script:EtapaN $script:EtapaTotal $texto }

function Titulo([string]$texto) { Limpar-Linha; Write-Host ''; Write-Host "=== $texto ===" -ForegroundColor Cyan }
function Ok([string]$texto) { Limpar-Linha; Write-Host "[OK] $texto" -ForegroundColor Green }
function Aviso([string]$texto) { Limpar-Linha; Write-Host "[!]  $texto" -ForegroundColor Yellow }
function Erro([string]$texto) { Limpar-Linha; Write-Host "[X]  $texto" -ForegroundColor Red }

function Confirmar([string]$pergunta) {
    Limpar-Linha
    $r = Read-Host "$pergunta (S/N)"
    return $r -match '^[sS]'
}

function Pausar { Limpar-Linha; Write-Host ''; Read-Host 'Enter para voltar ao menu' | Out-Null }

# Usuário logado na máquina (não o admin que abriu o painel) e a pasta do perfil dele.
function Obter-UsuarioLogado {
    $nome = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $nome) { return $null }
    try {
        $sid = (New-Object Security.Principal.NTAccount $nome).Translate([Security.Principal.SecurityIdentifier]).Value
        $perfil = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
        return [pscustomobject]@{ Nome = $nome; Sid = $sid; Perfil = $perfil }
    } catch {
        return [pscustomobject]@{ Nome = $nome; Sid = $null; Perfil = $null }
    }
}

function Tamanho-Pasta([string]$caminho) {
    if (-not (Test-Path $caminho)) { return 0 }
    (Get-ChildItem $caminho -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# Apaga arquivos com mais de N dias. São 3 etapas na barra: medir, apagar, conferir.
function Limpar-Pasta([string]$caminho, [int]$diasMinimos = 1) {
    if (-not (Test-Path $caminho)) { Etapa "$caminho (não existe)"; Etapa '...'; Etapa '...'; return 0 }
    Etapa "Medindo $caminho..."
    $antes = Tamanho-Pasta $caminho
    $limite = (Get-Date).AddDays(-$diasMinimos)
    Etapa "Apagando arquivos em $caminho..."
    Get-ChildItem $caminho -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limite } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $caminho -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Etapa "Conferindo $caminho..."
    return [math]::Max(0, $antes - (Tamanho-Pasta $caminho))
}

function MB([double]$bytes) { '{0:N0} MB' -f ($bytes / 1MB) }

# ---------- Manutenção ----------

function Limpar-Temporarios {
    Titulo 'Limpeza de arquivos temporários'
    $usuario = Obter-UsuarioLogado
    $pastas = @("$env:windir\Temp")
    if ($usuario -and $usuario.Perfil) {
        $pastas += Join-Path $usuario.Perfil 'AppData\Local\Temp'
        Write-Host "Usuário logado: $($usuario.Nome)"
    } else {
        Aviso 'Nenhum usuário logado encontrado; limpando só a pasta Temp do Windows.'
    }
    $total = 0
    $resultados = @()
    Iniciar-Etapas (3 * $pastas.Count)
    foreach ($p in $pastas) {
        $liberado = Limpar-Pasta $p 1
        $total += $liberado
        $resultados += ("  {0}: {1} liberados" -f $p, (MB $liberado))
    }
    Limpar-Linha
    $resultados | ForEach-Object { Write-Host $_ }
    Ok "Total liberado: $(MB $total) (arquivos em uso ou com menos de 1 dia foram mantidos)."
    Escrever-Log "Limpeza de temporários: $(MB $total)"
}

function Limpeza-Avancada {
    Titulo 'Limpeza de disco avançada'
    Write-Host 'Abre a Limpeza de Disco do Windows (inclui arquivos de sistema e de atualizações).'
    Start-Process cleanmgr.exe -ArgumentList '/d C:'
    Escrever-Log 'Abriu a Limpeza de Disco'
}

function Reparar-ArquivosWindows {
    Titulo 'Verificação e reparo de arquivos do Windows (SFC)'
    Aviso 'Pode levar de 10 a 20 minutos. Não feche esta janela.'
    sfc /scannow
    Escrever-Log 'SFC /scannow executado'
}

function Reparar-ImagemWindows {
    Titulo 'Reparo da imagem do Windows (DISM)'
    Aviso 'Precisa de internet e pode levar de 15 a 30 minutos. Depois, rode o SFC de novo.'
    DISM /Online /Cleanup-Image /RestoreHealth
    Escrever-Log 'DISM RestoreHealth executado'
}

function Verificar-Disco {
    Titulo 'Verificação do disco C: (somente leitura)'
    chkdsk C: /scan
    Escrever-Log 'chkdsk C: /scan executado'
}

function Saude-Disco {
    Titulo 'Saúde do disco (HD/SSD)'
    Iniciar-Etapas 2
    Etapa 'Lendo os discos...'
    $discos = Get-PhysicalDisk | ForEach-Object {
        $c = $_ | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Disco       = $_.FriendlyName
            Tipo        = $_.MediaType
            Tamanho     = '{0:N0} GB' -f ($_.Size / 1GB)
            Saude       = $_.HealthStatus
            Situacao    = $_.OperationalStatus
            Temperatura = if ($c.Temperature) { "$($c.Temperature) °C" } else { '-' }
            Desgaste    = if ($null -ne $c.Wear) { "$($c.Wear)%" } else { '-' }
            ErrosLeitura = $c.ReadErrorsTotal
        }
    }
    Etapa 'Lendo as unidades...'
    $volumes = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel,
        @{n = 'Livre'; e = { '{0:N1} GB' -f ($_.SizeRemaining / 1GB) } },
        @{n = 'Total'; e = { '{0:N1} GB' -f ($_.Size / 1GB) } }
    Limpar-Linha
    $discos | Format-List | Out-Host
    $volumes | Format-Table -AutoSize | Out-Host
    Aviso 'Se Saude não for "Healthy" ou o desgaste estiver alto, programe a troca do disco.'
    Escrever-Log 'Consultou a saúde do disco'
}

# Primeiro executável de uma linha de comando do registro (ex.: '"C:\x\a.exe" /min' -> 'C:\x\a.exe').
function Executavel-DoComando([string]$comando) {
    $cmd = [Environment]::ExpandEnvironmentVariables($comando).Trim()
    if ($cmd -match '^"([^"]+)"') { return $Matches[1] }
    if ($cmd -match '^(.+?\.(exe|com|bat|cmd|vbs|ps1))(\s|,|$)') { return $Matches[1] }
    return ($cmd -split '\s+')[0]
}

# Só acusa como quebrado o que aponta para um caminho completo que não existe.
# Comandos sem caminho (ex.: MsiExec.exe, rundll32) são considerados ok.
function Caminho-Ausente([string]$comando) {
    if (-not $comando) { return $false }
    $exe = Executavel-DoComando $comando
    try {
        if (-not [IO.Path]::IsPathRooted($exe)) { return $false }
        # Aliases de apps da Store (WindowsApps) são stubs que o Test-Path não enxerga: não acusar.
        if ($exe -like '*\WindowsApps\*') { return $false }
        return -not (Test-Path -LiteralPath $exe)
    } catch { return $false }
}

# 'HKLM:\X' -> 'HKLM\X' e 'Registry::HKEY_USERS\X' -> 'HKU\X' (formato do reg.exe).
function Chave-ParaRegExe([string]$chave) {
    $chave -replace '^HKLM:\\', 'HKLM\' -replace '^Registry::HKEY_USERS\\', 'HKU\'
}

function Corrigir-Registro {
    Titulo 'Corrigir registro do Windows'
    Write-Host 'Procura entradas quebradas do registro: programas que iniciam com o Windows e'
    Write-Host 'programas na lista de "Aplicativos instalados" cujos arquivos não existem mais.'
    $usuario = Obter-UsuarioLogado
    $raizes = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion')
    if ($usuario -and $usuario.Sid -and (Test-Path "Registry::HKEY_USERS\$($usuario.Sid)")) {
        $raizes += "Registry::HKEY_USERS\$($usuario.Sid)\Software\Microsoft\Windows\CurrentVersion"
    }

    $achados = New-Object System.Collections.Generic.List[object]
    Iniciar-Etapas $raizes.Count
    foreach ($raiz in $raizes) {
        $onde = if ($raiz -like 'Registry::HKEY_USERS*') { 'do usuário logado' } elseif ($raiz -like '*WOW6432Node*') { 'de 32 bits' } else { 'do computador' }
        Etapa "Verificando entradas $onde..."
        foreach ($sub in 'Run', 'RunOnce') {
            $chave = "$raiz\$sub"
            $item = Get-Item -LiteralPath $chave -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($nome in $item.GetValueNames()) {
                if (-not $nome) { continue }
                $valor = "$($item.GetValue($nome))"
                if (Caminho-Ausente $valor) {
                    $achados.Add([pscustomobject]@{ Tipo = 'Inicialização'; Nome = $nome; Arquivo = (Executavel-DoComando $valor); Chave = $chave; Valor = $nome })
                }
            }
        }
        foreach ($app in Get-ChildItem -LiteralPath "$raiz\Uninstall" -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty -LiteralPath $app.PSPath -ErrorAction SilentlyContinue
            if (-not ($p.DisplayName -and $p.UninstallString)) { continue }
            if ($p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation -ErrorAction SilentlyContinue)) { continue }
            if (Caminho-Ausente $p.UninstallString) {
                $achados.Add([pscustomobject]@{ Tipo = 'Programa fantasma'; Nome = $p.DisplayName; Arquivo = (Executavel-DoComando $p.UninstallString); Chave = ($app.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\' -replace '^Microsoft\.PowerShell\.Core\\Registry::', 'Registry::'); Valor = $null })
            }
        }
    }

    if ($achados.Count -eq 0) {
        Ok 'Nenhuma entrada quebrada encontrada no registro.'
        Write-Host 'Se o Windows está com erros de sistema, use as opções 3 (SFC) e 4 (DISM).'
        Escrever-Log 'Registro: nenhuma entrada quebrada'
        return
    }

    Limpar-Linha
    $i = 0
    foreach ($a in $achados) {
        $i++
        Write-Host (' {0,2}. [{1}] {2}' -f $i, $a.Tipo, $a.Nome)
        Write-Host ('     arquivo que não existe mais: {0}' -f $a.Arquivo) -ForegroundColor DarkGray
    }
    Write-Host ''
    if (-not (Confirmar "Remover as $i entrada(s) quebrada(s)? Um backup é feito antes")) { return }

    $chaves = @($achados.Chave | Select-Object -Unique)
    Iniciar-Etapas (1 + $chaves.Count + $achados.Count)
    Etapa 'Criando ponto de restauração (pode levar 1 minuto)...'
    try {
        Checkpoint-Computer -Description 'Painel TI - antes de corrigir o registro' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Ok 'Ponto de restauração criado.'
    } catch { Aviso "Ponto de restauração não criado ($($_.Exception.Message)). Seguindo só com o backup .reg." }

    $backup = Join-Path $PastaTI ("Registro_{0}_{1:yyyy-MM-dd_HHmm}" -f $env:COMPUTERNAME, (Get-Date))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $n = 0
    foreach ($chave in $chaves) {
        $n++
        Etapa "Fazendo backup ($n de $($chaves.Count))..."
        reg.exe export (Chave-ParaRegExe $chave) (Join-Path $backup ('{0:D2}.reg' -f $n)) /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Erro "Não consegui fazer backup de $chave. Nada foi removido."; return }
    }
    Ok "Backup salvo em $backup (dois cliques num .reg desfazem a correção)."

    $removidos = 0
    foreach ($a in $achados) {
        Etapa "Removendo $($a.Nome)..."
        try {
            if ($a.Valor) { Remove-ItemProperty -LiteralPath $a.Chave -Name $a.Valor -ErrorAction Stop }
            else { Remove-Item -LiteralPath $a.Chave -Recurse -Force -ErrorAction Stop }
            $removidos++
        } catch { Erro "$($a.Nome): $($_.Exception.Message)" }
    }
    Ok "$removidos de $($achados.Count) entrada(s) removida(s)."
    Escrever-Log "Registro: removeu $removidos entrada(s) quebrada(s); backup em $backup"
}

# ---------- Rede ----------

function Reset-Rede {
    Titulo 'Reset de rede (IP, Winsock e DNS)'
    Aviso 'O PC perde a rede por alguns segundos e precisa REINICIAR no final.'
    if (-not (Confirmar 'Continuar?')) { return }
    Iniciar-Etapas 5
    Etapa 'Liberando o IP...';            ipconfig /release 2>&1 | Out-Null
    Etapa 'Limpando o cache de DNS...';   ipconfig /flushdns 2>&1 | Out-Null
    Etapa 'Redefinindo o Winsock...';     netsh winsock reset 2>&1 | Out-Null
    Etapa 'Redefinindo o TCP/IP...';      netsh int ip reset 2>&1 | Out-Null
    Etapa 'Pedindo um IP novo...';        ipconfig /renew 2>&1 | Out-Null
    Ok 'Rede redefinida. Reinicie o computador para concluir.'
    Escrever-Log 'Reset de rede'
}

function Info-Rede {
    Titulo 'Informações de rede'
    Iniciar-Etapas 2
    Etapa 'Lendo as placas de rede...'
    $placas = Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object {
        [pscustomobject]@{
            Placa   = $_.InterfaceAlias
            IP      = ($_.IPv4Address.IPAddress -join ', ')
            Gateway = ($_.IPv4DefaultGateway.NextHop -join ', ')
            DNS     = ($_.DNSServer | Where-Object AddressFamily -eq 2).ServerAddresses -join ', '
        }
    }
    Etapa 'Lendo o Wi-Fi...'
    $wifi = netsh wlan show interfaces 2>$null | Select-String 'SSID|Sinal|Signal' | Select-Object -First 3
    Limpar-Linha
    $placas | Format-List | Out-Host
    if ($wifi) { Write-Host 'Wi-Fi:'; $wifi | ForEach-Object { Write-Host "  $($_.Line.Trim())" } }
    Escrever-Log 'Consultou informações de rede'
}

# Abre uma conexão TCP com tempo limite (sem a barra de progresso do Test-NetConnection).
function Testar-Porta([string]$alvo, [int]$porta, [int]$ms = 3000) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tarefa = $tcp.ConnectAsync($alvo, $porta)
        return ($tarefa.Wait($ms) -and $tcp.Connected)
    } catch { return $false }
    finally { $tcp.Dispose() }
}

# Ping com tempo limite: true se qualquer uma das tentativas responder.
function Testar-Ping([string]$alvo, [int]$ms = 2000, [int]$tentativas = 2) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        for ($i = 0; $i -lt $tentativas; $i++) {
            try { if ($ping.Send($alvo, $ms).Status -eq 'Success') { return $true } } catch {}
        }
        return $false
    } finally { $ping.Dispose() }
}

function Testar-Conexao {
    Titulo 'Testes de conectividade'
    Iniciar-Etapas 7
    Etapa 'Procurando o roteador...'
    $gateway = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4DefaultGateway.NextHop
    $testes = @(
        @{ Nome = 'Roteador (gateway)'; Alvo = $gateway; Porta = $null },
        @{ Nome = 'Internet (8.8.8.8)'; Alvo = '8.8.8.8'; Porta = $null },
        @{ Nome = 'DNS (google.com)'; Alvo = 'google.com'; Porta = 443 },
        @{ Nome = 'Microsoft 365 / Outlook'; Alvo = 'outlook.office365.com'; Porta = 443 },
        @{ Nome = 'SharePoint da empresa'; Alvo = $SharePointEmpresa; Porta = 443 },
        @{ Nome = 'Teams'; Alvo = 'teams.microsoft.com'; Porta = 443 }
    )
    foreach ($t in $testes) {
        Etapa "Testando $($t.Nome)..."
        if (-not $t.Alvo) { Erro "$($t.Nome): sem gateway (cabo/Wi-Fi desconectado?)"; continue }
        if ($t.Porta) { $ok = Testar-Porta $t.Alvo $t.Porta }
        else { $ok = Testar-Ping $t.Alvo }
        if ($ok) { Ok "$($t.Nome)" } else { Erro "$($t.Nome) não respondeu" }
    }
    Write-Host ''
    Write-Host 'Leitura: falhou o roteador = problema no cabo/Wi-Fi; roteador ok e internet não = link da operadora;'
    Write-Host 'internet ok e Microsoft não = DNS/firewall ou instabilidade da Microsoft.'
    Escrever-Log 'Testes de conectividade'
}

function Limpar-DNS {
    Titulo 'Limpar cache de DNS'
    ipconfig /flushdns
    Escrever-Log 'Flush DNS'
}

function Abrir-ConexoesRede { Start-Process ncpa.cpl; Escrever-Log 'Abriu Conexões de Rede' }

# ---------- Impressão ----------

function Limpar-FilaImpressao {
    Titulo 'Limpar fila de impressão travada'
    Iniciar-Etapas 3
    Etapa 'Parando o serviço de impressão...'
    Stop-Service Spooler -Force
    Etapa 'Apagando os trabalhos travados...'
    Remove-Item "$env:windir\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
    Etapa 'Iniciando o serviço de impressão...'
    Start-Service Spooler
    if ((Get-Service Spooler).Status -eq 'Running') { Ok 'Fila limpa e serviço de impressão reiniciado.' }
    else { Erro 'O serviço de impressão não voltou. Verifique em services.msc.' }
    Escrever-Log 'Limpou a fila de impressão'
}

function Listar-Impressoras {
    Titulo 'Impressoras instaladas'
    Iniciar-Etapas 1
    Etapa 'Lendo as impressoras...'
    $impressoras = Get-Printer | Select-Object Name, PrinterStatus, PortName, Default
    Limpar-Linha
    $impressoras | Format-Table -AutoSize | Out-Host
    Escrever-Log 'Listou impressoras'
}

# ---------- Sistema ----------

function Info-Sistema {
    Titulo 'Informações do sistema'
    Iniciar-Etapas 3
    Etapa 'Lendo o Windows...'
    $so = Get-CimInstance Win32_OperatingSystem
    $pc = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    Etapa 'Lendo o hardware...'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $c = Get-Volume -DriveLetter C
    Etapa 'Lendo o usuário logado...'
    $usuario = Obter-UsuarioLogado
    Limpar-Linha
    [pscustomobject]@{
        Computador     = $env:COMPUTERNAME
        UsuarioLogado  = if ($usuario) { $usuario.Nome } else { '-' }
        Fabricante     = "$($pc.Manufacturer) $($pc.Model)"
        NumeroSerie    = $bios.SerialNumber
        Windows        = "$($so.Caption) ($($so.Version))"
        Processador    = $cpu.Name.Trim()
        Memoria        = '{0:N0} GB' -f ($pc.TotalPhysicalMemory / 1GB)
        DiscoC         = '{0:N0} GB livres de {1:N0} GB' -f ($c.SizeRemaining / 1GB), ($c.Size / 1GB)
        LigadoDesde    = $so.LastBootUpTime
        DiasLigado     = [math]::Round(((Get-Date) - $so.LastBootUpTime).TotalDays, 1)
    } | Format-List | Out-Host
    if ((((Get-Date) - $so.LastBootUpTime).TotalDays) -gt 7) { Aviso 'Ligado há mais de 7 dias: peça para reiniciar.' }
    Escrever-Log 'Consultou informações do sistema'
}

function GB([double]$bytes) { '{0:N0} GB' -f ($bytes / 1GB) }

# Ficha completa da máquina: computador, processador, memória (pente a pente),
# discos, placa de vídeo, rede, monitores e bateria. Pode salvar em .txt.
function Especificacoes-Computador {
    Titulo 'Especificações completas do computador'
    $linhas = New-Object System.Collections.Generic.List[string]
    function Sec([string]$t) { $linhas.Add(''); $linhas.Add("--- $t ---") }
    function Item([string]$rotulo, $valor) { $linhas.Add(('  {0,-22} {1}' -f $rotulo, $valor)) }

    $chassi = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes
    $notebook = [bool]($chassi | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 })
    Iniciar-Etapas $(if ($notebook) { 8 } else { 7 })
    function Passo([string]$t) { Etapa "Lendo $t..." }

    Passo 'dados do computador'
    $so = Get-CimInstance Win32_OperatingSystem
    $pc = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $placa = Get-CimInstance Win32_BaseBoard
    $usuario = Obter-UsuarioLogado
    $versao = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion

    Sec 'COMPUTADOR'
    Item 'Nome' $env:COMPUTERNAME
    Item 'Usuário logado' $(if ($usuario) { $usuario.Nome } else { '-' })
    Item 'Tipo' $(if ($notebook) { 'Notebook' } else { 'Desktop' })
    Item 'Fabricante/Modelo' "$($pc.Manufacturer) $($pc.Model)"
    Item 'Número de série' $bios.SerialNumber
    Item 'Placa-mãe' "$($placa.Manufacturer) $($placa.Product)"
    Item 'BIOS' "$($bios.SMBIOSBIOSVersion) ($('{0:dd/MM/yyyy}' -f $bios.ReleaseDate))"
    Item 'Windows' "$($so.Caption) $versao (build $($so.BuildNumber))"
    Item 'Instalado em' ('{0:dd/MM/yyyy}' -f $so.InstallDate)
    Item 'Ligado desde' ('{0:dd/MM/yyyy HH:mm}' -f $so.LastBootUpTime)

    Passo 'processador'
    Sec 'PROCESSADOR'
    foreach ($cpu in Get-CimInstance Win32_Processor) {
        Item 'Modelo' $cpu.Name.Trim()
        Item 'Núcleos / threads' "$($cpu.NumberOfCores) núcleos / $($cpu.NumberOfLogicalProcessors) threads"
        Item 'Velocidade máxima' ('{0:N2} GHz' -f ($cpu.MaxClockSpeed / 1000))
        Item 'Uso agora' "$($cpu.LoadPercentage)%"
    }

    Passo 'memória'
    Sec 'MEMÓRIA RAM'
    $pentes = @(Get-CimInstance Win32_PhysicalMemory)
    $slots = (Get-CimInstance Win32_PhysicalMemoryArray | Measure-Object MemoryDevices -Sum).Sum
    $tipos = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $livre = $so.FreePhysicalMemory * 1KB
    Item 'Total' (GB $pc.TotalPhysicalMemory)
    Item 'Em uso agora' ('{0} de {1} ({2:N0}%)' -f (GB ($pc.TotalPhysicalMemory - $livre)), (GB $pc.TotalPhysicalMemory), (100 * ($pc.TotalPhysicalMemory - $livre) / $pc.TotalPhysicalMemory))
    Item 'Slots usados' $(if ($slots) { "$($pentes.Count) de $slots" } else { "$($pentes.Count)" })
    $i = 0
    foreach ($p in $pentes) {
        $i++
        $tipo = if ($tipos.ContainsKey([int]$p.SMBIOSMemoryType)) { $tipos[[int]$p.SMBIOSMemoryType] } else { 'tipo ?' }
        $velocidade = if ($p.ConfiguredClockSpeed) { $p.ConfiguredClockSpeed } else { $p.Speed }
        Item "Pente $i" ('{0} {1} {2} MHz - {3} {4} ({5})' -f (GB $p.Capacity), $tipo, $velocidade, $p.Manufacturer, "$($p.PartNumber)".Trim(), $p.DeviceLocator)
    }

    Passo 'discos'
    Sec 'ARMAZENAMENTO'
    $saudes = @{ 'Healthy' = 'boa'; 'Warning' = 'ATENÇÃO'; 'Unhealthy' = 'RUIM' }
    foreach ($d in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $saude = if ($saudes.ContainsKey("$($d.HealthStatus)")) { $saudes["$($d.HealthStatus)"] } else { "$($d.HealthStatus)" }
        Item 'Disco' ('{0} | {1} {2} | {3} | saúde: {4}' -f $d.FriendlyName, $d.MediaType, $d.BusType, (GB $d.Size), $saude)
        if ($saude -ne 'boa') { $linhas.Add('  [!] Disco com problema de saúde: faça backup e avalie a troca.') }
    }
    foreach ($v in Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }) {
        $pct = 100 * [double]$v.SizeRemaining / [double]$v.Size
        Item "Unidade $($v.DriveLetter):" ('{0} livres de {1} ({2:N0}% livre)' -f (GB $v.SizeRemaining), (GB $v.Size), $pct)
        if ($pct -lt 10) { $linhas.Add("  [!] Pouco espaço livre em $($v.DriveLetter): (menos de 10%).") }
    }

    Passo 'placa de vídeo'
    Sec 'PLACA DE VÍDEO'
    foreach ($g in Get-CimInstance Win32_VideoController) {
        Item 'Modelo' $g.Name
        Item 'Driver' "$($g.DriverVersion) ($('{0:dd/MM/yyyy}' -f $g.DriverDate))"
        if ($g.CurrentHorizontalResolution) { Item 'Resolução' "$($g.CurrentHorizontalResolution) x $($g.CurrentVerticalResolution)" }
    }

    Passo 'monitores'
    Sec 'MONITORES'
    try {
        $monitores = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        foreach ($m in $monitores) {
            $nome = -join ($m.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            $fab = -join ($m.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            Item 'Monitor' $(if ($nome) { "$fab $nome" } else { "$fab (tela integrada)" })
        }
    } catch { Item 'Monitor' 'não foi possível ler' }

    Passo 'rede'
    Sec 'REDE'
    foreach ($a in Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Sort-Object Status -Descending) {
        if ($a.Status -eq 'Up') {
            $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
            Item $a.Name ('{0} | conectado, {1} | IP {2} | MAC {3}' -f $a.InterfaceDescription, $a.LinkSpeed, $ip, $a.MacAddress)
        } else {
            Item $a.Name ('{0} | desconectado | MAC {1}' -f $a.InterfaceDescription, $a.MacAddress)
        }
    }

    if ($notebook) {
        Passo 'bateria'
        Sec 'BATERIA'
        $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($bat) {
            Item 'Carga atual' "$($bat.EstimatedChargeRemaining)%"
            try {
                $projeto = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
                $atual = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
                if ($projeto -and $atual) {
                    $saude = 100 * $atual / $projeto
                    Item 'Saúde da bateria' ('{0:N0}% da capacidade original' -f $saude)
                    if ($saude -lt 60) { $linhas.Add('  [!] Bateria bem desgastada: avaliar troca.') }
                }
            } catch { Item 'Saúde da bateria' 'não foi possível ler (o painel precisa estar como administrador)' }
        } else { Item 'Bateria' 'não encontrada' }
    }

    Limpar-Linha
    foreach ($l in $linhas) {
        if ($l -like '---*') { Write-Host $l -ForegroundColor DarkCyan } elseif ($l -like '  `[!`]*') { Write-Host $l -ForegroundColor Yellow } else { Write-Host $l }
    }
    Write-Host ''
    if (Confirmar 'Salvar esta ficha em arquivo .txt?') {
        $arquivo = Join-Path $PastaTI ("Ficha_{0}_{1:yyyy-MM-dd}.txt" -f $env:COMPUTERNAME, (Get-Date))
        $cab = @("FICHA DO COMPUTADOR", ("Gerada em {0:dd/MM/yyyy HH:mm}" -f (Get-Date)))
        ($cab + $linhas) | Set-Content -Path $arquivo -Encoding UTF8
        ($cab + $linhas) -join "`r`n" | Set-Clipboard -ErrorAction SilentlyContinue
        Ok "Ficha salva em $arquivo (e copiada para a área de transferência)."
        Start-Process explorer.exe -ArgumentList "/select,`"$arquivo`""
    }
    Escrever-Log 'Consultou as especificações completas do computador'
}

function Monitor-Recursos {
    Titulo 'Processos que mais usam memória'
    Iniciar-Etapas 2
    Etapa 'Lendo os processos...'
    $processos = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name,
        @{n = 'Memoria'; e = { MB $_.WorkingSet64 } }
    Etapa 'Abrindo o Monitor de Recursos...'
    Start-Process resmon.exe
    Limpar-Linha
    $processos | Format-Table -AutoSize | Out-Host
    Escrever-Log 'Abriu o Monitor de Recursos'
}

function Dispositivos-ComErro {
    Titulo 'Dispositivos com problema'
    Iniciar-Etapas 1
    Etapa 'Lendo os dispositivos...'
    $erros = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -notin 'OK', 'Unknown' }
    Limpar-Linha
    if ($erros) {
        $erros | Group-Object Status, Class, FriendlyName | ForEach-Object {
            [pscustomobject]@{
                Status      = $_.Group[0].Status
                Tipo        = $_.Group[0].Class
                Dispositivo = $_.Group[0].FriendlyName
                Qtde        = $_.Count
            }
        } | Format-Table -AutoSize | Out-Host
        Write-Host 'Dica: "Degraded" em componentes de software (ex.: Intel XTU) costuma ser inofensivo.'
        if (Confirmar 'Procurar drivers novos no Windows Update?') { Atualizar-Drivers; return }
    } else { Ok 'Nenhum dispositivo com erro.' }
    if (Confirmar 'Abrir o Gerenciador de Dispositivos?') { Start-Process devmgmt.msc }
    Escrever-Log 'Verificou dispositivos com erro'
}

function Atualizar-Drivers {
    Titulo 'Atualizar drivers pelo Windows Update'
    Aviso 'A busca pode levar alguns minutos.'
    Iniciar-Etapas 1
    Etapa 'Procurando drivers no Windows Update...'
    $sessao = New-Object -ComObject Microsoft.Update.Session
    $busca = $sessao.CreateUpdateSearcher()
    try { $resultado = $busca.Search("IsInstalled=0 and Type='Driver' and IsHidden=0") }
    catch { Erro "Não foi possível consultar o Windows Update: $($_.Exception.Message)"; return }
    if ($resultado.Updates.Count -eq 0) {
        Ok 'Nenhum driver novo disponível. Todos os drivers estão em dia pelo Windows Update.'
        Escrever-Log 'Drivers: nenhum disponível'
        return
    }
    Limpar-Linha
    $i = 0
    foreach ($u in $resultado.Updates) {
        $i++
        $data = if ($u.DriverVerDate) { '{0:dd/MM/yyyy}' -f $u.DriverVerDate } else { '-' }
        Write-Host (' {0,2}. {1}  [{2}, {3}]' -f $i, $u.Title, $u.DriverClass, $data)
    }
    Write-Host ''
    if (-not (Confirmar "Instalar os $i driver(s)?")) { return }
    $lista = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $resultado.Updates) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        [void]$lista.Add($u)
    }
    Iniciar-Etapas 2
    Etapa "Baixando $i driver(s)..."
    $baixar = $sessao.CreateUpdateDownloader(); $baixar.Updates = $lista; [void]$baixar.Download()
    Etapa "Instalando $i driver(s)..."
    $instalar = $sessao.CreateUpdateInstaller(); $instalar.Updates = $lista
    $fim = $instalar.Install()
    Limpar-Linha
    $codigos = @{ 2 = 'instalado'; 3 = 'instalado com avisos'; 4 = 'falhou'; 5 = 'cancelado' }
    for ($n = 0; $n -lt $lista.Count; $n++) {
        $r = $fim.GetUpdateResult($n).ResultCode
        $texto = if ($codigos.ContainsKey([int]$r)) { $codigos[[int]$r] } else { "código $r" }
        Write-Host (' - {0}: {1}' -f $lista.Item($n).Title, $texto)
    }
    if ($fim.RebootRequired) { Aviso 'Reinicie o computador para concluir.' }
    Ok 'Atualização de drivers concluída.'
    Escrever-Log "Drivers: $i atualização(ões) instaladas (resultado $($fim.ResultCode))"
}

function Backup-Drivers {
    Titulo 'Backup dos drivers instalados'
    $destino = Join-Path $PastaTI ("Drivers_{0}_{1:yyyy-MM-dd}" -f $env:COMPUTERNAME, (Get-Date))
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    Iniciar-Etapas 1
    Etapa 'Copiando os drivers (pode levar alguns minutos)...'
    Export-WindowsDriver -Online -Destination $destino | Out-Null
    Ok "Drivers salvos em $destino"
    Escrever-Log "Backup de drivers em $destino"
}

function Atualizacoes-Windows {
    Titulo 'Windows Update'
    Start-Process 'ms-settings:windowsupdate'
    try { Start-Process UsoClient.exe -ArgumentList 'StartScan' -WindowStyle Hidden } catch {}
    Ok 'Procura de atualizações iniciada; a tela do Windows Update foi aberta.'
    Escrever-Log 'Iniciou o Windows Update'
}

# ---------- Microsoft 365 ----------

function Status-Microsoft365 {
    Titulo 'Vínculo do PC com a Microsoft (Entra ID / Intune)'
    Iniciar-Etapas 1
    Etapa 'Consultando o vínculo com a Microsoft...'
    $s = dsregcmd /status
    Limpar-Linha
    $s | Select-String 'AzureAdJoined|DomainJoined|WorkplaceJoined|TenantName|DeviceId|AzureAdPrt ' |
        ForEach-Object { Write-Host "  $($_.Line.Trim())" }
    Write-Host ''
    Write-Host 'AzureAdJoined : YES = PC da empresa ligado ao Microsoft 365 (pode ser gerenciado pelo Intune).'
    Escrever-Log 'Consultou dsregcmd /status'
}

function Sincronizar-Intune {
    Titulo 'Sincronizar com o Intune'
    Iniciar-Etapas 1
    Etapa 'Procurando a tarefa do Intune...'
    $tarefas = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskName -eq 'PushLaunch'
    if ($tarefas) {
        $tarefas | Start-ScheduledTask
        Ok 'Sincronização pedida. As políticas e apps chegam em alguns minutos.'
    } else {
        Aviso 'Este PC ainda não está no Intune (depois do Business Premium ele aparece aqui).'
    }
    Escrever-Log 'Sincronização do Intune'
}

function Limpar-CacheTeams {
    Titulo 'Limpar cache do Teams'
    $usuario = Obter-UsuarioLogado
    if (-not ($usuario -and $usuario.Perfil)) { Erro 'Nenhum usuário logado encontrado.'; return }
    Aviso "O Teams de $($usuario.Nome) será fechado. Conversas e arquivos não são apagados."
    if (-not (Confirmar 'Continuar?')) { return }
    $caches = @(
        'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams',
        'AppData\Roaming\Microsoft\Teams'
    ) | ForEach-Object { Join-Path $usuario.Perfil $_ }
    Iniciar-Etapas (1 + $caches.Count)
    Etapa 'Fechando o Teams...'
    Get-Process ms-teams, Teams -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    foreach ($c in $caches) {
        Etapa 'Limpando o cache...'
        if (Test-Path $c) { Remove-Item "$c\*" -Recurse -Force -ErrorAction SilentlyContinue; Ok "Limpo: $c" }
    }
    Ok 'Peça para a pessoa abrir o Teams de novo.'
    Escrever-Log "Limpou o cache do Teams de $($usuario.Nome)"
}

function Defender-Firewall {
    Titulo 'Windows Defender e Firewall'
    Aviso 'Desligar a proteção deixa o PC vulnerável. Use só para um teste rápido e LIGUE de novo depois.'

    # Situação atual
    Iniciar-Etapas 2
    Etapa 'Lendo o Defender...'
    $rt = $null
    $tamper = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop; $rt = $mp.RealTimeProtectionEnabled; $tamper = $mp.IsTamperProtected } catch {}
    Etapa 'Lendo o Firewall...'
    $perfis = @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)
    Limpar-Linha
    Write-Host ''
    Write-Host ('  Defender (proteção em tempo real): {0}' -f $(if ($null -eq $rt) { 'não foi possível ler' } elseif ($rt) { 'LIGADA' } else { 'desligada' }))
    foreach ($perfil in $perfis) {
        Write-Host ('  Firewall {0,-8}: {1}' -f $perfil.Name, $(if ($perfil.Enabled) { 'LIGADO' } else { 'desligado' }))
    }
    Write-Host ''
    Write-Host '  [1] Desligar Defender e Firewall'
    Write-Host '  [2] Ligar Defender e Firewall'
    Write-Host '  [0] Voltar'
    $op = "$(Read-Host 'Escolha')".Trim()
    if ($op -notin '1', '2') { return }
    $ligar = ($op -eq '2')

    if (-not $ligar) {
        if ($tamper) {
            Erro 'A Proteção contra Adulteração (Tamper Protection) está LIGADA.'
            Write-Host 'Com ela ligada, o Windows não deixa desligar o Defender por script.'
            Write-Host 'Desligue antes em: Segurança do Windows > Proteção contra vírus e ameaças > Gerenciar configurações.'
            if (-not (Confirmar 'Tentar mesmo assim (só o firewall será afetado)?')) { return }
        } elseif (-not (Confirmar 'Confirma DESLIGAR Defender e Firewall?')) { return }
    }

    $alvo = if ($ligar) { 'LIGAR' } else { 'DESLIGAR' }
    Iniciar-Etapas 2

    # Defender (proteção em tempo real)
    Etapa "Defender: $($alvo.ToLower())..."
    try {
        Set-MpPreference -DisableRealtimeMonitoring (-not $ligar) -ErrorAction Stop
        Ok "Defender: proteção em tempo real definida para $(if ($ligar) {'LIGADA'} else {'desligada'})."
    } catch {
        Erro "Defender não pôde ser alterado: $($_.Exception.Message)"
        if ($tamper) { Write-Host 'Motivo provável: Proteção contra Adulteração ligada.' }
    }

    # Firewall (todos os perfis)
    Etapa "Firewall: $($alvo.ToLower())..."
    try {
        Set-NetFirewallProfile -All -Enabled $(if ($ligar) { 'True' } else { 'False' }) -ErrorAction Stop
        Ok "Firewall $(if ($ligar) {'ligado'} else {'desligado'}) em todos os perfis."
    } catch {
        Erro "Firewall não pôde ser alterado: $($_.Exception.Message)"
    }

    if (-not $ligar) { Aviso 'Lembre de voltar aqui e LIGAR a proteção quando terminar o teste.' }
    Escrever-Log "Defender/Firewall: pedido para $alvo"
}

function Ver-Log {
    Titulo 'Últimas ações registradas neste PC'
    if (Test-Path $Log) { Get-Content $Log -Tail 20 } else { Write-Host 'Ainda não há registros.' }
}

# ---------- Menu ----------

$opcoes = [ordered]@{
    '1'  = @('Limpeza de arquivos temporários', ${function:Limpar-Temporarios})
    '2'  = @('Limpeza de disco avançada', ${function:Limpeza-Avancada})
    '3'  = @('Verificar e reparar arquivos do Windows (SFC)', ${function:Reparar-ArquivosWindows})
    '4'  = @('Reparar a imagem do Windows (DISM)', ${function:Reparar-ImagemWindows})
    '5'  = @('Verificar o disco C:', ${function:Verificar-Disco})
    '6'  = @('Saúde do disco (HD/SSD)', ${function:Saude-Disco})
    '7'  = @('Reset de rede (IP, Winsock e DNS)', ${function:Reset-Rede})
    '8'  = @('Informações de rede', ${function:Info-Rede})
    '9'  = @('Testes de conectividade', ${function:Testar-Conexao})
    '10' = @('Limpar cache de DNS', ${function:Limpar-DNS})
    '11' = @('Abrir Conexões de Rede', ${function:Abrir-ConexoesRede})
    '12' = @('Limpar fila de impressão travada', ${function:Limpar-FilaImpressao})
    '13' = @('Listar impressoras', ${function:Listar-Impressoras})
    '14' = @('Informações do sistema', ${function:Info-Sistema})
    '15' = @('Especificações completas (memória, processador, discos...)', ${function:Especificacoes-Computador})
    '16' = @('Monitor de recursos e processos', ${function:Monitor-Recursos})
    '17' = @('Dispositivos com erro', ${function:Dispositivos-ComErro})
    '18' = @('Atualizar drivers (Windows Update)', ${function:Atualizar-Drivers})
    '19' = @('Backup dos drivers', ${function:Backup-Drivers})
    '20' = @('Procurar atualizações do Windows', ${function:Atualizacoes-Windows})
    '21' = @('Vínculo com a Microsoft (Entra/Intune)', ${function:Status-Microsoft365})
    '22' = @('Sincronizar com o Intune', ${function:Sincronizar-Intune})
    '23' = @('Limpar cache do Teams', ${function:Limpar-CacheTeams})
    '24' = @('Ver registro de ações deste PC', ${function:Ver-Log})
    '25' = @('Corrigir registro do Windows (entradas quebradas)', ${function:Corrigir-Registro})
    '26' = @('Desligar/ligar Defender e Firewall', ${function:Defender-Firewall})
}

$grupos = [ordered]@{
    'MANUTENÇÃO DO SISTEMA' = '1', '2', '3', '4', '5', '6', '25'
    'REDE E INTERNET'       = '7', '8', '9', '10', '11'
    'IMPRESSÃO'             = '12', '13'
    'DIAGNÓSTICO'           = '14', '15', '16'
    'DRIVERS E ATUALIZAÇÕES' = '17', '18', '19', '20'
    'MICROSOFT 365'         = '21', '22', '23'
    'SEGURANÇA'             = , '26'
    'TI'                    = , '24'
}

function Mostrar-Menu {
    Clear-Host
    $usuario = Obter-UsuarioLogado
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '              PAINEL DE SUPORTE DA TI' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host (" PC: {0}   Usuário logado: {1}" -f $env:COMPUTERNAME, $(if ($usuario) { $usuario.Nome } else { '-' }))
    foreach ($g in $grupos.Keys) {
        Write-Host ''
        Write-Host "--- $g ---" -ForegroundColor DarkCyan
        foreach ($n in $grupos[$g]) { Write-Host (' [{0,2}] {1}' -f $n, $opcoes[$n][0]) }
    }
    Write-Host ''
    Write-Host ' [ 0] Sair'
    Write-Host ''
}

if (-not (Eh-Admin)) {
    Erro 'Abra pelo "Abrir Painel TI.bat" (ou como administrador). Algumas opções precisam de admin.'
    Read-Host 'Enter para sair' | Out-Null
    exit 1
}

Escrever-Log 'Painel aberto'
while ($true) {
    Mostrar-Menu
    $escolha = (Read-Host 'Escolha uma opção').Trim()
    if ($escolha -eq '0') { Escrever-Log 'Painel fechado'; break }
    if ($opcoes.Contains($escolha)) {
        try { & $opcoes[$escolha][1] }
        catch { Erro $_.Exception.Message; Escrever-Log "ERRO na opção ${escolha}: $($_.Exception.Message)" }
        Pausar
    } else {
        Aviso 'Opção inválida.'
        Start-Sleep -Seconds 1
    }
}
