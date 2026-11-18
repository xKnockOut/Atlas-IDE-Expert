unit Atlas.UI.Debug.OpenedFiles.Strings;

// Texte zu „vom Debugger geöffnete Dateien schließen“ (#842): Hinweise nach der Sitzung mit ihren Knöpfen, Befehl
// „Datei offen halten“, Meldungen und Einstellungen, auf Deutsch und Englisch (#1455). Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

{$SCOPEDENUMS ON}

type
  TAtlasOpenedFilesTextId = (
    OpenedTitle, OpenedAskText, OpenedClose, OpenedKeep, OpenedAlways, OpenedClosedText, OpenedReopen, PinCommand,
    PinDone, PinNotOpenedByDebugger, PreviewMessage, SettingsCloseOpenedFiles, SettingsCloseOff, SettingsCloseAsk,
    SettingsCloseAuto, SettingsPreviewTab);

  TAtlasOpenedFilesStrings = class
  public
    class function Text(AId: TAtlasOpenedFilesTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasOpenedFilesTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasOpenedFilesTextId] of string = (
    ('Vom Debugger geöffnete Dateien',
     '%d Dateien hat der Debugger geöffnet.',
     'Schließen',
     'Offen lassen',
     'Immer automatisch',
     '%d vom Debugger geöffnete Dateien geschlossen.',
     'Wieder öffnen',
     'Vom Debugger geöffnete Datei offen halten',
     'Atlas: %s bleibt nach der Debug-Sitzung offen.',
     'Atlas: Die aktuelle Datei hat nicht der Debugger geöffnet.',
     'Atlas: %s ist der Vorschau-Reiter des Debuggers (wird beim nächsten Wechsel geschlossen).',
     'Vom Debugger geöffnete Dateien nach der Sitzung schließen',
     'aus',
     'nachfragen',
     'automatisch',
     'Vom Debugger geöffnete Dateien teilen sich einen Reiter (Vorschau)'),
    ('Files opened by the debugger',
     'The debugger opened %d files.',
     'Close',
     'Keep open',
     'Always automatically',
     'Closed %d files opened by the debugger.',
     'Reopen',
     'Keep file opened by the debugger',
     'Atlas: %s stays open after the debug session.',
     'Atlas: The current file was not opened by the debugger.',
     'Atlas: %s is the debugger''s preview tab (closed on the next switch).',
     'Close files opened by the debugger after the session',
     'off',
     'ask',
     'automatically',
     'Files opened by the debugger share one tab (preview)'));

{ TAtlasOpenedFilesStrings }

class function TAtlasOpenedFilesStrings.Text(AId: TAtlasOpenedFilesTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasOpenedFilesStrings.Fmt(AId: TAtlasOpenedFilesTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
