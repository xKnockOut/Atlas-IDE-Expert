unit Atlas.IDE.Search.Session;

// Zustand der Atlas-Suche im Editor (#877, #878, #893), geteilt von Leiste, Zeichner, Zähler, Suche über Dateien,
// Schritten und Ersetzen: letzte Suche, offene Leiste, Stand beim Öffnen, Verlauf und die Suche über Dateien.
// TAtlasIdeSearch (Commands) legt ihn in Install an und räumt ihn in Uninstall ab. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.ReplaceList,
  Atlas.UI.Search.Bar,
  Atlas.UI.Search.Strings,
  Atlas.IDE.Search.HistoryFile;

type
  /// <summary>Suche über Dateien (#893): Ergebnisse, Schlüssel der Suche, Stand und was danach kommt.</summary>
  TAtlasIdeSearchFilesState = record
    List: TAtlasReplaceList;
    Key: string;
    Done: Boolean;
    Listed: Boolean;
    After: TProc;
    // Pause im Tippen, nach der die Suche beginnt.
    Timer: TTimer;
  end;

  TAtlasIdeSearchSession = class
  public class var
    Last: TAtlasSearchQuery;
    // Steigt bei jeder neuen Suche; Teil des Schlüssels des Zeichners.
    Version: Integer;
    // Leiste der laufenden Suche und Stand beim Öffnen.
    Bar: TAtlasSearchBar;
    Origin: TAtlasSearchPos;
    Selection: TAtlasSearchArea;
    FileName: string;
    Highlight: Boolean;
    // Schlüssel der zuletzt im Reiter „Atlas-Suche“ gelisteten Suche in einer Datei.
    ListedKey: string;
    // Schreibt eine Zeile in die Meldungsansicht.
    OnMessage: TProc<string>;
    Histories: TAtlasIdeSearchHistories;
    Files: TAtlasIdeSearchFilesState;
  public
    class procedure Say(const AText: string); static;
    /// <summary>Meldung in der Leiste bis zur nächsten Suche.</summary>
    class procedure Notice(const AText: string); static;
    /// <summary>Neue Suche für den Zeichner; der oberste Editor zeichnet neu.</summary>
    class procedure Repaint; static;
    class function BarOpen: Boolean; static;
    class function ReplaceText: string; static;
    class procedure SaveHistories; static;
    class function FilesKey(const AQuery: TAtlasSearchQuery): string; static;
    /// <summary>Gehört die Suche über Dateien (laufend oder fertig) zur letzten Suche?</summary>
    class function FilesCurrent: Boolean; static;
    /// <summary>„1 Datei“, „3 Dateien“.</summary>
    class function Plural(ACount: Integer; AOne, AMany: TAtlasSearchTextId): string; static;
    /// <summary>Zusatz „Bezeichner“ für Titel, wenn die letzte Suche nur Bezeichner findet.</summary>
    class function IdentifierMode: string; static;
    /// <summary>„n Treffer in m Dateien“ der Suche über Dateien im Format AId.</summary>
    class function FilesCounter(AId: TAtlasSearchTextId): string; static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Search.Scopes,
  Atlas.IDE.Search.Editor;

class procedure TAtlasIdeSearchSession.Say(const AText: string);
begin
  if Assigned(OnMessage) then
  begin
    OnMessage(AText);
  end;
end;

class procedure TAtlasIdeSearchSession.Notice(const AText: string);
begin
  if Bar <> nil then
  begin
    Bar.SetNotice(AText);
  end;
end;

class procedure TAtlasIdeSearchSession.Repaint;
var
  mView: IOTAEditView;
begin
  Inc(Version);
  if TAtlasIdeSearchEditor.TopView(mView) then
  begin
    mView.Paint;
  end;
end;

class function TAtlasIdeSearchSession.BarOpen: Boolean;
begin
  Result := (Bar <> nil) and Bar.Visible;
end;

class function TAtlasIdeSearchSession.ReplaceText: string;
begin
  Result := '';
  if Bar <> nil then
  begin
    Result := Bar.ReplaceText;
  end;
end;

class procedure TAtlasIdeSearchSession.SaveHistories;
begin
  if Histories <> nil then
  begin
    Histories.Save;
  end;
end;

class function TAtlasIdeSearchSession.FilesKey(const AQuery: TAtlasSearchQuery): string;
begin
  Result := AQuery.Text + #0 + BoolToStr(AQuery.Options.CaseSensitive) + BoolToStr(AQuery.Options.WholeWord) +
    BoolToStr(AQuery.Options.Identifier) + BoolToStr(AQuery.Options.Regex) + #0 + IntToStr(Ord(AQuery.Scope));
end;

class function TAtlasIdeSearchSession.FilesCurrent: Boolean;
begin
  Result := (Files.List <> nil) and TAtlasSearchScopes.SpansFiles(Last.Scope) and (Files.Key = FilesKey(Last));
end;

class function TAtlasIdeSearchSession.Plural(ACount: Integer; AOne, AMany: TAtlasSearchTextId): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasSearchStrings.Text(AOne);
  end
  else
  begin
    Result := TAtlasSearchStrings.Text(AMany);
  end;
end;

class function TAtlasIdeSearchSession.IdentifierMode: string;
begin
  Result := '';
  if Last.Options.Identifier then
  begin
    Result := TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchListIdentifier);
  end;
end;

class function TAtlasIdeSearchSession.FilesCounter(AId: TAtlasSearchTextId): string;
var
  mFiles: Integer;
begin
  mFiles := Length(Files.List.Results);
  Result := TAtlasSearchStrings.Fmt(AId, [Files.List.HitCount, mFiles,
    Plural(mFiles, TAtlasSearchTextId.SearchFileOne, TAtlasSearchTextId.SearchFileMany)]);
end;

end.
