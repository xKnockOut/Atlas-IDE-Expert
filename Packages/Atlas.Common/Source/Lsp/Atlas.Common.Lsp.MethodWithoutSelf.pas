unit Atlas.Common.Lsp.MethodWithoutSelf;

// „Methode ohne Self umwandeln“ über das Protokoll (#686):
//   - Code-Aktionen auf dem Kopf einer Methode ohne Self, nur mit
//     refactoring.methodKind: „In class-Methode umwandeln“, „…, Aufrufe über
//     TKlasse“, „In freie Routine umwandeln“, „In Record-Helper für T
//     verschieben“. Jede trägt den Client-Befehl atlas.methodKind mit [uri,
//     position, Umwandlung]; das Plugin holt das Ergebnis und zeigt die
//     Vorschau.
//   - Befehl atlas.server.methodKind [uri, position, Umwandlung]:
//     {"edit": WorkspaceEdit über alle Dateien, "warnings": [...], "places": n,
//     "files": n, "calls": n, "preview": Text}; geht es nicht, ein Fehler mit
//     Grund. Die Verwendungen kommen aus der Referenzsuche im Projekt.
//   - Marken: Inlay-Hinweis „ohne Self“ am Ende des Kopfs (MarkerHints).
// Namensauflösung: Mitglieder, Interfaces, sichtbare Helper über
// TMethodLookup.FromResolver, die Formulardatei wie bei #668.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.MethodWithoutSelf,
  Atlas.Common.Editing.MethodWithoutSelf.Lookup,
  Atlas.Common.Lsp.References;

type
  TMethodKindContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>refactoring.methodKindStatic.</summary>
    WithStatic: Boolean;
    /// <summary>Umwandlung (TMethodWithoutSelf.ConversionName).</summary>
    Conversion: string;
    Style: TFormatStyle;
  end;

  TLspMethodWithoutSelf = class
  public const
    ClientCommand = 'atlas.methodKind';
    ApplyCommand = 'atlas.server.methodKind';
    Kind = 'refactor.rewrite';
    AnnotationId = 'methodKind';
  public
    /// <summary>Mitglieder, Interfaces, Helper und Formular über AResolver für ATree der Datei AFileName.</summary>
    class function Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const AReadText: TReferenceReadText): TMethodLookup; static;
    /// <summary>Die Code-Aktionen an APosition. Der Aufrufer übernimmt die Objekte.</summary>
    class function Actions(ATree: TSyntaxTree; const AText, AUri: string; const APosition: TTextPosition;
      const ALookup: TMethodLookup): TArray<TJSONObject>; static;
    /// <summary>Antwort auf atlas.server.methodKind; EJsonRpcError mit dem Grund, wenn es nicht geht. Der Aufrufer
    /// übernimmt das Objekt.</summary>
    class function Execute(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; const AContext: TMethodKindContext): TJSONObject; static;
    /// <summary>Stellen der Marken in ARange: Ende des Kopfs je Methode ohne Self.</summary>
    class function Markers(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
      const ALookup: TMethodLookup): TArray<TTextPosition>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.FormMentions,
  Atlas.Text.Lines;

class function TLspMethodWithoutSelf.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AReadText: TReferenceReadText): TMethodLookup;
begin
  Result := TMethodLookup.FromResolver(AResolver, ATree, AFileName);
  Result.InForm := TLspFormMentions.Lookup(AFileName, AReadText);
end;

class function TLspMethodWithoutSelf.Actions(ATree: TSyntaxTree; const AText, AUri: string;
  const APosition: TTextPosition; const ALookup: TMethodLookup): TArray<TJSONObject>;
var
  Target: TMethodTarget;
  Reason, Title: string;
  Conversion: TMethodConversion;
  Arguments: TJSONArray;
  Command, Action: TJSONObject;
begin
  Result := nil;
  if not TMethodWithoutSelf.Target(AText, ATree, APosition, ALookup, Target, Reason) then
  begin
    Exit;
  end;
  for Conversion in Target.Conversions do
  begin
    Title := Target.Title(Conversion);
    Arguments := TJSONArray.Create;
    Arguments.Add(AUri);
    Arguments.AddElement(TLspPositions.PositionToJson(APosition));
    Arguments.Add(TMethodWithoutSelf.ConversionName(Conversion));
    Command := TJSONObject.Create;
    Command.AddPair('title', Title);
    Command.AddPair('command', ClientCommand);
    Command.AddPair('arguments', Arguments);
    Action := TJSONObject.Create;
    Action.AddPair('title', Title);
    Action.AddPair('kind', Kind);
    Action.AddPair('command', Command);
    Result := Result + [Action];
  end;
end;

function Fail(const AMessage: string): EJsonRpcError;
begin
  Result := EJsonRpcError.Create(TLspErrorCode.RequestFailed, AMessage);
