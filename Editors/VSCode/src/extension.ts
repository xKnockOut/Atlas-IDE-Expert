// VS-Code-Erweiterung (#12, #49): startet AtlasServer.exe über stdio und
// bindet sie mit vscode-languageclient an. Meldungen des Servers
// (window/logMessage und stderr) erscheinen im Ausgabefenster „Atlas“.

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

const Section = 'atlas';
const ServerExe = 'AtlasServer.exe';
/** Build-Ausgaben im Arbeitsbereich, in dieser Reihenfolge gesucht. */
const WorkspaceServerPaths = [
  path.join('Output', 'Win64', 'Release', 'Bin', ServerExe),
  path.join('Output', 'Win64', 'Debug', 'Bin', ServerExe),
  path.join('Output', 'Win32', 'Release', 'Bin', ServerExe),
  path.join('Output', 'Win32', 'Debug', 'Bin', ServerExe),
];

/** Höchstens so viele Neustarts nach Absturz innerhalb des Zeitfensters. */
const MaxRestarts = 5;
const RestartWindowMs = 3 * 60 * 1000;

let client: LanguageClient | undefined;
let output: vscode.OutputChannel | undefined;
let traceOutput: vscode.OutputChannel | undefined;
let extensionPath = '';

/** Erster Treffer für ServerExe in den Ordnern von PATH. */
function findOnPath(): string | undefined {
  for (const dir of (process.env.PATH ?? '').split(path.delimiter)) {
    if (dir !== '') {
      const candidate = path.join(dir, ServerExe);
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
  }
  return undefined;
}

/**
 * Pfad zur Server-EXE: Einstellung, dann die in der .vsix mitgelieferte EXE
 * (server/), dann Build-Ausgaben im Arbeitsbereich, zuletzt PATH.
 * Ohne Treffer der erwartete Pfad für die Fehlermeldung.
 */
function resolveServerPath(): string | undefined {
  const configured = vscode.workspace.getConfiguration(Section).get<string>('serverPath', '').trim();
  if (configured !== '') {
    return configured;
  }
  const candidates: string[] = [];
  if (extensionPath !== '') {
    candidates.push(path.join(extensionPath, 'server', ServerExe));
  }
  // In nicht vertrauenswürdigen Ordnern keine Programme aus dem Arbeitsbereich starten (#186).
  for (const folder of vscode.workspace.isTrusted ? vscode.workspace.workspaceFolders ?? [] : []) {
    for (const relative of WorkspaceServerPaths) {
      candidates.push(path.join(folder.uri.fsPath, relative));
    }
  }
  return candidates.find((candidate) => fs.existsSync(candidate)) ?? findOnPath() ?? candidates[0];
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
  // Workspace Trust (#186): der Server führt dann nichts aus dem Projekt aus (kein Compiler-Lauf).
  if (!vscode.workspace.isTrusted) {
    args.push('--restricted');
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
          `Atlas ist ${MaxRestarts}-mal in kurzer Zeit abgestürzt und bleibt aus. ` +
          'Details im Ausgabefenster „Atlas“; Neustart über „Atlas: Server neu starten“.',
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
      `Atlas: Server nicht gefunden (${serverPath ?? 'kein Arbeitsbereich geöffnet'}). ` +
        'Bitte den Pfad in der Einstellung „atlas.serverPath“ angeben.',
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
      { scheme: 'file', pattern: '**/atlas.json' },
      { scheme: 'file', pattern: '**/delphi-lsp.json' },
      // Text-Formulardateien (#44): Gliederung und Sprung zum Ereignis.
      { scheme: 'file', pattern: '**/*.{dfm,fmx}' },
    ],
    outputChannel: output,
    traceOutputChannel: traceOutput,
    errorHandler: new RestartingErrorHandler(),
    // Schickt die Einstellungen atlas.* per workspace/didChangeConfiguration;
    // atlas.json im Projekt hat Vorrang.
    synchronize: { configurationSection: Section },
  };

  client = new LanguageClient(Section, 'Atlas', serverOptions, clientOptions);
  await client.start();
}

async function stopClient(): Promise<void> {
  if (client) {
    const running = client;
    client = undefined;
    await running.stop();
  }
}

interface LspPosition {
  line: number;
  character: number;
}

interface LspLocation {
  uri: string;
  range: { start: LspPosition; end: LspPosition };
}

