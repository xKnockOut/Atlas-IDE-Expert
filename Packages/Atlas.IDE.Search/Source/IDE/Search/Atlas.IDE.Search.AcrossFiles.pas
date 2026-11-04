unit Atlas.IDE.Search.AcrossFiles;

// Atlas-Suche über Dateien (#893): Bereiche „Offene Dateien“, „Projekt“, „Projektgruppe“. Nach einer Pause im
// Tippen sucht TAtlasIdeFileSearch im Hintergrund; die Ergebnisse stehen in TAtlasIdeSearchSession.Files, auf
// Wunsch nach und nach im Reiter „Atlas-Suche“ und im Fenster „Atlas-Suche: Ersetzen“. F3 springt über Dateien
// (aktive Datei mit ihrem aktuellen Text). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Search.Files;

type
  TAtlasIdeSearchAcrossFiles = class
  private
    class procedure FileFound(const AHits: TAtlasFileHits); static;
    class procedure Done(const ASummary: TAtlasFileSearchSummary); static;
    class procedure ListSummary(const ASummary: TAtlasFileSearchSummary); static;
    class procedure NoFiles; static;
    class procedure StartListing; static;
  public
    /// <summary>Takt nach der Pause im Tippen: beginnt die Suche, wenn die Leiste noch über Dateien sucht.</summary>
    class procedure Tick; static;
    /// <summary>Andere Suche: Die alte gilt nicht mehr; die neue beginnt nach einer Pause im Tippen.</summary>
    class procedure Schedule; static;
    /// <summary>Suche beginnen; AListed: in den Reiter „Atlas-Suche“; AThen: nach dem Ende ohne Abbruch.</summary>
    class procedure Start(AListed: Boolean; const AThen: TProc); static;
    /// <summary>Ergebnisse der aktuellen Suche in den Reiter „Atlas-Suche“ (Enter nach der Suche).</summary>
    class procedure List; static;
    /// <summary>Suche über Dateien beenden und vergessen (Thread beendet, Fenster leer).</summary>
    class procedure Drop; static;
    class procedure RefreshReplaceWindow(const ANotice: string); static;
    /// <summary>F3 über Dateien; ohne Suche beginnt sie und springt danach.</summary>
    class function Next(ABackward: Boolean): Boolean; static;
    /// <summary>Datei öffnen und den Treffer an ALine/ACharacter im aktuellen Text markieren.</summary>
    class procedure OpenHit(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.ReplaceList,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
  Atlas.UI.Search.Bar,
  Atlas.UI.Search.Strings,
  Atlas.UI.Search.ReplaceFrame,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Search.MessageList,
  Atlas.IDE.Search.FileSearch,
  Atlas.IDE.Search.ReplaceWindow,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session,
  Atlas.IDE.Search.Counter;

procedure StopTimer;
begin
  if TAtlasIdeSearchSession.Files.Timer <> nil then
  begin
    TAtlasIdeSearchSession.Files.Timer.Enabled := False;
  end;
end;

/// <summary>Was auf die fertige Suche gewartet hat, einmal ausführen.</summary>
procedure RunAfter;
var
  mAfter: TProc;
begin
  mAfter := TAtlasIdeSearchSession.Files.After;
  TAtlasIdeSearchSession.Files.After := nil;
  if Assigned(mAfter) then
  begin
    mAfter();
  end;
end;

/// <summary>Ergebnisse der Suche, die aktive Datei mit ihrem aktuellen Text.</summary>
function ResultsWithActive(const AView: IOTAEditView): TArray<TAtlasFileHits>;
var
  mActive: TAtlasFileHits;
  mIndex: Integer;
begin
  mActive := TAtlasFileSearch.SearchText(AView.Buffer.FileName, TAtlasEditorBuffer.Text(AView.Buffer),
    TAtlasIdeSearchSession.Last);
  Result := Copy(TAtlasIdeSearchSession.Files.List.Results);
  mIndex := TAtlasFileSearch.IndexOfFile(Result, AView.Buffer.FileName);
  if mIndex >= 0 then
  begin
    Result[mIndex] := mActive;
  end
  else if Length(mActive.Hits) > 0 then
  begin
    Result := TArray<TAtlasFileHits>.Create(mActive) + Result;
  end;
end;

/// <summary>Ab hier springt F3: Cursor, rückwärts der Anfang einer Markierung.</summary>
function StepFrom(const AView: IOTAEditView; const ALines: TArray<string>; ABackward: Boolean): TAtlasSearchPos;
var
  mSelection: TAtlasSearchArea;
begin
  Result := TAtlasIdeSearchEditor.CursorOf(AView, ALines);
  if ABackward and TAtlasIdeSearchEditor.SelectionOf(AView, ALines, mSelection) then
  begin
    Result := mSelection.Start;
  end;
end;

class procedure TAtlasIdeSearchAcrossFiles.Tick;
begin
  StopTimer;
  TAtlasGuard.Run(TAtlasFeature.Search,
    procedure
    begin
      // Nur, wenn die Leiste noch offen ist und der Bereich noch über Dateien geht.
      if TAtlasIdeSearchSession.BarOpen and TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) and
        not TAtlasIdeSearchSession.FilesCurrent then
      begin
        Start(False, nil);
      end;
    end);