end;

function EditsJson(const AUri: string; const AEdits: TArray<TTextEdit>): TJSONObject;
var
  Document, Item: TJSONObject;
  Items: TJSONArray;
  Edit: TTextEdit;
begin
  Document := TJSONObject.Create;
  Document.AddPair('uri', AUri);
  Document.AddPair('version', TJSONNull.Create);
  Items := TJSONArray.Create;
  for Edit in AEdits do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Edit.Range));
    Item.AddPair('newText', Edit.NewText);
    Item.AddPair('annotationId', TLspMethodWithoutSelf.AnnotationId);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', Document);
  Result.AddPair('edits', Items);
end;

type
  /// <summary>Gelesene Datei mit Verwendungen; gibt den Baum frei.</summary>
  TUseFile = class
  public
    Source: TMethodSource;
    Lines: TLineTable;
    OwnsTree: Boolean;
    destructor Destroy; override;
  end;

  /// <summary>Eine Umwandlung: Ziel, Verwendungen in allen Dateien und Ergebnis.</summary>
  TMethodKindRun = class
  private
    FResolver: TNameResolver;
    FTree: TSyntaxTree;
    FFileName: string;
    FText: string;
    FContext: TMethodKindContext;
    FLookup: TMethodLookup;
    FTarget: TMethodTarget;
    FDeclaring: TMethodSource;
    FLines: TLineTable;
    FFiles: TObjectList<TUseFile>;
    function UseFileOf(const AFileName: string; out AUseFile: TUseFile): Boolean;
    procedure AddUse(const ALocation: TReferenceLocation);
  public
    constructor Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const AContext: TMethodKindContext);
    destructor Destroy; override;
    /// <summary>Methode an APosition; EJsonRpcError, wenn sie sich nicht umwandeln lässt.</summary>
    procedure FindTarget(const APosition: TTextPosition);
    /// <summary>Verwendungen aus der Referenzsuche, nach Dateien.</summary>
    procedure CollectUses;
    function Convert(const APosition: TTextPosition; AConversion: TMethodConversion): TMethodResult;
    property Target: TMethodTarget read FTarget;
  end;

destructor TUseFile.Destroy;
begin
  if OwnsTree then
  begin
    Source.Tree.Free;
  end;
  inherited;
end;

{ TMethodKindRun }

constructor TMethodKindRun.Create(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
  const AContext: TMethodKindContext);
begin
  inherited Create;
  FResolver := AResolver;
  FTree := ATree;
  FFileName := AFileName;
  FText := AText;
  FContext := AContext;
  FFiles := TObjectList<TUseFile>.Create(True);
end;

destructor TMethodKindRun.Destroy;
begin
  FFiles.Free;
  inherited;
end;

procedure TMethodKindRun.FindTarget(const APosition: TTextPosition);
var
  mReason: string;
  mFound: Boolean;
begin
  FResolver.PinTree(FTree, FFileName);
  try
    FLookup := TLspMethodWithoutSelf.Lookup(FResolver, FTree, FFileName, FContext.ReadText);
    mFound := TMethodWithoutSelf.Target(FText, FTree, APosition, FLookup, FTarget, mReason);
  finally
    FResolver.UnpinTree;
  end;
  if not mFound then
  begin
    raise Fail('Umwandeln geht nicht: ' + mReason);
  end;
end;

function TMethodKindRun.UseFileOf(const AFileName: string; out AUseFile: TUseFile): Boolean;
var
  mUseFile: TUseFile;
begin
  for mUseFile in FFiles do
  begin
    if SameText(mUseFile.Source.FileName, AFileName) then
    begin
      AUseFile := mUseFile;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TMethodKindRun.AddUse(const ALocation: TReferenceLocation);
var
  mUseFile: TUseFile;
  mText: string;
begin
  if MatchText(ExtractFileExt(ALocation.FileName), ['.dfm', '.fmx']) then
  begin
    raise Fail(Format('Umwandeln geht nicht: %s steht in %s', [FTarget.Name, ExtractFileName(ALocation.FileName)]));
  end;
  if SameText(ALocation.FileName, FFileName) then
  begin
    FDeclaring.Offsets := FDeclaring.Offsets + [FLines.OffsetAt(ALocation.Range.StartPos)];
  end
  else if UseFileOf(ALocation.FileName, mUseFile) then
  begin
    mUseFile.Source.Offsets := mUseFile.Source.Offsets + [mUseFile.Lines.OffsetAt(ALocation.Range.StartPos)];
  end
  else if Assigned(FContext.ReadText) and FContext.ReadText(ALocation.FileName, mText) then
  begin
    mUseFile := TUseFile.Create;
    FFiles.Add(mUseFile);
    mUseFile.OwnsTree := True;
    mUseFile.Lines := TLineTable.Build(mText);
    mUseFile.Source := TMethodSource.Create(ALocation.FileName, mText, TSyntaxTreeCache.Parse(mText),
      [mUseFile.Lines.OffsetAt(ALocation.Range.StartPos)]);
  end
  else
  begin
    raise Fail(Format('Umwandeln geht nicht: %s lässt sich nicht lesen', [ExtractFileName(ALocation.FileName)]));
  end;
