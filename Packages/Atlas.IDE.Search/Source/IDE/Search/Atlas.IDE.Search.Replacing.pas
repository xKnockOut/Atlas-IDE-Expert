unit Atlas.IDE.Search.Replacing;

// Ersetzen der Atlas-Suche (#893): „Ersetzen“ ersetzt den markierten Treffer und springt weiter; steht keiner
// markiert, springt es nur. „Alle ersetzen“ ersetzt im Bereich: in einer Datei als ein Rückgängig-Schritt
// (Schreiber der IDE), über Dateien über TAtlasIdeWorkspaceEdit mit dem Änderungsprotokoll (#721) nach einer
// frischen Suche. „Auswählen …“ zeigt die Treffer mit Häkchen im Fenster „Atlas-Suche: Ersetzen“;
// schreibgeschützte und seit der Suche geänderte Dateien werden gemeldet und übersprungen. Nur im Hauptthread.

interface

type
  TAtlasIdeSearchReplacing = class
  public
    class procedure Replace; static;
    class procedure ReplaceAll; static;
    class procedure Choose; static;
    /// <summary>Angehakte Treffer der Liste ersetzen.</summary>
    class procedure ReplaceChosen; static;
    class procedure Cancel; static;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.Files,
  Atlas.Core.Search.Replace,
  Atlas.Core.Search.ReplaceList,
  Atlas.Core.Search.Scopes,
  Atlas.Text.Lines,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings,
  Atlas.UI.Search.ReplaceFrame,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Search.FileSearch,
  Atlas.IDE.Search.ReplaceWindow,
  Atlas.IDE.Search.Editor,
  Atlas.IDE.Search.Session,
  Atlas.IDE.Search.Counter,
  Atlas.IDE.Search.AcrossFiles,
  Atlas.IDE.Search.Stepping;

/// <summary>„12 Ersetzungen in 3 Dateien“.</summary>
function ReplacedText(AReplacements, AFiles: Integer): string;
begin
  Result := TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaced, [AReplacements,
    TAtlasIdeSearchSession.Plural(AReplacements, TAtlasSearchTextId.SearchReplacementOne,
    TAtlasSearchTextId.SearchReplacementMany), AFiles,
    TAtlasIdeSearchSession.Plural(AFiles, TAtlasSearchTextId.SearchFileOne, TAtlasSearchTextId.SearchFileMany)]);
end;

/// <summary>Schreibgeschützt: offener Puffer der IDE, sonst die Datei auf der Platte.</summary>
function IsReadOnlyFile(const AFileName: string): Boolean;
var
  mBuffer: IOTAEditBuffer;
  mAttributes: DWORD;
begin
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    Exit(mBuffer.IsReadOnly);
  end;
  mAttributes := GetFileAttributes(PChar(AFileName));
  Result := (mAttributes <> INVALID_FILE_ATTRIBUTES) and ((mAttributes and FILE_ATTRIBUTE_READONLY) <> 0);
end;

/// <summary>Änderungen in die Puffer bzw. Dateien (#397, #721); '' oder der Fehler.</summary>
function ApplyEdit(const AEdit: TLspWorkspaceEdit; const AQueryText, AReplace: string): string;
var
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(AEdit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceAction, [AQueryText, AReplace]));
  Result := mOutcome.Error;
end;

/// <summary>Ersetzungen in einer Datei als ein Schritt; '' oder der Fehler (gemeldet).</summary>
function ApplyInFile(const AFileName: string; const ALines: TArray<string>;
  const AHits: TArray<TAtlasSearchHit>): string;
var
  mEdit: TLspWorkspaceEdit;
  mChanges: TLspFileEdits;
