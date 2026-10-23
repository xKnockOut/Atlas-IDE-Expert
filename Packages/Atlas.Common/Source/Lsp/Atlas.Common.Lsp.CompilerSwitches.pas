unit Atlas.Common.Lsp.CompilerSwitches;

// Wirksame Compiler-Schalter an der Cursorposition (#558), Anfrage
// atlas/compilerSwitches mit textDocument und position. Der Präprozessor (#15)
// läuft mit den Symbolen und Schalterständen des Projekts und den
// Include-Dateien über die ganze Datei; TCompilerSwitches spielt die
// Direktiven bis zur Position nach. Antwort:
//   { configuration, platform, hasProject, summary,
//     switches: [{ name, longName, value, projectValue, deviates, origin }],
//     hints, warnings: { … wie oben },
//     warns: [{ name, value, projectValue, deviates, origin }],
//     defines: [{ name, origin }] }
// origin: { kind: "default" | "project" | "directive" | "include", text,
// file, line } (file und line nur bei Direktiven).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.CompilerSwitches;

type
  /// <summary>Was zum Projekt einer Datei bekannt ist; liefert die Composition.</summary>
  TCompilerSwitchContext = record
    FileName: string;
    ResolveInclude: TIncludeResolver;
    HasProject: Boolean;
    Configuration: string;
    Platform: string;
    Input: TCompilerSwitchInput;
  end;

  TCompilerSwitchContextFunc = reference to function(const AUri: string): TCompilerSwitchContext;

  TLspCompilerSwitches = class
  public const
    Method = 'atlas/compilerSwitches';
  private
    FStore: IDocumentStore;
    FContextFor: TCompilerSwitchContextFunc;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  public
    constructor Create(const AStore: IDocumentStore; const AContextFor: TCompilerSwitchContextFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Stand an APosition von AText.</summary>
    class function StateAt(const AText: string; const APosition: TTextPosition;
      const AContext: TCompilerSwitchContext): TCompilerSwitchState; static;
    /// <summary>Antwort wie im Kopf beschrieben; gehört dem Aufrufer.</summary>
    class function ToJson(const AState: TCompilerSwitchState; const AContext: TCompilerSwitchContext): TJSONObject;
      static;
  end;

implementation

uses
  Atlas.Common.Lsp.Positions;

const
  OriginKinds: array[TSwitchOriginKind] of string = ('default', 'project', 'directive', 'include');

function OriginJson(const AOrigin: TSwitchOrigin): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', OriginKinds[AOrigin.Kind]);
  Result.AddPair('text', AOrigin.Text);
  if AOrigin.FileName <> '' then
  begin
    Result.AddPair('file', AOrigin.FileName);
    Result.AddPair('line', TJSONNumber.Create(AOrigin.Line));
  end;
end;

function EntryJson(const AEntry: TSwitchEntry; AWithValue: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AEntry.Name);
  if AWithValue then
  begin
    if AEntry.LongName <> '' then
      Result.AddPair('longName', AEntry.LongName);
    Result.AddPair('value', AEntry.Value);
    Result.AddPair('projectValue', AEntry.ProjectValue);
    Result.AddPair('deviates', TJSONBool.Create(AEntry.Deviates));
  end;
  Result.AddPair('origin', OriginJson(AEntry.Origin));
end;

function EntriesJson(const AEntries: TSwitchEntries; AWithValue: Boolean): TJSONArray;
var
  Entry: TSwitchEntry;
begin
  Result := TJSONArray.Create;
  for Entry in AEntries do
    Result.AddElement(EntryJson(Entry, AWithValue));
end;

{ TLspCompilerSwitches }

constructor TLspCompilerSwitches.Create(const AStore: IDocumentStore; const AContextFor: TCompilerSwitchContextFunc);
begin
  inherited Create;
  FStore := AStore;
  FContextFor := AContextFor;
end;

procedure TLspCompilerSwitches.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, Handle);
end;

class function TLspCompilerSwitches.StateAt(const AText: string; const APosition: TTextPosition;
  const AContext: TCompilerSwitchContext): TCompilerSwitchState;
var
  Options: TPreprocessorOptions;
begin
  Options := TPreprocessorOptions.Default;
  Options.Defines := AContext.Input.Defines;
  Options.FileName := AContext.FileName;
  Options.ResolveInclude := AContext.ResolveInclude;
  Result := TCompilerSwitches.At(TPascalPreprocessor.Process(AText, Options), APosition, AContext.Input);
end;

class function TLspCompilerSwitches.ToJson(const AState: TCompilerSwitchState;
  const AContext: TCompilerSwitchContext): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('configuration', AContext.Configuration);
  Result.AddPair('platform', AContext.Platform);
  Result.AddPair('hasProject', TJSONBool.Create(AContext.HasProject));
  Result.AddPair('summary', AState.Summary);
  Result.AddPair('switches', EntriesJson(AState.Switches, True));
  Result.AddPair('hints', EntryJson(AState.Hints, True));
  Result.AddPair('warnings', EntryJson(AState.Warnings, True));
  Result.AddPair('warns', EntriesJson(AState.Warns, True));
  Result.AddPair('defines', EntriesJson(AState.Defines, False));
end;

function TLspCompilerSwitches.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Context: TCompilerSwitchContext;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Context := Default(TCompilerSwitchContext);
  if Assigned(FContextFor) then
    Context := FContextFor(Uri);
  ACancellation.ThrowIfCancellationRequested;
  Result := ToJson(StateAt(Document.Text, TLspPositions.ReadPosition(PositionValue), Context), Context);
end;

end.
