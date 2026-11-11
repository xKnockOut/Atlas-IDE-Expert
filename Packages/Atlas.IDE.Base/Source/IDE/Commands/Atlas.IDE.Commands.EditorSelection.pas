unit Atlas.IDE.Commands.EditorSelection;

// Editorbefehle für Auswahl und Sprünge (#399), Vorfahr von
// TAtlasIdeEditorCommands (Atlas.IDE.Commands.Editor, Beschreibung dort):
// Auswahl erweitern und verkleinern, Gehe zu Typdefinition, Sicher löschen,
// Deklaration ⇄ Implementierung (#775), Sprung zum Gegenstück (#635),
// nächster/vorheriger Befund (#509) und F3 mit Markierung.

interface

uses
  ToolsAPI,
  Atlas.Core.Lsp.TextChanges,
  Atlas.IDE.Commands.EditorContext;

type
  /// <summary>Editorbefehle für Auswahl und Sprünge.</summary>
  TAtlasEditorSelectionCommands = class(TAtlasEditorCommandContext)
  protected
    class procedure Step(AExpand: Boolean); static;
    /// <summary>Einzeilige Markierung der Ansicht als Suchtext; False ohne solche.</summary>
    class function SelectedNeedle(const AView: IOTAEditView; out ANeedle: string): Boolean; static;
  public
    class procedure ExpandSelection; static;
    class procedure ShrinkSelection; static;
    class procedure GoToTypeDefinition; static;
    /// <summary>„Sicher löschen“ für das Symbol am Cursor (#716, Alt+Entf).</summary>
    class procedure SafeDelete; static;
    /// <summary>Cursor zum Gegenstück der Methode am Cursor (Deklaration ⇄ Implementierung, #775); False ohne
    /// Gegenstück, dann ohne Meldung (die Taste geht an die IDE weiter).</summary>
    class function TryToggleMethod: Boolean; static;
    /// <summary>Wie TryToggleMethod, für Menü und Palette: ohne Gegenstück eine Zeile in der Meldungsansicht.</summary>
    class procedure ToggleMethod; static;
    /// <summary>Sprung zum Gegenstück (#635) reihum; mit ASelect vom Cursor bis zum Gegenstück markieren. Ohne
    /// eindeutiges Gegenstück passiert nichts.</summary>
    class procedure JumpToMatch(ASelect: Boolean); static;
    /// <summary>F3 bzw. Umschalt+F3 mit einzeiliger Markierung: nächstes bzw. vorheriges Vorkommen markieren
    /// und als Suchtext der IDE übernehmen. False ohne solche Markierung (die Taste geht an die IDE). Mit
    /// „Gleichen Text hervorheben“ (#709) gelten dessen Optionen; ist dort F3 abgeschaltet, geht die Taste bei
    /// passender Markierung an die IDE.</summary>
    class function TryFindSelection(ABackward: Boolean): Boolean; static;
    /// <summary>Cursor zum nächsten (AForward) bzw. vorherigen Befund der oberen Datei (#509); ohne Befund eine
    /// Zeile in der Meldungsansicht.</summary>
    class procedure StepProblem(AForward: Boolean); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Selection,
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Editor.Match,
  Atlas.Core.Editor.SelectionMatches,
  Atlas.Core.Editor.SafeDelete,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Build.Target,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.InlineHints,
  Atlas.Text.Defines,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Strings,
  Atlas.IDE.Build.Target,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.SafeDelete;

/// <summary>Symbole der bedingten Übersetzung des aktiven Projekts (Plattform und DCC_Define), damit der
/// Methodenwechsel dieselben $IFDEF-Zweige sieht wie der Compiler; nil ohne Projekt (dann Delphi für Win32).</summary>
function ProjectDefines: TArray<string>;
var
  mTarget: TAtlasBuildTarget;
begin
  Result := nil;
  if TAtlasIdeBuildTarget.Read(mTarget) then
  begin
    Result := TTextDefines.Predefined(mTarget.Platform, CompilerVersion) + mTarget.Defines;
  end;
end;

type
  /// <summary>Suchtext von F3 mit den Optionen von „Gleichen Text hervorheben“ (Matching), sonst als Text.</summary>
  TNeedleSearch = record
    Needle: string;
    Matching: Boolean;
    Options: TAtlasSelectionMatchOptions;
  end;

/// <summary>Treffer von ASearch ab AFrom.</summary>
function FindNeedle(const ALines: TArray<string>; const ASearch: TNeedleSearch; const AFrom: TLspTextPosition;
  ABackward: Boolean; out AFound: TLspRange): Boolean;
