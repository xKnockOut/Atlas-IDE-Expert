unit Atlas.IDE.Search.Stepping;

// Atlas-Suche im Editor (#877, #878, #893, #1242):
// - Sync übernimmt die Suche der Leiste: Treffer hervorheben, auf Wunsch zum nächsten ab dem Ursprung springen,
//   bei Bereichen über Dateien die Suche im Hintergrund planen. Ungültiger Regex färbt das Feld rot.
// - TryNext (F3/Umschalt+F3) springt mit Umlauf, über Dateien mit den Ergebnissen im Hintergrund. Ist ein anderer
//   Text einzeilig markiert als zuletzt gesucht, sucht F3 nach der Markierung.
// - List (Enter bzw. „In Meldungen“) listet alle Treffer im Reiter „Atlas-Suche“; dieselbe Suche wird nicht
//   erneut aufgebaut.
// Nur im Hauptthread.

interface

type
  TAtlasIdeSearchSteps = class
  public
    /// <summary>Suche der Leiste übernehmen; AJump: zum nächsten Treffer ab dem Ursprung springen.</summary>
    class procedure Sync(AJump: Boolean); static;
    /// <summary>F3/Umschalt+F3: False ohne letzte Atlas-Suche oder ohne Editor.</summary>
    class function TryNext(ABackward: Boolean): Boolean; static;
    /// <summary>Alle Treffer der Leiste in den Reiter „Atlas-Suche“.</summary>
    class procedure List; static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Scopes,
  Atlas.Core.Search.Results,
  Atlas.Text.Lines,
  Atlas.UI.Search.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Search.MessageList,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session,
  Atlas.IDE.Search.Counter,
  Atlas.IDE.Search.AcrossFiles;

/// <summary>Anderes Dokument im selben Fenster: neuer Ursprung am Cursor, Auswahl gilt nicht mehr.</summary>
procedure FollowDocument(const AView: IOTAEditView; const ALines: TArray<string>);
begin
  if SameText(TAtlasIdeSearchSession.FileName, AView.Buffer.FileName) then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.FileName := AView.Buffer.FileName;
  TAtlasIdeSearchSession.Origin := TAtlasIdeSearchEditor.CursorOf(AView, ALines);
  TAtlasIdeSearchSession.Selection := TAtlasSearchArea.Create(0, 0, 0, 0);
end;

/// <summary>Ungültiger Ausdruck (#893): Feld rot, Fehlertext der Engine, nichts markiert, gezählt oder gesucht.
/// </summary>
function RejectInvalid(const AQuery: TAtlasSearchQuery): Boolean;
var
  mError: string;
begin
  Result := AQuery.Options.Regex and not TAtlasSearchRegex.Check(AQuery.Text, mError);
  if not Result then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Last := AQuery;
  TAtlasIdeSearchSession.Highlight := False;
  TAtlasIdeSearchAcrossFiles.Drop;
  TAtlasIdeSearchSession.Repaint;
  TAtlasIdeSearchSession.Bar.SetError(mError);
  TAtlasIdeSearchSession.Bar.SetCounter('');
  TAtlasIdeSearchSession.Bar.ClearPreview;
end;

/// <summary>Kein Bereich (Cursor außerhalb jeder Methode, keine Auswahl): nichts hervorheben, Hinweis im Zähler.
/// </summary>
procedure ShowNoArea(const AQuery: TAtlasSearchQuery);
begin
  TAtlasIdeSearchSession.Last := AQuery;
  TAtlasIdeSearchSession.Last.Area := TAtlasSearchArea.Create(0, 0, 0, 0);
  TAtlasIdeSearchSession.Highlight := False;
  TAtlasIdeSearchSession.Repaint;
  if AQuery.Scope = TAtlasSearchScope.Method then
  begin
    TAtlasIdeSearchSession.Bar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoMethod));
  end
  else
  begin
    TAtlasIdeSearchSession.Bar.SetCounter(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoSelection));
  end;
end;

/// <summary>Erster Treffer oder nächster ab der Stelle beim Öffnen (#1242, search.fromFirstHit).</summary>
procedure JumpFromOrigin(const AView: IOTAEditView; const ALines: TArray<string>);
var
  mHits: TArray<TAtlasSearchHit>;
  mIndex: Integer;
  mWrapped: Boolean;
begin
  mHits := TAtlasTextSearch.FindAll(ALines, TAtlasIdeSearchSession.Last.Text, TAtlasIdeSearchSession.Last.Options,
    TAtlasIdeSearchSession.Last.Area);
  if Length(mHits) = 0 then
  begin
    Exit;
  end;
  mIndex := 0;
  if not TAtlasIdeSettings.Current.SearchFromFirstHit then
  begin
    mIndex := TAtlasTextSearch.Next(mHits, TAtlasIdeSearchSession.Origin, False, mWrapped);
  end;
  TAtlasIdeSearchEditor.SelectHit(AView, ALines, mHits[mIndex]);
end;

