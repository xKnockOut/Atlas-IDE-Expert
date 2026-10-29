unit Atlas.IDE.Search.MessageList;

// Reiter „Atlas-Suche“ im Fenster Meldungen (#878): eine eigene
// Meldungsgruppe mit einer Kopfzeile (Suchtext, Modus, Datei, Bereich,
// Anzahl) und je Treffer einer Zeile mit Datei, Zeile, Spalte und
// Zeilentext; Doppelklick springt hin (Werkzeugmeldung der IDE). Jede neue
// Liste ersetzt die vorige. Ist search.resultsInMessages aus, verschwindet
// der Reiter (Clear). Suche über Dateien (#893): Start mit der Kopfzeile,
// dann je Datei AddFile, sobald sie durchsucht ist, zuletzt AddTitle mit der
// Zusammenfassung. Nur im Hauptthread.

interface

uses
  Atlas.Core.Search.Results;

type
  TAtlasIdeSearchMessages = class
  public
    /// <summary>Gruppe neu füllen und zeigen. ATotal: Anzahl aller Treffer (AEntries ist gekappt).</summary>
    class procedure Show(const AFileName, ATitle: string; const AEntries: TArray<TAtlasSearchEntry>;
      ATotal: Integer); static;
    /// <summary>Gruppe leeren, Kopfzeile schreiben und zeigen (Suche über Dateien).</summary>
    class procedure Start(const ATitle: string); static;
    /// <summary>Treffer einer Datei anhängen.</summary>
    class procedure AddFile(const AFileName: string; const AEntries: TArray<TAtlasSearchEntry>); static;
    /// <summary>Zeile ohne Ort anhängen (Zusammenfassung, übersprungene Dateien).</summary>
    class procedure AddTitle(const AText: string); static;
    /// <summary>Reiter entfernen.</summary>
    class procedure Clear; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.UI.Strings;

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  Name: string;
begin
  Name := TAtlasStrings.Text(TAtlasTextId.SearchGroup);
  Result := AMessages.GetGroup(Name);
  if (Result = nil) and ACreate then
    Result := AMessages.AddMessageGroup(Name);
end;

class procedure TAtlasIdeSearchMessages.Show(const AFileName, ATitle: string;
  const AEntries: TArray<TAtlasSearchEntry>; ATotal: Integer);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Entry: TAtlasSearchEntry;
  Prefix: string;
  LineRef: Pointer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target = nil then
    Exit;
  Messages.ClearMessageGroup(Target);
  Messages.AddTitleMessage(ATitle, Target);
  Prefix := TAtlasStrings.Text(TAtlasTextId.SearchGroup);
  for Entry in AEntries do
    Messages.AddToolMessage(AFileName, Entry.Text, Prefix, Entry.Line, Entry.Column, nil, LineRef, Target);
  if ATotal > Length(AEntries) then
    Messages.AddTitleMessage(TAtlasStrings.Fmt(TAtlasTextId.SearchListMore, [ATotal - Length(AEntries)]), Target);
  Messages.ShowMessageView(Target);
end;

class procedure TAtlasIdeSearchMessages.Start(const ATitle: string);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target = nil then
    Exit;
  Messages.ClearMessageGroup(Target);
  Messages.AddTitleMessage(ATitle, Target);
  Messages.ShowMessageView(Target);
end;

class procedure TAtlasIdeSearchMessages.AddFile(const AFileName: string; const AEntries: TArray<TAtlasSearchEntry>);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
  Entry: TAtlasSearchEntry;
  Prefix: string;
  LineRef: Pointer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target = nil then
    Exit;
  Prefix := TAtlasStrings.Text(TAtlasTextId.SearchGroup);
  for Entry in AEntries do
    Messages.AddToolMessage(AFileName, Entry.Text, Prefix, Entry.Line, Entry.Column, nil, LineRef, Target);
end;

class procedure TAtlasIdeSearchMessages.AddTitle(const AText: string);
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, True);
  if Target <> nil then
    Messages.AddTitleMessage(AText, Target);
end;

class procedure TAtlasIdeSearchMessages.Clear;
var
  Messages: IOTAMessageServices;
  Target: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Exit;
  Target := Group(Messages, False);
  if Target <> nil then
    Messages.RemoveMessageGroup(Target);
end;

end.