begin
  mChanges.FileName := AFileName;
  mChanges.Edits := TAtlasSearchReplace.Edits(ALines, AHits, TAtlasIdeSearchSession.Last,
    TAtlasIdeSearchSession.ReplaceText);
  mEdit := Default(TLspWorkspaceEdit);
  mEdit.Files := [mChanges];
  Result := ApplyEdit(mEdit, TAtlasIdeSearchSession.Last.Text, TAtlasIdeSearchSession.ReplaceText);
  if Result <> '' then
  begin
    TAtlasIdeSearchSession.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Result]));
  end;
end;

/// <summary>Leiste offen, Editor da, Suche gültig (nach Sync).</summary>
function Ready(out AView: IOTAEditView): Boolean;
begin
  TAtlasIdeSearchSession.SaveHistories;
  Result := (TAtlasIdeSearchSession.Bar <> nil) and TAtlasIdeSearchEditor.TopView(AView);
  if not Result then
  begin
    Exit;
  end;
  TAtlasIdeSearchSteps.Sync(False);
  Result := not TAtlasIdeSearchSession.Bar.HasError and not TAtlasIdeSearchSession.Last.IsEmpty;
end;

/// <summary>Schreibgeschützter Puffer: melden und True.</summary>
function RejectReadOnly(const AView: IOTAEditView): Boolean;
begin
  Result := AView.Buffer.IsReadOnly;
  if Result then
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceReadOnly,
      [ExtractFileName(AView.Buffer.FileName)]));
  end;
end;

/// <summary>Treffer ersetzen und weiter hinter dem neuen Text: Enthält er den Suchtext, wird er nicht gleich wieder
/// gefunden.</summary>
procedure ReplaceHit(const AView: IOTAEditView; const ALines: TArray<string>; const AHit: TAtlasSearchHit);
var
  mNewText, mLineText: string;
  mLines: TArray<string>;
  mTarget: TOTAEditPos;
