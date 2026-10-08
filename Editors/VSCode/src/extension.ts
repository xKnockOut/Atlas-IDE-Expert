// Minimale VS-Code-Erweiterung: startet BetterDelphiLSP.exe über stdio und
// bindet sie mit vscode-languageclient an. Meldungen des Servers
// (window/logMessage und stderr) erscheinen im Ausgabefenster „BetterDelphiLSP“.

import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import {
  CloseAction,
  CloseHandlerResult,
  ErrorAction,
  ErrorHandler,
  ErrorHandlerResult,
  LanguageClient,
  LanguageClientOptions,
  Message,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

const Section = 'betterDelphiLsp';
const DefaultServerPath = path.join('Output', 'Win64', 'Debug', 'Bin', 'BetterDelphiLSP.exe');

/** Höchstens so viele Neustarts nach Absturz innerhalb des Zeitfensters. */
const MaxRestarts = 5;
const RestartWindowMs = 3 * 60 * 1000;

let client: LanguageClient | undefined;
let output: vscode.OutputChannel | undefined;
let traceOutput: vscode.OutputChannel | undefined;

/** Pfad zur Server-EXE aus der Einstellung oder dem Standardort im Arbeitsbereich. */
function resolveServerPath(): string | undefined {
  const configured = vscode.workspace.getConfiguration(Section).get<string>('serverPath', '').trim();
  if (configured !== '') {
    return configured;
  }
  const folder = vscode.workspace.workspaceFolders?.[0];
  return folder ? path.join(folder.uri.fsPath, DefaultServerPath) : undefined;
}

/** Kommandozeile des Servers aus den Einstellungen. */
function serverArgs(): string[] {
  const config = vscode.workspace.getConfiguration(Section);
  const args = ['--log-level', config.get<string>('logLevel', 'info')];
  const logFile = config.get<string>('logFile', '').trim();
  if (logFile !== '') {
    args.push('--log', logFile);
  }
  const traceFile = config.get<string>('traceFile', '').trim();
  if (traceFile !== '') {
    args.push('--trace', traceFile);
  }
  return args;
}

/**
 * Startet den Server nach einem Absturz neu, höchstens MaxRestarts-mal in
 * RestartWindowMs. Danach bleibt er aus, bis der Befehl „Server neu starten“
 * kommt. Einzelne Lese- oder Schreibfehler beenden die Verbindung nicht.
 */
class RestartingErrorHandler implements ErrorHandler {
  private readonly restarts: number[] = [];

  error(_error: Error, _message: Message | undefined, count: number | undefined): ErrorHandlerResult {
    return { action: count !== undefined && count <= 3 ? ErrorAction.Continue : ErrorAction.Shutdown };
  }

  closed(): CloseHandlerResult {
    const now = Date.now();
    while (this.restarts.length > 0 && now - this.restarts[0] > RestartWindowMs) {
      this.restarts.shift();
    }
    if (this.restarts.length >= MaxRestarts) {
      return {
        action: CloseAction.DoNotRestart,
        message:
          `BetterDelphiLSP ist ${MaxRestarts}-mal in kurzer Zeit abgestürzt und bleibt aus. ` +
          'Details im Ausgabefenster „BetterDelphiLSP“; Neustart über „BetterDelphiLSP: Server neu starten“.',
      };
    }
    this.restarts.push(now);
    output?.appendLine(`Server beendet, Neustart ${this.restarts.length} von ${MaxRestarts}.`);
    return { action: CloseAction.Restart, handled: true };
  }
}

async function startClient(): Promise<void> {
  const serverPath = resolveServerPath();
  if (!serverPath || !fs.existsSync(serverPath)) {
    const choice = await vscode.window.showErrorMessage(
      `BetterDelphiLSP: Server nicht gefunden (${serverPath ?? 'kein Arbeitsbereich geöffnet'}). ` +
        'Bitte den Pfad in der Einstellung „betterDelphiLsp.serverPath“ angeben.',
      'Einstellungen öffnen',
    );
    if (choice) {
      await vscode.commands.executeCommand('workbench.action.openSettings', `${Section}.serverPath`);
    }
    return;
  }

  const serverOptions: ServerOptions = {
    command: serverPath,
    args: serverArgs(),
    transport: TransportKind.stdio,
  };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: 'file', language: 'objectpascal' },
      // Fehler in der Konfigurationsdatei meldet der Server.
      { scheme: 'file', pattern: '**/delphi-lsp.json' },
    ],
    outputChannel: output,
    traceOutputChannel: traceOutput,
    errorHandler: new RestartingErrorHandler(),
    // Schickt die Einstellungen betterDelphiLsp.* per workspace/didChangeConfiguration;
    // delphi-lsp.json im Projekt hat Vorrang.
    synchronize: { configurationSection: Section },
  };

  client = new LanguageClient(Section, 'BetterDelphiLSP', serverOptions, clientOptions);
  await client.start();
}

async function stopClient(): Promise<void> {
  if (client) {
    const running = client;
    client = undefined;
    await running.stop();
  }
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  output = vscode.window.createOutputChannel('BetterDelphiLSP');
  traceOutput = vscode.window.createOutputChannel('BetterDelphiLSP Trace');
  context.subscriptions.push(output, traceOutput);
  context.subscriptions.push(
    vscode.commands.registerCommand(`${Section}.restartServer`, async () => {
      await stopClient();
      await startClient();
    }),
    vscode.commands.registerCommand(`${Section}.showStatus`, async () => {
      if (!client) {
        void vscode.window.showWarningMessage('BetterDelphiLSP läuft nicht.');
        return;
      }
      // Der Server liefert den Status als JSON mit einer Markdown-Fassung zum Anzeigen.
      const status = await client.sendRequest<{ markdown?: string }>('workspace/executeCommand', {
        command: 'betterdelphilsp.status',
      });
      const document = await vscode.workspace.openTextDocument({
        language: 'markdown',
        content: status?.markdown ?? JSON.stringify(status, undefined, 2),
      });
      await vscode.commands.executeCommand('markdown.showPreview', document.uri);
    }),
  );
  await startClient();
}

export async function deactivate(): Promise<void> {
  await stopClient();
}
