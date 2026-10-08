// Minimale VS-Code-Erweiterung: startet BetterDelphiLSP.exe über stdio und
// bindet sie mit vscode-languageclient an. Meldungen des Servers
// (window/logMessage und stderr) erscheinen im Ausgabefenster „BetterDelphiLSP“.

import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

const Section = 'betterDelphiLsp';
const DefaultServerPath = path.join('Output', 'Win64', 'Debug', 'Bin', 'BetterDelphiLSP.exe');

let client: LanguageClient | undefined;
let output: vscode.OutputChannel | undefined;

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
    documentSelector: [{ scheme: 'file', language: 'objectpascal' }],
    outputChannel: output,
    traceOutputChannel: vscode.window.createOutputChannel('BetterDelphiLSP Trace'),
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
  context.subscriptions.push(output);
  context.subscriptions.push(
    vscode.commands.registerCommand(`${Section}.restartServer`, async () => {
      await stopClient();
      await startClient();
    }),
  );
  await startClient();
}

export async function deactivate(): Promise<void> {
  await stopClient();
}
