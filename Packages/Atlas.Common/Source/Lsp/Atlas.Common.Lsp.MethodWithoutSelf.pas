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
  Atlas.Common.Lsp.References;

type
  TMethodKindContext = record
    Index: ISymbolIndex;
    /// <summary>Dateien des Projekts für die Referenzsuche.</summary>
    Files: TArray<string>;
    ReadText: TReferenceReadText;
    /// <summary>refactoring.methodKindStatic.</summary>
    WithStatic: Boolean;
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
      const APosition: TTextPosition; const AConversion: string; const AContext: TMethodKindContext;
      const AStyle: TFormatStyle): TJSONObject; static;
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
  Atlas.Common.Lsp.PromoteVariable,
  Atlas.Text.Lines;

class function TLspMethodWithoutSelf.Lookup(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AReadText: TReferenceReadText): TMethodLookup;
begin
  Result := TMethodLookup.FromResolver(AResolver, ATree, AFileName);
  Result.InForm := TLspPromoteVariable.Lookup(AResolver, ATree, AFileName, AReadText).InForm;
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
    Exit;
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

destructor TUseFile.Destroy;
begin
  if OwnsTree then
    Source.Tree.Free;
  inherited;
end;

class function TLspMethodWithoutSelf.Execute(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition; const AConversion: string;
  const AContext: TMethodKindContext; const AStyle: TFormatStyle): TJSONObject;
var
  Conversion: TMethodConversion;
  Target: TMethodTarget;
  Reason, Text, Warning: string;
  Locations: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Files: TArray<TUseFile>;
  UseFile: TUseFile;
  Found: Boolean;
  Others: TArray<TMethodSource>;
  Declaring: TMethodSource;
  Converted: TMethodResult;
  Item: TMethodFileEdits;
  Changes, Warnings: TJSONArray;
  Edit, Annotation, Annotations: TJSONObject;
  Places: Integer;
  MethodLookup: TMethodLookup;
  Lines: TLineTable;
begin
  if not TMethodWithoutSelf.ConversionOf(AConversion, Conversion) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, Format('Unbekannte Umwandlung "%s"', [AConversion]));
  AResolver.PinTree(ATree, AFileName);
  try
    MethodLookup := Lookup(AResolver, ATree, AFileName, AContext.ReadText);
    if not TMethodWithoutSelf.Target(AText, ATree, APosition, MethodLookup, Target, Reason) then
      raise Fail('Umwandeln geht nicht: ' + Reason);
  finally
    AResolver.UnpinTree;
  end;
  Locations := TLspReferences.Find(AResolver, AContext.Index, ATree, AFileName, Target.NamePosition, False,
    AContext.Files, AContext.ReadText);
  Files := nil;
  try
    Declaring := TMethodSource.Create(AFileName, AText, ATree, nil);
    Lines := TLineTable.Build(AText);
    for Location in Locations do
    begin
      if MatchText(ExtractFileExt(Location.FileName), ['.dfm', '.fmx']) then
        raise Fail(Format('Umwandeln geht nicht: %s steht in %s', [Target.Name, ExtractFileName(Location.FileName)]));
      if SameText(Location.FileName, AFileName) then
      begin
        Declaring.Offsets := Declaring.Offsets + [Lines.OffsetAt(Location.Range.StartPos)];
        Continue;
      end;
      Found := False;
      for UseFile in Files do
        if SameText(UseFile.Source.FileName, Location.FileName) then
        begin
          UseFile.Source.Offsets := UseFile.Source.Offsets + [UseFile.Lines.OffsetAt(Location.Range.StartPos)];
          Found := True;
        end;
      if Found then
        Continue;
      if not Assigned(AContext.ReadText) or not AContext.ReadText(Location.FileName, Text) then
        raise Fail(Format('Umwandeln geht nicht: %s lässt sich nicht lesen', [ExtractFileName(Location.FileName)]));
      UseFile := TUseFile.Create;
      Files := Files + [UseFile];
      UseFile.OwnsTree := True;
      UseFile.Lines := TLineTable.Build(Text);
      UseFile.Source := TMethodSource.Create(Location.FileName, Text, TSyntaxTreeCache.Parse(Text),
        [UseFile.Lines.OffsetAt(Location.Range.StartPos)]);
    end;
    Others := nil;
    for UseFile in Files do
      Others := Others + [UseFile.Source];
    AResolver.PinTree(ATree, AFileName);
    try
      if not TMethodWithoutSelf.Execute(Declaring, Others, APosition, Conversion, AContext.WithStatic, MethodLookup, AStyle,
        Converted, Reason) then
        raise Fail('Umwandeln geht nicht: ' + Reason);
    finally
      AResolver.UnpinTree;
    end;
  finally
    for UseFile in Files do
      UseFile.Free;
  end;
  Places := 0;
  Changes := TJSONArray.Create;
  for Item in Converted.Files do
  begin
    Changes.AddElement(EditsJson(TDocumentUris.FromPath(Item.FileName), Item.Edits));
    Inc(Places, Length(Item.Edits));
  end;
  Annotation := TJSONObject.Create;
  Annotation.AddPair('label', Target.Title(Conversion));
  Annotation.AddPair('needsConfirmation', TJSONBool.Create(True));
  Annotation.AddPair('description', Format('%s: %d Aufrufe in %d Dateien', [Target.Name, Converted.Calls,
    Length(Converted.Files)]));
  Annotations := TJSONObject.Create;
  Annotations.AddPair(AnnotationId, Annotation);
  Edit := TJSONObject.Create;
  Edit.AddPair('documentChanges', Changes);
  Edit.AddPair('changeAnnotations', Annotations);
  Warnings := TJSONArray.Create;
  for Warning in Converted.Warnings do
    Warnings.Add(Warning);
  Result := TJSONObject.Create;
  Result.AddPair('edit', Edit);
  Result.AddPair('warnings', Warnings);
  Result.AddPair('places', TJSONNumber.Create(Places));
  Result.AddPair('files', TJSONNumber.Create(Length(Converted.Files)));
  Result.AddPair('calls', TJSONNumber.Create(Converted.Calls));
  Result.AddPair('preview', Converted.Preview);
end;

class function TLspMethodWithoutSelf.Markers(ATree: TSyntaxTree; const AText: string; const ARange: TTextRange;
  const ALookup: TMethodLookup): TArray<TTextPosition>;
var
  Target: TMethodTarget;
begin
  Result := nil;
  for Target in TMethodWithoutSelf.Candidates(AText, ATree, ALookup) do
    if (Target.HeaderEnd.Line >= ARange.StartPos.Line) and (Target.HeaderEnd.Line <= ARange.EndPos.Line) then
      Result := Result + [Target.HeaderEnd];
end;

end.