/// <summary>Anderer Text einzeilig markiert als zuletzt gesucht: nach der Markierung suchen. Liefert die Stelle,
/// ab der F3 springt: vorwärts ab dem Ende der Markierung (dem Cursor), rückwärts ab ihrem Anfang.</summary>
function FollowMarked(const AView: IOTAEditView; const ALines: TArray<string>; ABackward: Boolean): TAtlasSearchPos;
var
  mSelection: TAtlasSearchArea;
  mHasSelection, mChanged: Boolean;
  mMarked: string;
begin
  Result := TAtlasIdeSearchEditor.CursorOf(AView, ALines);
  mHasSelection := TAtlasIdeSearchEditor.SelectionOf(AView, ALines, mSelection);
  mMarked := TAtlasIdeSearchEditor.LineSelection(ALines, mSelection, mHasSelection);
  if mMarked <> '' then
  begin
    TAtlasIdeSearchSession.Last := TAtlasSearchResults.FollowSelection(TAtlasIdeSearchSession.Last, mMarked,
      mChanged);
    if mChanged then
    begin
      TAtlasIdeSearchSession.Last.FileName := AView.Buffer.FileName;
      TAtlasIdeSearchSession.Repaint;
    end;
  end;
  if ABackward and mHasSelection then
  begin
    Result := mSelection.Start;
  end;
end;

/// <summary>Bereich für F3; außerhalb jeder Routine die ganze Unit statt gar nichts. False: kein Bereich (Meldung).
/// </summary>
function StepArea(const AText: string; const ALines: TArray<string>; const AFrom: TAtlasSearchPos;
  out AArea: TAtlasSearchArea): Boolean;
begin
  Result := True;
  if TAtlasIdeSearchEditor.AreaOf(AText, TAtlasIdeSearchSession.Last, AFrom, AArea) then
  begin
    Exit;
  end;
  if TAtlasIdeSearchSession.Last.Scope <> TAtlasSearchScope.Method then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchNoSelection));
    Exit(False);
  end;
  TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchOutsideMethod));
  AArea := TAtlasSearchArea.Whole(ALines);
end;

procedure StepIn(const AView: IOTAEditView; const ALines: TArray<string>; const AArea: TAtlasSearchArea;
  const AFrom: TAtlasSearchPos; ABackward: Boolean);
var
  mHits: TArray<TAtlasSearchHit>;
  mIndex: Integer;
  mWrapped: Boolean;
begin
  mHits := TAtlasTextSearch.FindAll(ALines, TAtlasIdeSearchSession.Last.Text, TAtlasIdeSearchSession.Last.Options,
    AArea);
  if Length(mHits) = 0 then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchNothing,
      [TAtlasIdeSearchSession.Last.Text]));
    Exit;
  end;
  mIndex := TAtlasTextSearch.Next(mHits, AFrom, ABackward, mWrapped);
  if mWrapped then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchWrapped));
  end;
  TAtlasIdeSearchEditor.SelectHit(AView, ALines, mHits[mIndex]);
  TAtlasIdeSearchCounter.Update;
end;

/// <summary>Schlüssel einer Liste in einer Datei: Suche, Optionen, Bereich und Text.</summary>
function ListKey(const AText: string): string;
var
  mLast: TAtlasSearchQuery;
begin
  mLast := TAtlasIdeSearchSession.Last;
  Result := TAtlasIdeSearchSession.FileName + #0 + TAtlasIdeSearchSession.FilesKey(mLast) + #0 +
    IntToStr(mLast.Area.Start.Line) + ':' + IntToStr(mLast.Area.Start.Character) + '-' +
    IntToStr(mLast.Area.Stop.Line) + ':' + IntToStr(mLast.Area.Stop.Character) + #0 + AText;
end;

/// <summary>Zusatz zum Titel: Methode oder Auswahl.</summary>
function ListPlace(const AText: string): string;
var
  mRoutines: TArray<TAtlasSearchRoutine>;
begin
  Result := '';
  case TAtlasIdeSearchSession.Last.Scope of
    TAtlasSearchScope.Method:
      begin
        mRoutines := TAtlasSearchScopes.RoutinesAt(AText, TAtlasIdeSearchSession.Last.Area.Start);
        if Length(mRoutines) > 0 then
        begin
          Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchListScopeMethod,
            [TAtlasSearchResults.RoutineName(mRoutines[0].Caption)]);
        end;
      end;
    TAtlasSearchScope.Selection:
      Result := ', ' + TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchScopeSelection);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Treffer der aktiven Datei listen; False, wenn dieselbe Suche im selben Text schon steht.</summary>
function ListUnit(const AView: IOTAEditView): Boolean;
var
  mText, mKey, mFileName: string;
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mLast: TAtlasSearchQuery;
begin
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  // Dieselbe Suche im selben Text nicht erneut aufbauen (Enter springt auch nur weiter).
  mKey := ListKey(mText);
  Result := mKey <> TAtlasIdeSearchSession.ListedKey;
  if not Result then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.ListedKey := mKey;
  mLast := TAtlasIdeSearchSession.Last;
  mFileName := TAtlasIdeSearchSession.FileName;
  mLines := TTextLines.SplitLines(mText);
  mHits := TAtlasTextSearch.FindAll(mLines, mLast.Text, mLast.Options, mLast.Area);
  TAtlasIdeSearchMessages.Show(mFileName, TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchListTitle,
    [mLast.Text, TAtlasIdeSearchSession.IdentifierMode, ExtractFileName(mFileName), ListPlace(mText), Length(mHits)]),
    TAtlasSearchResults.Entries(mLines, mHits, TAtlasEditorBuffer.TabWidth(AView.Buffer)), Length(mHits));