begin
  if ASearch.Matching then
  begin
    Result := TAtlasSelectionMatches.Next(ALines, ASearch.Needle, ASearch.Options, AFrom, ABackward, AFound);
  end
  else
  begin
    Result := TAtlasSelectionSearch.Find(ALines, ASearch.Needle, AFrom, ABackward, AFound);
  end;
end;

/// <summary>Suchtext der IDE: Strg+F und „Erneut suchen“ ohne Markierung machen damit weiter. Ohne Position oder
/// Suchoptionen (Ansicht im Abbau) bleibt der Suchtext, wie er ist.</summary>
procedure TakeSearchText(const AView: IOTAEditView; const ANeedle: string);
var
  mPosition: IOTAEditPosition;
  mOptions: IOTASearchOptions;
begin
  mPosition := AView.Position;
  if mPosition = nil then
  begin
    Exit;
  end;
  mOptions := mPosition.SearchOptions;
  if mOptions = nil then
  begin
    Exit;
  end;
  try
    mOptions.SearchText := ANeedle;
  except
    // Der Suchtext ist Zugabe: Die Markierung des Treffers geht trotzdem weiter. Ins Protokoll, damit ein
    // Fehler der IDE an dieser Stelle sichtbar wird statt still zu verschwinden.
    on E: Exception do
      TAtlasGuard.Log('Suchtext der IDE setzen: ' + TAtlasGuard.ErrorText(E)); // german-ok Protokoll
  end;
end;

class procedure TAtlasEditorSelectionCommands.Step(AExpand: Boolean);
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection, mNext: TLspRange;
  mPosition: TLspTextPosition;
  mChain: TArray<TLspRange>;
  mMoved: Boolean;
begin
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  // Erstes Erweitern an dieser Stelle: Der Cursor wird zum Anker.
  if mSelection.IsEmpty and AExpand then
  begin
    FAnchorFile := mFileName;
    FAnchor := mSelection.StartPos;
  end;
  mPosition := TAtlasSelectionSteps.ChainPosition(mSelection, SameText(FAnchorFile, mFileName), FAnchor);
  try
    mChain := Session.SelectionRanges(mFileName, mPosition.Line, mPosition.Character);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if AExpand then
  begin
    mMoved := TAtlasSelectionSteps.Expand(mChain, mSelection, mNext);
  end
  else
  begin
    mMoved := TAtlasSelectionSteps.Shrink(mChain, mSelection, mNext);
  end;
  if mMoved then
  begin
    Select(mView, mLines, mNext);
  end;
end;

class procedure TAtlasEditorSelectionCommands.ExpandSelection;
begin
  Step(True);
end;

class procedure TAtlasEditorSelectionCommands.ShrinkSelection;
begin
  Step(False);
end;

class procedure TAtlasEditorSelectionCommands.GoToTypeDefinition;
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
  mFound: TArray<TLspLocation>;
begin
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  try
    mFound := Session.TypeDefinition(mFileName, mSelection.StartPos.Line, mSelection.StartPos.Character);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(mFound) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  // Ein Typ hat eine Deklaration; bei mehreren (Forward-Deklaration) die erste.
  TAtlasIdeNavigation.GoToLocation(mFound[0].FileName, mFound[0].Line, mFound[0].Character);
end;

class procedure TAtlasEditorSelectionCommands.SafeDelete;
var
  mView: IOTAEditView;
  mFileName: string;
  mLines: TArray<string>;
  mSelection: TLspRange;
begin
  if not Current(mView, mFileName, mLines, mSelection) then
  begin
    Exit;
  end;
  TAtlasIdeSafeDelete.Execute(Session, TAtlasSafeDelete.Arguments(TLspSession.PathToUri(mFileName),
    mSelection.StartPos.Line, mSelection.StartPos.Character),
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    procedure(AText: string)
    begin
      Say(AText);
    end);
end;

class function TAtlasEditorSelectionCommands.TryToggleMethod: Boolean;
var
  mCaret: TAtlasEditorCaret;
  mTarget: TAtlasMethodPlace;
begin
  Result := Caret(mCaret) and TAtlasMethodToggle.Counterpart(mCaret.Text, mCaret.Row, mCaret.Character, mTarget,
    ProjectDefines);
  if Result then
  begin
    MoveCaret(mCaret, TLspTextPosition.Create(mTarget.Line, mTarget.Character));
  end;