function toPosition(position: LspPosition): vscode.Position {
  return new vscode.Position(position.line, position.character);
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  extensionPath = context.extensionPath;
  output = vscode.window.createOutputChannel('Atlas');
  traceOutput = vscode.window.createOutputChannel('Atlas Trace');
  context.subscriptions.push(output, traceOutput);
  context.subscriptions.push(
    vscode.commands.registerCommand(`${Section}.restartServer`, async () => {
      await stopClient();
      await startClient();
    }),
    // Sobald der Ordner vertraut wird, ohne --restricted neu starten.
    vscode.workspace.onDidGrantWorkspaceTrust(async () => {
      await stopClient();
      await startClient();
    }),
    vscode.commands.registerCommand(`${Section}.showStatus`, async () => {
      if (!client) {
        void vscode.window.showWarningMessage('Atlas läuft nicht.');
        return;
      }
      // Der Server liefert den Status als JSON mit einer Markdown-Fassung zum Anzeigen.
      const status = await client.sendRequest<{ markdown?: string }>('workspace/executeCommand', {
        command: 'atlas.server.status',
      });
      const document = await vscode.workspace.openTextDocument({
        language: 'markdown',
        content: status?.markdown ?? JSON.stringify(status, undefined, 2),
      });
      await vscode.commands.executeCommand('markdown.showPreview', document.uri);
    }),
    // Qualifizierten Namen des Symbols unter dem Cursor kopieren (#128); der Server liefert ihn als String.
    ...[false, true].map((withParameters) =>
      vscode.commands.registerCommand(
        withParameters ? `${Section}.copyQualifiedNameWithParameters` : `${Section}.copyQualifiedName`,
        async () => {
          const editor = vscode.window.activeTextEditor;
          if (!client || !editor) {
            void vscode.window.showWarningMessage('Atlas läuft nicht oder kein Editor ist aktiv.');
            return;
          }
          try {
            const name = await client.sendRequest<string>('workspace/executeCommand', {
              command: 'atlas.server.qualifiedName',
              arguments: [
                editor.document.uri.toString(),
                { line: editor.selection.active.line, character: editor.selection.active.character },
                withParameters,
              ],
            });
            await vscode.env.clipboard.writeText(name);
            void vscode.window.setStatusBarMessage(`Kopiert: ${name}`, 3000);
          } catch (error) {
            void vscode.window.showWarningMessage(`Atlas: ${(error as Error).message}`);
          }
        },
      ),
    ),
    // Klartext und String-Literal (#312), Befund als Prompt (#158): copyText kommt aus den Code-Aktionen.
    vscode.commands.registerCommand(`${Section}.copyText`, async (text: string) => {
      await vscode.env.clipboard.writeText(text);
      void vscode.window.setStatusBarMessage('In die Zwischenablage kopiert', 3000);
    }),
    vscode.commands.registerCommand(`${Section}.copyAsPlainText`, async () => {
      const editor = vscode.window.activeTextEditor;
      if (!client || !editor) {
        void vscode.window.showWarningMessage('Atlas läuft nicht oder kein Editor ist aktiv.');
        return;
      }
      try {
        const text = await client.sendRequest<string>('workspace/executeCommand', {
          command: 'atlas.server.plainText',
          arguments: [
            editor.document.uri.toString(),
            { line: editor.selection.active.line, character: editor.selection.active.character },
          ],
        });
        await vscode.env.clipboard.writeText(text);
        void vscode.window.setStatusBarMessage('Klartext kopiert', 3000);
      } catch (error) {
        void vscode.window.showWarningMessage(`Atlas: ${(error as Error).message}`);
      }
    }),
    vscode.commands.registerCommand(`${Section}.pasteAsLiteral`, async () => {
      const editor = vscode.window.activeTextEditor;
      if (!client || !editor) {
        void vscode.window.showWarningMessage('Atlas läuft nicht oder kein Editor ist aktiv.');
        return;
      }
      try {
        const literal = await client.sendRequest<string>('workspace/executeCommand', {
          command: 'atlas.server.textToLiteral',
          arguments: [
            editor.document.uri.toString(),
            { line: editor.selection.start.line, character: editor.selection.start.character },
            await vscode.env.clipboard.readText(),
          ],
        });
        await editor.edit((builder) => builder.replace(editor.selection, literal));
      } catch (error) {
        void vscode.window.showWarningMessage(`Atlas: ${(error as Error).message}`);
      }
    }),
    // Konfiguration und Plattform des Projekts umschalten (#46).
    vscode.commands.registerCommand(`${Section}.selectBuild`, async () => {
      if (!client) {
        void vscode.window.showWarningMessage('Atlas läuft nicht.');
        return;
      }
      interface BuildProject {
        project: string;
        config: string;
        platform: string;
        configs: string[];
        platforms: string[];
      }
      const current = await client.sendRequest<{ projects: BuildProject[] }>('workspace/executeCommand', {
        command: 'atlas.server.selectBuild',
      });
      const project = current?.projects?.[0];
      if (!project) {
        void vscode.window.showWarningMessage('Atlas: Kein Projekt geladen.');
        return;
      }
      const config = await vscode.window.showQuickPick(project.configs.length > 0 ? project.configs : [project.config], {
        placeHolder: `Konfiguration (aktuell ${project.config})`,
      });
      if (config === undefined) {
        return;
      }
      const platform = await vscode.window.showQuickPick(
        project.platforms.length > 0 ? project.platforms : [project.platform],
        { placeHolder: `Plattform (aktuell ${project.platform})` },
      );
      if (platform === undefined) {
        return;
      }
      await client.sendRequest('workspace/executeCommand', {
        command: 'atlas.server.selectBuild',
        arguments: [{ config, platform }],
      });
    }),
    // Code Lens des Servers (#36): Referenzen, Nachfahren, Überschreibungen und Message-Handler anzeigen.
    vscode.commands.registerCommand(
      `${Section}.showLocations`,
      async (uri: string, position: LspPosition, locations: LspLocation[]) => {
        await vscode.commands.executeCommand(
          'editor.action.showReferences',
          vscode.Uri.parse(uri),
          toPosition(position),
          (locations ?? []).map(
            (item) =>
              new vscode.Location(
                vscode.Uri.parse(item.uri),
                new vscode.Range(toPosition(item.range.start), toPosition(item.range.end)),
              ),
          ),
        );
      },
    ),
  );
  await startClient();
}

export async function deactivate(): Promise<void> {
  await stopClient();
}