end;

class procedure TAtlasIdeSearchAcrossFiles.Schedule;
begin
  if TAtlasIdeSearchSession.FilesCurrent or (TAtlasIdeSearchSession.Files.Timer = nil) then
  begin
    Exit;
  end;
  Drop;
  StopTimer;
  if TAtlasIdeSearchSession.Last.Text <> '' then
  begin
    TAtlasIdeSearchSession.Files.Timer.Enabled := True;
  end;
end;

class procedure TAtlasIdeSearchAcrossFiles.StartListing;
var
  mLast: TAtlasSearchQuery;
begin
  mLast := TAtlasIdeSearchSession.Last;
  TAtlasIdeSearchMessages.Start(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesTitle,
    [mLast.Text, TAtlasIdeSearchSession.IdentifierMode, TAtlasSearchBar.ScopeCaption(mLast.Scope)]));
end;

/// <summary>Keine Datei im Bereich (kein Projekt geöffnet): fertig mit nichts.</summary>
class procedure TAtlasIdeSearchAcrossFiles.NoFiles;
begin
  TAtlasIdeSearchSession.Files.Done := True;
  if TAtlasIdeSearchSession.Files.Listed then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoFiles));
  end;
  if TAtlasIdeSearchSession.Bar <> nil then
  begin
    TAtlasIdeSearchSession.Bar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoFiles));
  end;
  RunAfter;
end;

class procedure TAtlasIdeSearchAcrossFiles.Start(AListed: Boolean; const AThen: TProc);
var
  mLast: TAtlasSearchQuery;
begin
  Drop;
  StopTimer;
  mLast := TAtlasIdeSearchSession.Last;
  if mLast.Text = '' then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Files.Key := TAtlasIdeSearchSession.FilesKey(mLast);
  TAtlasIdeSearchSession.Files.List := TAtlasReplaceList.Create(mLast, TAtlasIdeSearchSession.ReplaceText);
  TAtlasIdeSearchSession.Files.Listed := AListed and TAtlasIdeSettings.Current.SearchResultsInMessages;
  TAtlasIdeSearchSession.Files.After := AThen;
  if TAtlasIdeSearchSession.Files.Listed then
  begin
    StartListing;
  end;
  if not TAtlasIdeFileSearch.Start(TAtlasIdeFileSearch.FilesOf(mLast.Scope), TAtlasIdeSearchSession.FileName, mLast,
    procedure(AHits: TAtlasFileHits)
    begin
      FileFound(AHits);
    end,
    procedure(ASummary: TAtlasFileSearchSummary)
    begin
      Done(ASummary);
    end) then
  begin
    NoFiles;
    Exit;
  end;
  if TAtlasIdeSearchSession.Bar <> nil then
  begin
    TAtlasIdeSearchSession.Bar.SetSearching(True);
  end;
  TAtlasIdeSearchCounter.Update;
end;

class procedure TAtlasIdeSearchAcrossFiles.FileFound(const AHits: TAtlasFileHits);
begin
  if TAtlasIdeSearchSession.Files.List = nil then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Files.List.Add(AHits);
  if TAtlasIdeSearchSession.Files.Listed then
  begin
    TAtlasIdeSearchMessages.AddFile(AHits.FileName, TAtlasSearchResults.Entries(AHits.Lines, AHits.Hits,
      TAtlasIdeSearchEditor.TabWidth));
  end;
  TAtlasIdeSearchCounter.Update;
  RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearchAcrossFiles.ListSummary(const ASummary: TAtlasFileSearchSummary);
begin
  TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesDone,
    [ASummary.Hits, ASummary.FilesWithHits, ASummary.Files]));
  if ASummary.Skipped > 0 then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesSkipped,
      [ASummary.Skipped]));
  end;
  if ASummary.Cancelled then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCancelled,
      [ASummary.Files]));
  end;
end;

class procedure TAtlasIdeSearchAcrossFiles.Done(const ASummary: TAtlasFileSearchSummary);
begin
  if TAtlasIdeSearchSession.Files.List = nil then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Files.Done := True;
  if TAtlasIdeSearchSession.Bar <> nil then
  begin
    TAtlasIdeSearchSession.Bar.SetSearching(False);
  end;
  if TAtlasIdeSearchSession.Files.Listed then
  begin
    ListSummary(ASummary);
  end;
  TAtlasIdeSearchCounter.Update;
  if ASummary.Cancelled and (TAtlasIdeSearchSession.Bar <> nil) then
  begin
    TAtlasIdeSearchSession.Bar.SetCounter(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchFilesCancelled,
      [ASummary.Files]));
  end;
  RefreshReplaceWindow('');
  // Was auf die fertige Suche gewartet hat (Alle ersetzen, F3); nicht nach einem Abbruch.
  if ASummary.Cancelled then
  begin
    TAtlasIdeSearchSession.Files.After := nil;
  end;
  RunAfter;
end;

class procedure TAtlasIdeSearchAcrossFiles.List;
var
  mItem: TAtlasFileHits;
  mWidth: Integer;