end;

procedure TMethodKindRun.CollectUses;
var
  mLocation: TReferenceLocation;
begin
  FDeclaring := TMethodSource.Create(FFileName, FText, FTree, nil);
  FLines := TLineTable.Build(FText);
  for mLocation in TLspReferences.Find(FResolver, FContext.Index, FTree, FFileName, FTarget.NamePosition, False,
    FContext.Files, FContext.ReadText) do
  begin
    AddUse(mLocation);
  end;
end;

function TMethodKindRun.Convert(const APosition: TTextPosition; AConversion: TMethodConversion): TMethodResult;
var
  mOthers: TArray<TMethodSource>;
  mUseFile: TUseFile;
  mReason: string;
  mDone: Boolean;
begin
  mOthers := nil;
  for mUseFile in FFiles do
  begin
    mOthers := mOthers + [mUseFile.Source];
  end;
  FResolver.PinTree(FTree, FFileName);
  try
    mDone := TMethodWithoutSelf.Execute(FDeclaring, mOthers, APosition, AConversion, FContext.WithStatic, FLookup,
      FContext.Style, Result, mReason);
  finally
    FResolver.UnpinTree;
  end;
  if not mDone then
  begin
    raise Fail('Umwandeln geht nicht: ' + mReason);
  end;
end;

/// <summary>Antwort auf atlas.server.methodKind aus dem Ergebnis AConverted.</summary>
function Answer(const ATitle, AName: string; const AConverted: TMethodResult): TJSONObject;
var
  mItem: TMethodFileEdits;
  mChanges, mWarnings: TJSONArray;
  mEdit, mAnnotation, mAnnotations: TJSONObject;
  mPlaces: Integer;
  mWarning: string;
begin
  mPlaces := 0;
  mChanges := TJSONArray.Create;
  for mItem in AConverted.Files do
  begin
    mChanges.AddElement(EditsJson(TDocumentUris.FromPath(mItem.FileName), mItem.Edits));
    Inc(mPlaces, Length(mItem.Edits));
  end;
  mAnnotation := TJSONObject.Create;
  mAnnotation.AddPair('label', ATitle);
  mAnnotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  mAnnotation.AddPair('description', Format('%s: %d Aufrufe in %d Dateien', [AName, AConverted.Calls,
    Length(AConverted.Files)]));
  mAnnotations := TJSONObject.Create;
  mAnnotations.AddPair(TLspMethodWithoutSelf.AnnotationId, mAnnotation);
  mEdit := TJSONObject.Create;
  mEdit.AddPair('documentChanges', mChanges);
  mEdit.AddPair('changeAnnotations', mAnnotations);
  mWarnings := TJSONArray.Create;
  for mWarning in AConverted.Warnings do
  begin
    mWarnings.Add(mWarning);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('edit', mEdit);
  Result.AddPair('warnings', mWarnings);
  Result.AddPair('places', TJSONNumber.Create(mPlaces));
  Result.AddPair('files', TJSONNumber.Create(Length(AConverted.Files)));
  Result.AddPair('calls', TJSONNumber.Create(AConverted.Calls));
  Result.AddPair('preview', AConverted.Preview);
end;

class function TLspMethodWithoutSelf.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; const AContext: TMethodKindContext): TJSONObject;
var
  mConversion: TMethodConversion;
  mRun: TMethodKindRun;
  mConverted: TMethodResult;
begin
  if not TMethodWithoutSelf.ConversionOf(AContext.Conversion, mConversion) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Umwandlung "%s"',
      [AContext.Conversion]));
  end;
  mRun := TMethodKindRun.Create(AResolver, ATree, AFileName, AText, AContext);
  try
    mRun.FindTarget(APosition);
    mRun.CollectUses;
    mConverted := mRun.Convert(APosition, mConversion);
    Result := Answer(mRun.Target.Title(mConversion), mRun.Target.Name, mConverted);
  finally
    mRun.Free;
  end;
end;

class function TLspMethodWithoutSelf.Markers(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
  const ALookup: TMethodLookup): TArray<TTextPosition>;
var
  Target: TMethodTarget;
begin
  Result := nil;
  for Target in TMethodWithoutSelf.Candidates(AText, ATree, ALookup) do
  begin
    if (Target.HeaderEnd.Line >= ARange.StartPos.Line) and (Target.HeaderEnd.Line <= ARange.EndPos.Line) then
    begin
      Result := Result + [Target.HeaderEnd];
    end;
  end;
end;

end.
