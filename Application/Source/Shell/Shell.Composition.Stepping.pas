unit Shell.Composition.Stepping;

// Internals-Rolle Shell: Befehle für den Debugger des Plugins: gezielt hineinspringen (#836), Schrittfilter
// (#850), „Warum bin ich hier?“ (#1878), Variablen beim Halt (#853), kommende Bedingungen (#2169), Haltepunkte,
// die nicht greifen werden (#577), und die Parameter einer Routine für das Fenster „Aufrufstapel“ (#843). Sie
// lesen nur; Code-Aktionen gibt es hier keine.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.EnclosingConditions,
  Shell.Composition.Refactorings.Services;

type
  /// <summary>Baut die Antwort eines Bedingungsbefehls aus Baum, Text, Aufrufstellen, Zeile und drittem Argument.
  /// </summary>
  TShellConditionBuild = reference to function(ATree: TSyntaxTree; const AText: string;
    const ACallsAt: TLspCallsAt; ALine, AExtra: Integer): TJSONObject;

  TShellStepping = class(TShellRefactoringPart)
  private
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function StepTargets(const AArguments: TJSONArray): TJSONValue;
    function StepFilter(const AArguments: TJSONArray): TJSONValue;
    function StepFilterOfFile(const AUri: string; ALine: Integer): TJSONObject;
    function StepFilterCounts(const AArguments: TJSONArray): TJSONValue;
    function ConditionAnswer(const AArguments: TJSONArray; const ABuild: TShellConditionBuild): TJSONObject;
    function EnclosingConditions(const AArguments: TJSONArray): TJSONValue;
    function DebugVariables(const AArguments: TJSONArray): TJSONValue;
    function RoutineParameters(const AArguments: TJSONArray): TJSONValue;
    function UpcomingConditions(const AArguments: TJSONArray): TJSONValue;
    function BreakpointCheck(const AArguments: TJSONArray): TJSONValue;
    function BreakpointCheckFile(const AUri: string; const ALines: TArray<Integer>): TJSONObject;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.StepTargets,
  Atlas.Common.Lsp.StepFilter,
  Atlas.Common.Lsp.DebugVariables,
  Atlas.Common.Lsp.RoutineParameters,
  Atlas.Common.Lsp.UpcomingConditions,
  Atlas.Common.Lsp.BreakpointCheck,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Localization.Texts,
  Shell.Texts;

type
{$SCOPEDENUMS ON}
  TSteppingText = (Unreadable);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TSteppingText] of TAtlasText = (
    (De: 'Die Datei ist nicht lesbar.'; En: 'The file is not readable.'));

/// <summary>Argumente URI und Zeile (ab 0); sonst EJsonRpcError.</summary>
function LineOf(const AArguments: TJSONArray): Integer;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, TShellTexts.Missing(['uri', 'line']));
  end;
  Result := TJSONNumber(AArguments.Items[1]).AsInt;
end;

procedure TShellStepping.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspStepTargets.cCommand, StepTargets);
  ACommands.Register(TLspStepFilter.cCommand, StepFilter);
  ACommands.Register(TLspStepFilter.cCountsCommand, StepFilterCounts);
  ACommands.Register(TLspEnclosingConditions.cCommand, EnclosingConditions);
  ACommands.Register(TLspDebugVariables.cCommand, DebugVariables);
  ACommands.Register(TLspRoutineParameters.cCommand, RoutineParameters);
  ACommands.Register(TLspUpcomingConditions.cCommand, UpcomingConditions);
  ACommands.Register(TLspBreakpointCheck.cCommand, BreakpointCheck);
end;

function TShellStepping.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := nil;
end;

function TShellStepping.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := ReadText(AFileName, AText);
end;