end;

{ TAtlasIdeSearchSteps }

class procedure TAtlasIdeSearchSteps.Sync(AJump: Boolean);
var
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mQuery: TAtlasSearchQuery;
  mArea: TAtlasSearchArea;
begin
  if (TAtlasIdeSearchSession.Bar = nil) or not TAtlasIdeSearchEditor.TopView(mView) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := TTextLines.SplitLines(mText);
  FollowDocument(mView, mLines);
  mQuery := TAtlasIdeSearchSession.Bar.Query;
  mQuery.FileName := TAtlasIdeSearchSession.FileName;
  if RejectInvalid(mQuery) then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Bar.SetError('');
  // Eine Meldung wie „12 Ersetzungen in 3 Dateien“ gilt bis zur nächsten Suche.
  TAtlasIdeSearchSession.Bar.SetNotice('');
  if not TAtlasSearchScopes.AreaFor(mText, mQuery.Scope, TAtlasIdeSearchSession.Origin,
    TAtlasIdeSearchSession.Selection, mQuery.Level, mArea) then
  begin
    ShowNoArea(mQuery);
    Exit;
  end;
  // Gemerkt wird der Bereich beim Suchen (Auswahl; Methode als Rückfall außerhalb jeder Routine).
  mQuery.Area := mArea;
  TAtlasIdeSearchSession.Last := mQuery;
  TAtlasIdeSearchSession.Highlight := True;
  TAtlasIdeSearchSession.Repaint;
  if AJump then
  begin
    JumpFromOrigin(mView, mLines);
  end;
  // Über Dateien: nach einer Pause im Tippen im Hintergrund; sonst gilt eine frühere Suche nicht mehr.
  if TAtlasSearchScopes.SpansFiles(mQuery.Scope) then
  begin
    TAtlasIdeSearchAcrossFiles.Schedule;
  end
  else
  begin
    TAtlasIdeSearchAcrossFiles.Drop;
  end;
  TAtlasIdeSearchCounter.Update;
end;

class function TAtlasIdeSearchSteps.TryNext(ABackward: Boolean): Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mArea: TAtlasSearchArea;
  mFrom: TAtlasSearchPos;
begin
  Result := False;
  if TAtlasIdeSearchSession.Last.IsEmpty or not TAtlasIdeSearchEditor.TopView(mView) then
  begin
    Exit;
  end;
  // Über Dateien (#893): mit den Ergebnissen der Suche im Hintergrund.
  if TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) and
    TAtlasIdeSettings.Current.SearchMultiFile then
  begin
    Exit(TAtlasIdeSearchAcrossFiles.Next(ABackward));
  end;
  // Auswahl gilt nur in der Datei, in der gesucht wurde; in anderen Dateien die ganze Unit.
  if (TAtlasIdeSearchSession.Last.Scope = TAtlasSearchScope.Selection) and
    not SameText(TAtlasIdeSearchSession.Last.FileName, mView.Buffer.FileName) then
  begin
    TAtlasIdeSearchSession.Last.Scope := TAtlasSearchScope.UnitFile;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := TTextLines.SplitLines(mText);
  mFrom := FollowMarked(mView, mLines, ABackward);
  Result := True;
  if StepArea(mText, mLines, mFrom, mArea) then
  begin
    StepIn(mView, mLines, mArea, mFrom, ABackward);
  end;
end;

class procedure TAtlasIdeSearchSteps.List;
var
  mView: IOTAEditView;
  mListed: Boolean;
begin
  if (TAtlasIdeSearchSession.Bar = nil) or not TAtlasIdeSettings.Current.SearchResultsInMessages or
    not TAtlasIdeSearchEditor.TopView(mView) then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.SaveHistories;
  Sync(False);
  if TAtlasIdeSearchSession.Last.IsEmpty or TAtlasIdeSearchSession.Last.Area.IsEmpty or
    TAtlasIdeSearchSession.Bar.HasError then
  begin
    Exit;
  end;
  mListed := True;
  // Über Dateien (#893): die laufende bzw. fertige Suche auflisten, sonst eine neue beginnen.
  if not TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) then
  begin
    mListed := ListUnit(mView);
  end
  else if TAtlasIdeSearchSession.FilesCurrent then
  begin
    TAtlasIdeSearchAcrossFiles.List;
  end
  else
  begin
    TAtlasIdeSearchAcrossFiles.Start(True, nil);
  end;
  // Das Meldungsfenster nimmt beim Zeigen den Fokus; zurück in die Leiste.
  if mListed and (TAtlasIdeSearchSession.Bar <> nil) then
  begin
    TAtlasIdeSearchSession.Bar.FocusText;
  end;
end;

end.