begin
  if (TAtlasIdeSearchSession.Files.List = nil) or TAtlasIdeSearchSession.Files.Listed or
    not TAtlasIdeSettings.Current.SearchResultsInMessages then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Files.Listed := True;
  StartListing;
  mWidth := TAtlasIdeSearchEditor.TabWidth;
  for mItem in TAtlasIdeSearchSession.Files.List.Results do
  begin
    TAtlasIdeSearchMessages.AddFile(mItem.FileName, TAtlasSearchResults.Entries(mItem.Lines, mItem.Hits, mWidth));
  end;
  if TAtlasIdeSearchSession.Files.Done then
  begin
    TAtlasIdeSearchMessages.AddTitle(TAtlasIdeSearchSession.FilesCounter(TAtlasSearchTextId.SearchFilesCounter));
  end;
end;

class procedure TAtlasIdeSearchAcrossFiles.Drop;
begin
  StopTimer;
  TAtlasIdeFileSearch.Stop;
  TAtlasIdeSearchSession.Files.After := nil;
  TAtlasIdeSearchSession.Files.Key := '';
  TAtlasIdeSearchSession.Files.Done := False;
  TAtlasIdeSearchSession.Files.Listed := False;
  if TAtlasIdeSearchSession.Bar <> nil then
  begin
    TAtlasIdeSearchSession.Bar.SetSearching(False);
  end;
  if TAtlasIdeSearchSession.Files.List = nil then
  begin
    Exit;
  end;
  FreeAndNil(TAtlasIdeSearchSession.Files.List);
  RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearchAcrossFiles.RefreshReplaceWindow(const ANotice: string);
var
  mFrame: TAtlasSearchReplaceFrame;
begin
  mFrame := TAtlasIdeSearchReplaceWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  if TAtlasIdeSearchSession.Files.List <> nil then
  begin
    TAtlasIdeSearchSession.Files.List.Replace := TAtlasIdeSearchSession.ReplaceText;
  end;
  mFrame.SetModel(TAtlasIdeSearchSession.Files.List);
  if ANotice <> '' then
  begin
    mFrame.SetNotice(ANotice);
  end;
end;

class procedure TAtlasIdeSearchAcrossFiles.OpenHit(const AFileName: string; ALine, ACharacter: Integer);
var
  mView: IOTAEditView;
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mIndex: Integer;
  mWrapped: Boolean;
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine, 0);
  if not TAtlasIdeSearchEditor.TopView(mView) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Mit dem aktuellen Text: Der Treffer kann sich seit der Suche verschoben haben.
  mLines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer));
  mHits := TAtlasTextSearch.FindAll(mLines, TAtlasIdeSearchSession.Last.Text, TAtlasIdeSearchSession.Last.Options,
    TAtlasSearchArea.Whole(mLines));
  if Length(mHits) = 0 then
  begin
    Exit;
  end;
  mIndex := TAtlasTextSearch.Next(mHits, TAtlasSearchPos.Create(ALine, ACharacter), False, mWrapped);
  TAtlasIdeSearchEditor.SelectHit(mView, mLines, mHits[mIndex]);
  TAtlasIdeSearchSession.Repaint;
end;

class function TAtlasIdeSearchAcrossFiles.Next(ABackward: Boolean): Boolean;
var
  mView: IOTAEditView;
  mLines: TArray<string>;
  mResults: TArray<TAtlasFileHits>;
  mLocation: TAtlasFileLocation;
  mHit: TAtlasSearchHit;
begin
  Result := TAtlasIdeSearchEditor.TopView(mView);
  if not Result then
  begin
    Exit;
  end;
  if not TAtlasIdeSearchSession.FilesCurrent then
  begin
    // Noch keine Suche über Dateien (Leiste zu): suchen, dann springen.
    Start(False,
      procedure
      begin
        if TAtlasIdeSearchSession.FilesCurrent then
        begin
          Next(ABackward);
        end;
      end);
    Exit;
  end;
  if not TAtlasIdeSearchSession.Files.Done and (Length(TAtlasIdeSearchSession.Files.List.Results) = 0) then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchFilesWait));
    Exit;
  end;
  // Die aktive Datei mit ihrem aktuellen Text, die übrigen wie gefunden.
  mLines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer));
  mResults := ResultsWithActive(mView);
  if not TAtlasFileSearch.NextLocation(mResults, mView.Buffer.FileName, StepFrom(mView, mLines, ABackward), ABackward,
    mLocation) then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchNothing,
      [TAtlasIdeSearchSession.Last.Text]));
    Exit;
  end;
  if mLocation.Wrapped then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWrapped));
  end;
  mHit := mResults[mLocation.FileIndex].Hits[mLocation.HitIndex];
  if SameText(mResults[mLocation.FileIndex].FileName, mView.Buffer.FileName) then
  begin
    TAtlasIdeSearchEditor.SelectHit(mView, mLines, mHit);
    TAtlasIdeSearchCounter.Update;
  end
  else
  begin
    OpenHit(mResults[mLocation.FileIndex].FileName, mHit.Line, mHit.Character);
  end;
end;

end.