begin
  mNewText := TAtlasSearchReplace.Edits(ALines, [AHit], TAtlasIdeSearchSession.Last,
    TAtlasIdeSearchSession.ReplaceText)[0].NewText;
  if ApplyInFile(AView.Buffer.FileName, ALines, [AHit]) <> '' then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(AView.Buffer));
  mLineText := '';
  if AHit.Line <= High(mLines) then
  begin
    mLineText := mLines[AHit.Line];
  end;
  mTarget.Line := AHit.Line + 1;
  mTarget.Col := TLspSession.IndexToColumn(mLineText, AHit.Character + Length(mNewText),
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.Block.Reset;
  AView.CursorPos := mTarget;
  TAtlasIdeSearchSession.Repaint;
  TAtlasIdeSearchSteps.TryNext(False);
end;

/// <summary>Über Dateien: frisch suchen (Ergebnisse von vorhin können veraltet sein), dann alle Treffer ersetzen.
/// </summary>
procedure ReplaceAllFiles;
begin
  TAtlasIdeSearchAcrossFiles.Start(TAtlasIdeSearchSession.Files.Listed,
    procedure
    var
      mIndex: Integer;
    begin
      if TAtlasIdeSearchSession.Files.List = nil then
      begin
        Exit;
      end;
      for mIndex := 0 to High(TAtlasIdeSearchSession.Files.List.Results) do
      begin
        TAtlasIdeSearchSession.Files.List.SetFileChecked(mIndex, True);
      end;
      TAtlasIdeSearchReplacing.ReplaceChosen;
    end);
end;

/// <summary>Eine Datei: alle Treffer im Bereich als ein Rückgängig-Schritt (ein Schreiber der IDE).</summary>
procedure ReplaceAllInFile(const AView: IOTAEditView);
var
  mLines: TArray<string>;
  mHits: TArray<TAtlasSearchHit>;
  mError: string;
  mLast: TAtlasSearchQuery;
begin
  mLast := TAtlasIdeSearchSession.Last;
  mLines := TTextLines.SplitLines(TAtlasEditorBuffer.Text(AView.Buffer));
  mHits := nil;
  if not mLast.Area.IsEmpty then
  begin
    mHits := TAtlasTextSearch.FindAll(mLines, mLast.Text, mLast.Options, mLast.Area);
  end;
  if Length(mHits) = 0 then
  begin
    TAtlasIdeSearchSession.Notice(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceNone));
    Exit;
  end;
  if RejectReadOnly(AView) then
  begin
    Exit;
  end;
  mError := ApplyInFile(AView.Buffer.FileName, mLines, mHits);
  if mError <> '' then
  begin
    TAtlasIdeSearchSession.Notice(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
    Exit;
  end;
  TAtlasIdeSearchSession.Notice(ReplacedText(Length(mHits), 1));
  TAtlasIdeSearchSession.Repaint;
  TAtlasIdeSearchCounter.Update;
end;

/// <summary>Eine Datei: ihre Treffer im Bereich als Liste für „Auswählen …“.</summary>
procedure ChooseInFile(const AView: IOTAEditView);
var
  mItem: TAtlasFileHits;
  mLast: TAtlasSearchQuery;
begin
  TAtlasIdeSearchAcrossFiles.Drop;
  mLast := TAtlasIdeSearchSession.Last;
  mItem := TAtlasFileSearch.SearchText(AView.Buffer.FileName, TAtlasEditorBuffer.Text(AView.Buffer), mLast);
  mItem.Hits := nil;
  if not mLast.Area.IsEmpty then
  begin
    mItem.Hits := TAtlasTextSearch.FindAll(mItem.Lines, mLast.Text, mLast.Options, mLast.Area);
  end;
  TAtlasIdeSearchSession.Files.List := TAtlasReplaceList.Create(mLast, TAtlasIdeSearchSession.ReplaceText);
  TAtlasIdeSearchSession.Files.List.Add(mItem);
  TAtlasIdeSearchSession.Files.Done := True;
end;

procedure WireFrame(AFrame: TAtlasSearchReplaceFrame);
begin
  AFrame.OnReplace :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Search,
        procedure
        begin
          TAtlasIdeSearchReplacing.ReplaceChosen;
        end);
    end;
  AFrame.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Search,
        procedure
        begin
          TAtlasIdeSearchAcrossFiles.OpenHit(AFileName, ALine, ACharacter);
        end);
    end;
  AFrame.SetNotice('');
end;

/// <summary>Vorab melden, was übersprungen wird; Zusatz „n übersprungen“ für den Bericht.</summary>
function ReportSkipped(const APlan: TAtlasReplacePlan): string;
var
  mFileName: string;
  mSkipped: Integer;
begin
  for mFileName in APlan.ReadOnly do
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceReadOnly, [mFileName]));
  end;
  for mFileName in APlan.Changed do
  begin
    TAtlasIdeSearchSession.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceChanged, [mFileName]));
  end;
  Result := '';
  mSkipped := Length(APlan.ReadOnly) + Length(APlan.Changed);
  if mSkipped > 0 then
  begin
    Result := ' · ' + TAtlasSearchStrings.Fmt(TAtlasSearchTextId.SearchReplaceSkipped, [mSkipped]);
  end;
end;

/// <summary>Plan ausführen; Bericht „n Ersetzungen in m Dateien“, „keine“ oder der Fehler.</summary>
function ApplyPlan(const APlan: TAtlasReplacePlan): string;
var
  mError: string;
  mList: TAtlasReplaceList;
begin
  if APlan.Replacements = 0 then
  begin
    Exit(TAtlasSearchStrings.Text(TAtlasSearchTextId.SearchReplaceNone));
  end;
  mList := TAtlasIdeSearchSession.Files.List;
  mError := ApplyEdit(APlan.Edit, mList.Query.Text, mList.Replace);
  if mError <> '' then
  begin
    TAtlasIdeSearchSession.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]));
    Result := TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mError]);
  end
  else
  begin
    Result := ReplacedText(APlan.Replacements, APlan.Files);
  end;
