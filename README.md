# Rotorflight Tools Installer

Script interativo para instalar ou atualizar ferramentas comuns de Rotorflight no Linux.

Ele baixa releases oficiais do GitHub, instala os aplicativos em `/opt`, cria atalhos `.desktop` e instala regras `udev` para permitir acesso USB/DFU a controladoras de voo.

## Ferramentas Instaladas

- Rotorflight Configurator
- Rotorflight Blackbox
- ExpressLRS Configurator
- Regras `udev` para firmware flashing e portas seriais USB comuns

## Sistemas Suportados

Testado em Manjaro Linux.

O script deve funcionar em outras distribuicoes Linux com `bash`, `curl`, `jq`, `tar`, `unzip`, `find`, `awk`, `sudo` e `udev`, mas isso ainda precisa ser validado.

## Instalacao

Clone ou baixe este repositorio e execute:

```bash
chmod +x bin/rotorflight-tools-installer.sh
./bin/rotorflight-tools-installer.sh
```

Para ver a ajuda:

```bash
./bin/rotorflight-tools-installer.sh --help
```

## Dependencias

No Manjaro/Arch:

```bash
sudo pacman -S --needed curl jq unzip tar
```

No Ubuntu/Debian:

```bash
sudo apt install curl jq unzip tar
```

## Menu

```text
1) Rotorflight Configurator
2) Rotorflight Blackbox
3) ExpressLRS Configurator
4) Rotorflight Configurator + Blackbox + regras udev (padrao)
5) Instalar regras udev do Rotorflight
6) Todos - ultima versao estavel, sem perguntar release
```

As opcoes `1`, `2`, `3` e `4` permitem escolher o release na lista retornada pelo GitHub.

A opcao `6` nao pergunta qual release instalar. Ela seleciona automaticamente a ultima versao `stable`, ignorando pre-releases/dev builds.

## O Que O Script Faz

- consulta os releases oficiais no GitHub;
- baixa o pacote Linux compativel;
- extrai o arquivo;
- instala em `/opt`;
- cria backup da instalacao anterior antes de substituir;
- cria atalhos `.desktop`;
- instala regras `udev` em `/etc/udev/rules.d/60-rotorflight.rules`;
- recarrega as regras com `udevadm`, quando disponivel.

## Regras Udev

As regras `udev` permitem que o usuario acesse controladoras em modo DFU/USB sem precisar executar o configurador como root.

Depois de instalar as regras:

1. Feche o configurador.
2. Desconecte a controladora.
3. Conecte novamente.
4. Se ainda houver erro de permissao, reinicie a sessao ou o computador.

## Variaveis

`RELEASE_LIMIT` controla quantos releases recentes sao consultados em cada repositorio:

```bash
RELEASE_LIMIT=20 ./bin/rotorflight-tools-installer.sh
```

O valor padrao e `10`.

## Avisos

- O script pode pedir `sudo` para escrever em `/opt`, `/usr/share/applications`, `/usr/share/icons` e `/etc/udev/rules.d`.
- Nao execute aplicativos Electron/Chromium como root para contornar problema de USB. Corrija as regras `udev`.
- Revise o script antes de executar, especialmente se estiver usando em uma distribuicao diferente de Manjaro.

## Licenca

MIT. Veja [LICENSE](LICENSE).
