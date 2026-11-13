unit Shell.Composition.MethodBreakpoints;

// Internals-Rolle Shell: Befehl des Debuggers für Haltepunkte auf Methoden nach Name oder Muster (#855). Liest nur
// Index und Dateien; Code-Aktionen gibt es hier keine.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.MethodBreakpoints,
  Shell.Composition.Refactorings.Services;

type
  TShellMethodBreakpoints = class(TShellRefactoringPart)
  private
    function MethodBreakpoints(const AArguments: TJSONArray): TJSONValue;
    function BodiesOf(const AFileName: string): TArray<TMethodBody>;
  public
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Shell.Texts;

procedure TShellMethodBreakpoints.Register(ACommands: TLspCommands);
begin
  ACommands.Register(TLspMethodBreakpoints.cCommand, MethodBreakpoints);
end;

function TShellMethodBreakpoints.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := nil;
end;

function TShellMethodBreakpoints.BodiesOf(const AFileName: string): TArray<TMethodBody>;
var
  mDocument: ITextDocument;
  mText: string;
  mTree: TSyntaxTree;
begin
  // Offenes Dokument vor der Platte: Ungespeicherte Änderungen verschieben die Zeilen.
  if Documents.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    mText := mDocument.Text;
  end
  else if not ReadText(AFileName, mText) then
  begin
    Result := nil;
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TLspMethodBreakpoints.Bodies(mTree);
  finally
    mTree.Free;
  end;
end;

function TShellMethodBreakpoints.MethodBreakpoints(const AArguments: TJSONArray): TJSONValue;
var
  mText: string;
  mOptions: TMethodBreakpointOptions;
  mPattern: TMethodPattern;
  mHits: TArray<TMethodBreakpointHit>;
  mTruncated: Boolean;
begin
  // Argument: {"pattern": …, "overrides": …, "overloads": …} aus dem Fenster bzw. beim Mitwachsen vor dem Start.
  if not TLspMethodBreakpoints.ReadRequest(AArguments, mText, mOptions) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, TShellTexts.Missing(['pattern']));
  end;
  if not TMethodPattern.Parse(mText, Index, mPattern) then
  begin
    Exit(TLspMethodBreakpoints.ErrorToJson(TLspMethodBreakpoints.InvalidPattern(mText)));
  end;
  mHits := TLspMethodBreakpoints.Search(Index, mPattern, mOptions, BodiesOf, mTruncated);
  Log(Format('Method breakpoints: %d hits', [Length(mHits)]));
  Result := TLspMethodBreakpoints.ToJson(mPattern.Text, mHits, mTruncated);
end;

end.
