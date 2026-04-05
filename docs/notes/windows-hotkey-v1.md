# Windows Hotkey V1 (Resumo Tecnico)

## Objetivo do v1
- Rodar um processo Zig em segundo plano no Windows.
- Capturar `Ctrl+B` globalmente.
- Colar `Hello world from zig` no input com foco.
- Deixar arquitetura pronta para trocar a fonte de texto (ex.: Redis) sem reescrever o core.

## Processo logico (simples e direto)
1. Inicializa adapters.
2. Registra hotkey global `Ctrl+B`.
3. Entra em loop de mensagens do Windows.
4. Quando recebe evento de hotkey:
   - Busca texto no `TextSourceAdapter` (v1 = texto fixo).
   - Coloca texto no clipboard em Unicode.
   - Injeta `Ctrl+V` para colar no app ativo.

## Arquitetura usada
- Core com interfaces:
  - `HotkeyAdapter`
  - `TextSourceAdapter`
  - `PasteAdapter`
- Implementacao Windows v1:
  - `WindowsHotkeyAdapter` (captura hotkey)
  - `WindowsPasteAdapter` (clipboard + paste)
  - `FixedTextSource` (texto fixo)

## Referencias oficiais (Microsoft Learn)
- RegisterHotKey:
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey
- WM_HOTKEY:
  - https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-hotkey
- Message queue/loop:
  - https://learn.microsoft.com/en-us/windows/win32/winmsg/using-messages-and-message-queues
- OpenClipboard:
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard
- EmptyClipboard:
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-emptyclipboard
- SetClipboardData:
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata
- SendInput:
  - https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput

## O que foi aprendido
- `RegisterHotKey` resolve bem o caso simples de atalho global.
- Para texto confiavel no Windows, usar `CF_UNICODETEXT`.
- Para "colar no foco", a combinacao clipboard + `SendInput` e o caminho mais direto.
- Arquitetura por adapters evita acoplamento com Windows e facilita portar Linux/macOS.

## Limites atuais (v1)
- Sem auto-start no login.
- Sem tray icon.
- Fecha pelo Gerenciador de Tarefas.
- Sobrescreve clipboard ao colar.

## Proximo passo natural (v2)
- Trocar `FixedTextSource` por `RedisTextSourceAdapter`.
- Manter `HotkeyAdapter` e `PasteAdapter` como estao.