end;

class procedure TAtlasEditorSelectionCommands.ToggleMethod;
begin
  if not TryToggleMethod then
  begin
    Say(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.EditorMethodToggleNone));
  end;
end;

class procedure TAtlasEditorSelectionCommands.JumpToMatch(ASelect: Boolean);
var
  mCaret: TAtlasEditorCaret;
  mTarget, mStart, mStop: TAtlasMatchSpot;
begin
  if not TAtlasIdeSettings.Current.JumpToMatch or not Caret(mCaret) then
  begin
    Exit;
  end;
  if ASelect then
  begin
    if TAtlasJumpToMatch.Selection(mCaret.Text, mCaret.Row, mCaret.Character, mStart, mStop) then
    begin
      Select(mCaret.View, mCaret.Lines, TLspRange.Create(mStart.Line, mStart.Character, mStop.Line, mStop.Character));
    end;
  end
  else if TAtlasJumpToMatch.Target(mCaret.Text, mCaret.Row, mCaret.Character, mTarget) then
  begin
    MoveCaret(mCaret, TLspTextPosition.Create(mTarget.Line, mTarget.Character));
  end;
end;

class procedure TAtlasEditorSelectionCommands.StepProblem(AForward: Boolean);
var
  mCaret: TAtlasEditorCaret;
  mProblems: TArray<TAtlasProblem>;
  mTarget: TAtlasProblem;
begin
  if not Caret(mCaret) then
  begin
    Exit;
  end;
  if Assigned(FStepList) and FStepList(AForward) then
  begin
    Exit;
  end;
  mProblems := nil;
  if Assigned(FProblemsOf) and TAtlasIdeSettings.ProblemMarksOn then
  begin
    mProblems := FProblemsOf(mCaret.View.Buffer.FileName);
  end;
  if not TAtlasInlineDiagnostics.Next(mProblems, mCaret.Row, mCaret.Character, AForward, mTarget) then
  begin
    Say(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.ProblemNoneInFile));
    Exit;
  end;
  MoveCaret(mCaret, TLspTextPosition.Create(mTarget.StartLine, mTarget.StartCharacter));
end;

class function TAtlasEditorSelectionCommands.SelectedNeedle(const AView: IOTAEditView; out ANeedle: string): Boolean;
var
  mBlock: IOTAEditBlock;
begin
  ANeedle := '';
  mBlock := AView.Block;
  Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) and (mBlock.StartingRow = mBlock.EndingRow);
  if Result then
  begin
    ANeedle := mBlock.Text;
    Result := (ANeedle <> '') and (Pos(#10, ANeedle) = 0) and (Pos(#13, ANeedle) = 0);
  end;
end;

class function TAtlasEditorSelectionCommands.TryFindSelection(ABackward: Boolean): Boolean;
var
  mCaret: TAtlasEditorCaret;
  mBlock: IOTAEditBlock;
  mSearch: TNeedleSearch;
  mTerm, mLineText: string;
  mRow, mColumn: Integer;
  mFound: TLspRange;
  mNavigateF3: Boolean;
begin
  Result := False;
  mSearch := Default(TNeedleSearch);
  if not Caret(mCaret) or not SelectedNeedle(mCaret.View, mSearch.Needle) then
  begin
    Exit;
  end;
  // Gleichen Text hervorheben (#709): F3 springt zwischen dessen Treffern, mit denselben Optionen.
  mSearch.Matching := TAtlasIdeSettings.SelectionMatchesOn(mSearch.Options, mNavigateF3) and
    TAtlasSelectionMatches.Term(mSearch.Needle, mSearch.Options, mTerm);
  mBlock := mCaret.View.Block;
  mRow := mBlock.StartingRow - 1;
  if (mSearch.Matching and not mNavigateF3) or (mRow < 0) or (mRow >= Length(mCaret.Lines)) then
  begin
    Exit;
  end;
  mLineText := mCaret.Lines[mRow];
  mColumn := mBlock.EndingColumn;
  if ABackward then
  begin
    mColumn := mBlock.StartingColumn;
  end;
  if FindNeedle(mCaret.Lines, mSearch, TLspTextPosition.Create(mRow, TLspSession.ColumnToIndex(mLineText, mColumn,
    mCaret.TabWidth)), ABackward, mFound) then
  begin
    TakeSearchText(mCaret.View, mSearch.Needle);
    Select(mCaret.View, mCaret.Lines, mFound);
    Result := True;
  end;
end;

end.