function TShellStepping.StepTargets(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mResolver: TNameResolver;
  mTargets: TLspStepTargets;
  mAnswer: TJSONObject;
begin
  // Argumente: URI und Zeile (ab 0) des Ausführungspunkts (#836).
  mLine := LineOf(AArguments);
  mUri := AArguments.Items[0].Value;
  mDocument := Open(mUri);
  mResolver := NewResolver;
  try
    mTargets := TLspStepTargets.Create(mResolver, Index, TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text,
      TDocumentUris.ToPath(mUri), ReadFile);
    try
      mAnswer := mTargets.Execute(mLine);
    finally
      mTargets.Free;
    end;
  finally
    mResolver.Free;
  end;
  Log(Format('Gezielt hineinspringen: %d Aufrufe', [Count(mAnswer, 'calls')]));
  Result := mAnswer;
end;

function TShellStepping.StepFilter(const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mAnswer: TJSONObject;
begin
  // Argumente: URI und Zeile (ab 0) des Halts nach F7 bzw. des Methodenkopfs im Kontextmenü (#850).
  mLine := LineOf(AArguments);
  mUri := AArguments.Items[0].Value;
  if Documents.TryGet(mUri, mDocument) then
  begin
    mAnswer := TLspStepFilter.Execute(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text, mLine);
  end
  else
  begin
    mAnswer := StepFilterOfFile(mUri, mLine);
  end;
  Log(Format('Schrittfilter: Routine %s', [BoolToStr(mAnswer.GetValue<Boolean>('found', False), True)]));
  Result := mAnswer;
end;

function TShellStepping.StepFilterOfFile(const AUri: string; ALine: Integer): TJSONObject;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  // Nach F7 steht der Halt oft in einer Datei, die der Editor erst jetzt öffnet: selbst lesen.
  if not ReadText(TDocumentUris.ToPath(AUri), mText) then
  begin
    raise EJsonRpcError.Create(TLspErrorCode.cRequestFailed, cTexts[TSteppingText.Unreadable].Text);
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TLspStepFilter.Execute(mTree, mText, ALine);
  finally
    mTree.Free;
  end;
end;

function TShellStepping.StepFilterCounts(const AArguments: TJSONArray): TJSONValue;
var
  mPatterns: TArray<string>;
  mCounts: TLspStepFilterCounts;
  mUnit: TUnitIndex;
  mText: string;
  mTree: TSyntaxTree;
begin
  // Argument: Liste der Muster (#850). Gezählt werden die Projekt-Units, Bibliotheken nicht.
  mPatterns := TLspStepFilter.ReadPatterns(AArguments);
  mCounts := TLspStepFilter.NewCounts(mPatterns);
  for mUnit in Index.Units do
  begin
    if mUnit.Library_ or (mUnit.FileName = '') then
    begin
      Continue;
    end;
    if mCounts.Files >= TLspStepFilter.cMaxFiles then
    begin
      mCounts.Truncated := True;
      Break;
    end;
    if not ReadText(mUnit.FileName, mText) then
    begin
      Continue;
    end;
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      TLspStepFilter.AddCounts(mTree, mText, mPatterns, mCounts);
    finally
      mTree.Free;
    end;
  end;
  Log(Format('Schrittfilter: %d Dateien, %d Routinen', [mCounts.Files, mCounts.Routines]));
  Result := TLspStepFilter.CountsToJson(mCounts);
end;

function TShellStepping.ConditionAnswer(const AArguments: TJSONArray;
  const ABuild: TShellConditionBuild): TJSONObject;
var
  mUri: string;
  mLine, mExtra: Integer;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mTargets: TLspStepTargets;
begin
  // Argumente: URI, Zeile (ab 0) des Halts und eine Zahl (Tiefe bzw. Zeilen voraus).
  mLine := LineOf(AArguments);
  mUri := AArguments.Items[0].Value;
  mExtra := 0;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
  begin
    mExtra := TJSONNumber(AArguments.Items[2]).AsInt;
  end;
  mDocument := Open(mUri);
  mTree := TSyntaxTreeCache.Get(mDocument, nil).Tree;
  mResolver := NewResolver;
  try
    // Getter und Aufrufe ohne Klammern erkennt die Namensauflösung von „Gezielt hineinspringen“.
    mTargets := TLspStepTargets.Create(mResolver, Index, mTree, mDocument.Text, TDocumentUris.ToPath(mUri), ReadFile);
    try
      Result := ABuild(mTree, mDocument.Text,
        function(ALine: Integer): TArray<TTextPosition>
        begin
          Result := mTargets.CallPositions(ALine);
        end, mLine, mExtra);
    finally
      mTargets.Free;
    end;
  finally
    mResolver.Free;
  end;
end;

function BuildEnclosing(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt;
  ALine, AExtra: Integer): TJSONObject;
var
  mConditions: TLspEnclosingConditions;
begin
  mConditions := TLspEnclosingConditions.Create(ATree, AText, ACallsAt);
  try
    Result := mConditions.Execute(ALine, AExtra);
  finally
    mConditions.Free;
  end;
end;

function BuildUpcoming(ATree: TSyntaxTree; const AText: string; const ACallsAt: TLspCallsAt;
  ALine, AExtra: Integer): TJSONObject;
var
  mConditions: TLspUpcomingConditions;
begin
  mConditions := TLspUpcomingConditions.Create(ATree, AText, ACallsAt);
  try
    Result := mConditions.Execute(ALine, AExtra);
  finally
    mConditions.Free;
  end;
end;

function TShellStepping.EnclosingConditions(const AArguments: TJSONArray): TJSONValue;
var
  mAnswer: TJSONObject;
begin
  // „Warum bin ich hier?“ (#1878): drittes Argument ist die Tiefe.
  mAnswer := ConditionAnswer(AArguments, BuildEnclosing);
  Log(Format(TLspEnclosingConditions.cCommand + ': %d', [Count(mAnswer, 'blocks')]));
  Result := mAnswer;
end;

function IsValueSymbol(const ASymbol: TResolvedSymbol): Boolean;
begin
  // Unbekannt (Unit nicht im Index): lieber auswerten; der Debugger meldet dann selbst.
  case ASymbol.Kind of
    TResolvedKind.None:
      Result := True;
    TResolvedKind.Local, TResolvedKind.Symbol:
      Result := ASymbol.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field,
        TIndexSymbolKind.Property_];
  else
    Result := False;
  end;
end;

function TShellStepping.DebugVariables(const AArguments: TJSONArray): TJSONValue;
var
  mUri, mPath: string;
  mLine, mPrevious: Integer;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mTargets: TLspStepTargets;
  mVariables: TLspDebugVariables;
  mAnswer: TJSONObject;
begin
  // Argumente: URI, Zeile (ab 0) des Halts und Zeile des vorigen Halts (-1 ohne) (#853).
  mLine := LineOf(AArguments);
  mUri := AArguments.Items[0].Value;
  mPrevious := -1;
  if (AArguments.Count > 2) and (AArguments.Items[2] is TJSONNumber) then
  begin
    mPrevious := TJSONNumber(AArguments.Items[2]).AsInt;
  end;
  mDocument := Open(mUri);
  mTree := TSyntaxTreeCache.Get(mDocument, nil).Tree;
  mPath := TDocumentUris.ToPath(mUri);
  mResolver := NewResolver;
  try
    // Getter und Aufrufe ohne Klammern erkennt die Namensauflösung von „Gezielt hineinspringen“.
    mTargets := TLspStepTargets.Create(mResolver, Index, mTree, mDocument.Text, mPath, ReadFile);
    try
      mVariables := TLspDebugVariables.Create(mTree, mDocument.Text,
        function(ALine: Integer): TArray<TTextPosition>
        begin
          Result := mTargets.CallPositions(ALine);
        end,
        function(const APosition: TTextPosition): Boolean
        begin
          Result := IsValueSymbol(mResolver.Resolve(mTree, mPath, APosition));
        end);
      try
        mAnswer := mVariables.Execute(mLine, mPrevious);
      finally
        mVariables.Free;
      end;
    finally
      mTargets.Free;
    end;
  finally
    mResolver.Free;
  end;
  Log(Format(TLspDebugVariables.cCommand + ': %d autos, %d locals', [Count(mAnswer, 'autos'),
    Count(mAnswer, 'locals')]));
  Result := mAnswer;
end;

function TShellStepping.RoutineParameters(const AArguments: TJSONArray): TJSONValue;
var
  mLine: Integer;
  mDocument: ITextDocument;
  mParameters: TLspRoutineParameters;
  mAnswer: TJSONObject;
begin
  // Argumente: URI und Zeile (ab 0) eines Rahmens im Aufrufstapel (#843).
  mLine := LineOf(AArguments);
  mDocument := Open(AArguments.Items[0].Value);
  mParameters := TLspRoutineParameters.Create(TSyntaxTreeCache.Get(mDocument, nil).Tree, mDocument.Text);
  try
    mAnswer := mParameters.Execute(mLine);
  finally
    mParameters.Free;
  end;
  Log(Format(TLspRoutineParameters.cCommand + ': %d', [Count(mAnswer, 'parameters')]));
  Result := mAnswer;
end;

function TShellStepping.UpcomingConditions(const AArguments: TJSONArray): TJSONValue;
var
  mAnswer: TJSONObject;
begin
  // Bedingungen vorausschauen (#2169): drittes Argument ist die Zahl der Zeilen voraus.
  mAnswer := ConditionAnswer(AArguments, BuildUpcoming);
  Log(Format(TLspUpcomingConditions.cCommand + ': %d', [Count(mAnswer, 'blocks')]));
  Result := mAnswer;
end;

function TShellStepping.BreakpointCheck(const AArguments: TJSONArray): TJSONValue;
var
  mFiles: TArray<TLspBreakpointFile>;
  mFile: TLspBreakpointFile;
  mEntries: TArray<TJSONObject>;
  mEntry: TJSONObject;
begin
  // Argument: Dateien mit den Zeilen ihrer aktiven Haltepunkte (#577), vor dem Start einer Debug-Sitzung.
  mFiles := TLspBreakpointCheck.ReadFiles(AArguments);
  mEntries := nil;
  try
    for mFile in mFiles do
    begin
      mEntries := mEntries + [BreakpointCheckFile(mFile.Uri, mFile.Lines)];
    end;
  except
    // Schon gebaute Einträge gehören noch niemandem.
    for mEntry in mEntries do
    begin
      mEntry.Free;
    end;
    raise;
  end;
  Log(Format('Breakpoint check: %d files', [Length(mFiles)]));
  Result := TLspBreakpointCheck.AnswerToJson(mEntries);
end;

function TShellStepping.BreakpointCheckFile(const AUri: string; const ALines: TArray<Integer>): TJSONObject;
var
  mPath, mText: string;
  mDocument: ITextDocument;
  mProject: TProjectInfo;
  mInput: TCompilerSwitchInput;
  mOptions: TPreprocessorOptions;
  mTreeRun, mProcessed: TPreprocessorResult;
  mTree: TSyntaxTree;
begin
  mPath := TDocumentUris.ToPath(AUri);
  if Documents.TryGet(AUri, mDocument) then
  begin
    mText := mDocument.Text;
  end
  else if not ReadText(mPath, mText) then
  begin
    Exit(TLspBreakpointCheck.UnreadableToJson(AUri));
  end;
  // Symbole und Schalter des Projekts der Datei; ohne Projekt die Vorgaben des Compilers.
  mInput := Default(TCompilerSwitchInput);
  if Project(mPath, mProject) then
  begin
    mInput.Defines := mProject.Defines;
    mInput.Properties := mProject.Properties;
  end;
  mOptions := TPascalPreprocessor.EditorOptions(mInput.Defines);
  mOptions.FileName := mPath;
  mTree := TSyntaxTreeCache.ParseActive(mText, mOptions, nil, mTreeRun);
  try
    // Voller Lauf auch ohne Bedingungen: daraus kommen die lokalen Schalter ($D-).
    mProcessed := TPascalPreprocessor.Process(mText, mOptions);
    Result := TLspBreakpointCheck.FileToJson(AUri, TLspBreakpointCheck.Check(mTree, mProcessed, mInput, ALines));
  finally
    mTree.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Composition.Stepping', cTexts);

end.