end;

{ TAtlasIdeSearchReplacing }

class procedure TAtlasIdeSearchReplacing.Replace;
var
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mArea: TAtlasSearchArea;
  mHits: TArray<TAtlasSearchHit>;
  mIndex: Integer;
begin
  if not Ready(mView) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := TTextLines.SplitLines(mText);
  mHits := nil;
  if TAtlasIdeSearchEditor.AreaOf(mText, TAtlasIdeSearchSession.Last, TAtlasIdeSearchEditor.CursorOf(mView, mLines),
    mArea) then
  begin
    mHits := TAtlasTextSearch.FindAll(mLines, TAtlasIdeSearchSession.Last.Text, TAtlasIdeSearchSession.Last.Options,
      mArea);
  end;
  mIndex := TAtlasIdeSearchEditor.MarkedHit(mView, mLines, mHits);
  // Kein Treffer markiert: erst hinspringen, der nächste Klick ersetzt.
  if mIndex < 0 then
  begin
    TAtlasIdeSearchSteps.TryNext(False);
  end
  else if not RejectReadOnly(mView) then
  begin
    ReplaceHit(mView, mLines, mHits[mIndex]);
  end;
end;

class procedure TAtlasIdeSearchReplacing.ReplaceAll;
var
  mView: IOTAEditView;
begin
  if not Ready(mView) then
  begin
    Exit;
  end;
  if TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) then
  begin
    ReplaceAllFiles;
  end
  else
  begin
    ReplaceAllInFile(mView);
  end;
end;

class procedure TAtlasIdeSearchReplacing.Choose;
var
  mView: IOTAEditView;
  mFrame: TAtlasSearchReplaceFrame;
begin
  if not Ready(mView) then
  begin
    Exit;
  end;
  mFrame := TAtlasIdeSearchReplaceWindow.Show;
  if mFrame = nil then
  begin
    Exit;
  end;
  WireFrame(mFrame);
  if not TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) then
  begin
    ChooseInFile(mView);
  end
  else if not TAtlasIdeSearchSession.FilesCurrent then
  begin
    TAtlasIdeSearchAcrossFiles.Start(TAtlasIdeSearchSession.Files.Listed, nil);
  end;
  TAtlasIdeSearchAcrossFiles.RefreshReplaceWindow('');
end;

class procedure TAtlasIdeSearchReplacing.ReplaceChosen;
var
  mPlan: TAtlasReplacePlan;
  mReport: string;
begin
  if TAtlasIdeSearchSession.Files.List = nil then
  begin
    Exit;
  end;
  TAtlasIdeSearchSession.Files.List.Replace := TAtlasIdeSearchSession.ReplaceText;
  mPlan := TAtlasIdeSearchSession.Files.List.Plan(
    function(const AFileName: string): Boolean
    begin
      Result := IsReadOnlyFile(AFileName);
    end,
    function(const AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end);
  mReport := ReportSkipped(mPlan);
  mReport := ApplyPlan(mPlan) + mReport;
  TAtlasIdeSearchSession.Say(mReport);
  TAtlasIdeSearchSession.Notice(mReport);
  // Die Ergebnisse stimmen nicht mehr: vergessen, das Fenster zeigt die Meldung.
  TAtlasIdeSearchAcrossFiles.Drop;
  TAtlasIdeSearchAcrossFiles.RefreshReplaceWindow(mReport);
  TAtlasIdeSearchSession.Repaint;
  if TAtlasIdeSearchSession.BarOpen and TAtlasSearchScopes.SpansFiles(TAtlasIdeSearchSession.Last.Scope) then
  begin
    TAtlasIdeSearchAcrossFiles.Schedule;
  end;
  TAtlasIdeSearchCounter.Update;
end;

class procedure TAtlasIdeSearchReplacing.Cancel;
begin
  TAtlasIdeFileSearch.Cancel;
end;

end.
