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
  Atlas.UI.Search.Strings;

function Group(const AMessages: IOTAMessageServices; ACreate: Boolean): IOTAMessageGroup;
var
  mName: string;
begin
  mName := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchGroup);
  Result := AMessages.GetGroup(mName);
  if (Result = nil) and ACreate then
  begin
    Result := AMessages.AddMessageGroup(mName);
  end;
end;

class procedure TAtlasIdeSearchMessages.Show(const AFileName, ATitle: string;
  const AEntries: TArray<TAtlasSearchEntry>; ATotal: Integer);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mEntry: TAtlasSearchEntry;
  mPrefix: string;
  mLineRef: Pointer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget = nil then
  begin
    Exit;
  end;
  mMessages.ClearMessageGroup(mTarget);
  mMessages.AddTitleMessage(ATitle, mTarget);
  mPrefix := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchGroup);
  for mEntry in AEntries do
  begin
    mMessages.AddToolMessage(AFileName, mEntry.Text, mPrefix, mEntry.Line, mEntry.Column, nil, mLineRef, mTarget);
  end;
  if ATotal > Length(AEntries) then
  begin
    mMessages.AddTitleMessage(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchListMore, [ATotal - Length(AEntries)]),
      mTarget);
  end;
  mMessages.ShowMessageView(mTarget);
end;

class procedure TAtlasIdeSearchMessages.Start(const ATitle: string);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget = nil then
  begin
    Exit;
  end;
  mMessages.ClearMessageGroup(mTarget);
  mMessages.AddTitleMessage(ATitle, mTarget);
  mMessages.ShowMessageView(mTarget);
end;

class procedure TAtlasIdeSearchMessages.AddFile(const AFileName: string; const AEntries: TArray<TAtlasSearchEntry>);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
  mEntry: TAtlasSearchEntry;
  mPrefix: string;
  mLineRef: Pointer;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget = nil then
  begin
    Exit;
  end;
  mPrefix := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchGroup);
  for mEntry in AEntries do
  begin
    mMessages.AddToolMessage(AFileName, mEntry.Text, mPrefix, mEntry.Line, mEntry.Column, nil, mLineRef, mTarget);
  end;
end;

class procedure TAtlasIdeSearchMessages.AddTitle(const AText: string);
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, True);
  if mTarget <> nil then
  begin
    mMessages.AddTitleMessage(AText, mTarget);
  end;
end;

class procedure TAtlasIdeSearchMessages.Clear;
var
  mMessages: IOTAMessageServices;
  mTarget: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mTarget := Group(mMessages, False);
  if mTarget <> nil then
  begin
    mMessages.RemoveMessageGroup(mTarget);
  end;
end;

end.
