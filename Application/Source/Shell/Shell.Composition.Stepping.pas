unit Shell.Composition.Stepping;

// Internals-Rolle Shell: Befehle für den Debugger des Plugins: gezielt hineinspringen (#836) und Schrittfilter
// (#850). Sie lesen nur; Code-Aktionen gibt es hier keine.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services;

type
  TShellStepping = class(TShellRefactoringPart)
  private
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function StepTargets(const AArguments: TJSONArray): TJSONValue;
    function StepFilter(const AArguments: TJSONArray): TJSONValue;
    function StepFilterOfFile(const AUri: string; ALine: Integer): TJSONObject;
    function StepFilterCounts(const AArguments: TJSONArray): TJSONValue;
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.StepTargets,
  Atlas.Common.Lsp.StepFilter,
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
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, TShellTexts.Missing(['uri', 'line']));
  end;
  Result := TJSONNumber(AArguments.Items[1]).AsInt;
end;

procedure TShellStepping.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspStepTargets.Command, StepTargets);
  ACommands.Register(TLspStepFilter.Command, StepFilter);
  ACommands.Register(TLspStepFilter.CountsCommand, StepFilterCounts);
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
    raise EJsonRpcError.Create(TLspErrorCode.RequestFailed, cTexts[TSteppingText.Unreadable].Text);
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
    if mCounts.Files >= TLspStepFilter.MaxFiles then
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

initialization
  TAtlasTextTables.Add('Shell.Composition.Stepping', cTexts);

end.
