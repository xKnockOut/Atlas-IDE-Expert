unit Atlas.Common.Lsp.Completion.TestSupport;

// Gemeinsame Hilfen der Vervollständigungstests (Atlas.Common.Lsp.Completion.Tests und .Proposals.Tests).

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion.Values;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBasis = class'#10 +
    '    Zaehler: Integer;'#10 +
    '    procedure Melde;'#10 +
    '  end;'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Versteckt;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBasis.Melde;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class(TBasis)'#10 +
    '    Name: string;'#10 +
    '    procedure Bar(Anzahl: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +
    'var'#10 +
    '  Wert: TFoo;'#10 +
    'begin'#10 +
    '  { Kommentar Wert } |'#10 +
    'end;'#10 +
    'end.';

{ TLspCompletionTests }

type
  /// <summary>Gemeinsamer Aufbau der Vervollständigungstests: Index mit der Unit Werkzeug und Namensauflöser.
  /// </summary>
  TLspCompletionTestCase = class
  protected
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    /// <summary>Index mit Werkzeug und Auflöser anlegen.</summary>
    procedure Prepare;
    /// <summary>Index und Auflöser freigeben.</summary>
    procedure Release;
    /// <summary>Vorschläge an AMarker mit Präfix-Abgleich.</summary>
    function ItemsAt(const AText, AMarker: string): TCompletionItems; overload;
    /// <summary>Vorschläge an AMarker mit dem Abgleich AMatching.</summary>
    function ItemsAt(const AText, AMarker: string; AMatching: TCompletionMatching): TCompletionItems; overload;
    /// <summary>Namen der Vorschläge, durch Leerzeichen getrennt.</summary>
    function Names(const AItems: TCompletionItems): string;
    /// <summary>Vorschlag „alle Felder zuweisen“ an AMarker.</summary>
    function AssignItem(const AText, AMarker: string; ASnippets, AOn: Boolean; out AItem: TCompletionItem): Boolean;
  end;

/// <summary>Position direkt hinter AMarker in AText; Ausnahme, wenn AMarker fehlt.</summary>
function PositionOf(const AText, AMarker: string): TTextPosition;

/// <summary>Unit Haupt mit ACode an der Stelle des Platzhalters.</summary>
function WithCode(const ACode: string): string;
/// <summary>Was TCompletionValues aus der Datei HauptFile braucht.</summary>
function LookupOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AText: string;
  const AReadText: TCompletionReadText): TEnumLookup;
/// <summary>Anfrage an APosition mit Auflöser, Index, Baum und Lesen aus ALookup; der Aufrufer gibt sie frei.
/// </summary>
function RequestOf(const ALookup: TEnumLookup; const APosition: TTextPosition): TCompletionRequest;
/// <summary>TCompletionValues.EnumItems an APosition.</summary>
function EnumAt(const ALookup: TEnumLookup; const APosition: TTextPosition; out AItems: TArray<TCompletionItem>;
  out ASetMode: Boolean): Boolean;
/// <summary>TCompletionValues.DeclareItems an APosition.</summary>
function DeclareAt(const ALookup: TEnumLookup; const APosition: TTextPosition; AInlineVar: Boolean;
  const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean;

implementation

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
  begin
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function WithCode(const ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, '  { Kommentar Wert } |', ACode, []);
end;

/// <summary>Was TCompletionValues aus der Datei HauptFile braucht.</summary>
function LookupOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AText: string;
  const AReadText: TCompletionReadText): TEnumLookup;
begin
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.Tree := ATree;
  Result.Text := AText;
  Result.FileName := HauptFile;
  Result.ReadText := AReadText;
end;

/// <summary>Anfrage an APosition mit Auflöser, Index, Baum und Lesen aus ALookup; der Aufrufer gibt sie frei.
/// </summary>
function RequestOf(const ALookup: TEnumLookup; const APosition: TTextPosition): TCompletionRequest;
begin
  Result := TCompletionRequest.Create(ALookup.Text, ALookup.FileName, APosition);
  Result.Tree := ALookup.Tree;
  Result.Resolver := ALookup.Resolver;
  Result.Index := ALookup.Index;
  Result.ReadText := ALookup.ReadText;
  Result.Matching := TCompletionMatching.Fuzzy;
end;

/// <summary>TCompletionValues.EnumItems an APosition.</summary>
function EnumAt(const ALookup: TEnumLookup; const APosition: TTextPosition; out AItems: TArray<TCompletionItem>;
  out ASetMode: Boolean): Boolean;
var
  mRequest: TCompletionRequest;
begin
  mRequest := RequestOf(ALookup, APosition);
  try
    Result := TCompletionValues.EnumItems(mRequest, AItems, ASetMode);
  finally
    mRequest.Free;
  end;
end;

/// <summary>TCompletionValues.DeclareItems an APosition.</summary>
function DeclareAt(const ALookup: TEnumLookup; const APosition: TTextPosition; AInlineVar: Boolean;
  const AKnown: TArray<TCompletionItem>; out AItems: TArray<TCompletionItem>): Boolean;
var
  mRequest: TCompletionRequest;
begin
  mRequest := RequestOf(ALookup, APosition);
  try
    Result := TCompletionValues.DeclareItems(mRequest, AInlineVar, AKnown, AItems);
  finally
    mRequest.Free;
  end;
end;

procedure TLspCompletionTestCase.Prepare;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspCompletionTestCase.Release;
begin
  FreeAndNil(FResolver);
  FIndex := nil;
end;

function TLspCompletionTestCase.ItemsAt(const AText, AMarker: string): TCompletionItems;
begin
  Result := ItemsAt(AText, AMarker, TCompletionMatching.Prefix);
end;

function TLspCompletionTestCase.ItemsAt(const AText, AMarker: string;
  AMatching: TCompletionMatching): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(AText, AMarker), AMatching);
  finally
    Tree.Free;
  end;
end;

function TLspCompletionTestCase.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
  begin
    Result := Result + Item.Name + ' ';
  end;
  Result := Result.Trim;
end;

function TLspCompletionTestCase.AssignItem(const AText, AMarker: string; ASnippets, AOn: Boolean;
  out AItem: TCompletionItem): Boolean;
var
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
  Settings: TCompletionSettings;
begin
  Tree := TPascalParser.Parse(AText);
  Request := TCompletionRequest.Create(AText, HauptFile, PositionOf(AText, AMarker));
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Settings := TCompletionSettings.Default;
    Settings.AssignAllFields := AOn;
    Request.Settings := Settings;
    Result := TCompletionValues.AssignAllItem(Request, ASnippets, AItem);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

end.
